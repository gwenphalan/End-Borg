"""Conservative metadata-only product-family inference for shared backplates."""
from collections import defaultdict
from pathlib import Path
import re
import shlex
import shutil
TRANSPORTS = {"sh", "bash", "dash", "zsh", "fish", "python", "pypy", "ruby",
              "perl", "node", "java", "electron", "flatpak", "gtk-launch", "xdg-open"}


def _tokens(value):
    return set(re.findall(r"[a-z0-9]+", value.casefold()))

def _is_transport(program):
    return re.sub(r"[0-9.]+$", "", program.casefold()) in TRANSPORTS


def _executable(desktop):
    """Parse launch metadata without running it or grouping generic transports."""
    try:
        command = shlex.split(desktop.get("exec", ""))
    except ValueError:
        return None
    if not command:
        return None
    if Path(command[0]).name == "env":
        command = command[1:]
        while command and ("=" in command[0] or command[0] == "--"):
            command.pop(0)
        if not command or command[0].startswith("-"):
            return None
    program = Path(command[0]).name
    if _is_transport(program):
        return None
    if any("://" in argument for argument in command[1:]):
        return None
    resolved = shutil.which(command[0])
    return Path(resolved).resolve() if resolved else Path(command[0])


def infer_families(desktops):
    """Return groups only when all members share the same corroborated evidence.

    Branding must occur in both a display-name prefix and an independent desktop
    identifier/icon/WMClass/executable token. Broad vendor namespaces alone never
    establish a family. Groups are not transitively unioned.
    """
    identities, binaries, labels = {}, {}, {}
    for app_id, desktop in desktops.items():
        executable = _executable(desktop)
        binaries[app_id] = executable
        icon = desktop.get("icon", "")
        if icon.startswith(("application-", "applications-", "preferences-", "utilities-")):
            icon = ""
        if Path(icon).is_absolute():
            icon = Path(icon).stem
        tokens = _tokens(" ".join((app_id, icon, desktop.get("startupwmclass", ""))))
        if executable:
            tokens.update(_tokens(executable.name))
            for root in (Path("/usr/lib"), Path("/usr/lib64"), Path("/opt")):
                if executable.is_absolute() and executable.is_relative_to(root):
                    relative = executable.relative_to(root)
                    if len(relative.parts) >= 2 and relative.parts[0] not in ("bin", "libexec"):
                        tokens.update(_tokens(relative.parts[0]))
            tokens.update(re.sub(r"[0-9]+$", "", token) for token in tuple(tokens))
        identities[app_id] = tokens
        name = desktop.get("name", "").split()
        prefix = name[0].casefold() if name else ""
        labels[app_id] = prefix if prefix.isalnum() and len(prefix) >= 2 else ""
    candidates = defaultdict(set)
    for app_id, executable in binaries.items():
        if not executable:
            continue
        stem = re.sub(r"[0-9]+$", "", executable.name.casefold())
        if stem in _tokens(app_id) or stem == labels[app_id]:
            candidates[(0, "executable:" + str(executable))].add(app_id)
    # Every member must corroborate its own label; sharing an author namespace
    # or a common installation directory never admits an unrelated sibling.
    brands = {label for label in labels.values() if label and
              not _is_transport(label) and
              sum(labels[key] == label and label in identities[key] for key in desktops) >= 2}
    for brand in brands:
        for app_id in desktops:
            if labels[app_id] == brand and brand in identities[app_id]:
                candidates[(1, "brand:" + brand)].add(app_id)
    # A real full product ID can anchor its own components; an author/vendor
    # prefix with no product entry cannot group unrelated applications.
    for anchor in desktops:
        if anchor.count(".") >= 2:
            for app_id in desktops:
                if app_id == anchor or app_id.startswith(anchor + "."):
                    candidates[(2, "product:" + anchor)].add(app_id)
    choices = defaultdict(list)
    for candidate, members in candidates.items():
        if len(members) >= 2:
            for app_id in members:
                choices[app_id].append(candidate)
    selected = {}
    # An executable shared by only a subset of a corroborated brand should not
    # split that brand into inconsistent background groups.
    for app_id, options in choices.items():
        selected[app_id] = min(options, key=lambda option: (-len(candidates[option]), option))
    groups = defaultdict(list)
    for app_id, candidate in selected.items():
        groups[candidate].append(app_id)
    result = {}
    for (_, key), members in sorted(groups.items()):
        if len(members) < 2:
            continue
        for app_id in members:
            result[app_id] = {"key": key, "members": sorted(members),
                              "evidence": key.split(":", 1)[0]}
    return result
