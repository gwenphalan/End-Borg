# End-Borg

A personal fork of [end-4's illogical-impulse desktop](https://github.com/end-4/dots-hyprland),
built around Quickshell and Hyprland. End-Borg brings the customizations from Gwen's
running desktop back into version control while preserving upstream history and resources.

The initial consolidation rebases four existing custom commits onto upstream main
at `2f2a376f`, then reconciles the later live configuration with the original checkout.
The full provenance and reconciliation decisions are in the
[consolidation record](docs/CONSOLIDATION.md).

## Customizations

| Area | Included source |
| --- | --- |
| Launcher | Spotlight search, app drawer, clipboard integration, pin/hide controls, and uninstall tooling |
| Settings | Desktop settings catalog and editors, appearance controls, and variable clock fonts |
| Home automation | Home Assistant integration, Bed Lock, sleep schedules, and bedtime delay controls |
| Media and intelligence | Music Assistant, desktop media controls, Borg Intelligence, and recording tools |
| App icons | Adaptive icon modes and families, SteamGridDB integration, and icon generation/publication tooling |
| Lens Cap | Lens calibration and annotation tools, project workflows, and Blender/LabelMe integration |
| Shared tools | Reusable Quickshell tool-app components, document workflows, profiles, and worker protocols |
| Desktop | Custom bars, backgrounds, lock helpers, keybindings, monitor controls, and bed-mode scripts |
| Theme integration | Quickshell palette synchronization for T3 Code and VS Code |

Optional upstream Waffle components, Fluent icons, and shared widgets remain available.
Existing Fish, Kitty, and KDE changes are preserved in the fork's history.

## Current status

**Deployed to the current desktop on 2026-10-30.** Quickshell reloaded
successfully and Hyprland accepted the deployed configuration. The deployment
preserved desktop preferences, generated lock appearance, monitor modes and
volume, with verified backups and rollback journals.

Live checks passed for Home Assistant, fresh Bed Lock data, Music Assistant
service discovery, Borg model discovery, notifications, and launcher IPC. The
bar and Settings were inspected on the running desktop. Two null-handling bugs
found in media bindings and notification timers were repaired during verification.

Automated checks passed 409 source Python tests, 14 deployment/rollback tests,
eight JavaScript harnesses, and parsing checks across 741 QML files. Isolated
runtime tests added seven shared-tool UI checks and eight QML/controller/process
tests. See [validation details](docs/VALIDATION.md) and the
[deployment record](docs/DEPLOYED.md) for scope and evidence.

Physical authentication, alarm/light/audio actions, reboot behavior, and complete
Lens Cap GUI/export workflows were not exercised as part of deployment. The
private virtual compositor crashed during the longer Lens Cap tests; successful
QML loading is recorded separately from completed UI testing.

## Working with the source

Clone with submodules:

```sh
git clone --recurse-submodules https://github.com/gwenphalan/End-Borg.git ~/repositories/end-borg
cd ~/repositories/end-borg
```

For an existing clone:

```sh
git submodule update --init --recursive
```

This is a personalized desktop source tree, not a universal installer. Hardware
settings, service endpoints, dependencies, and credentials need host-specific
configuration. The inherited upstream `setup` script must not be used to migrate
an existing customized desktop.

| Path | Purpose |
| --- | --- |
| `dots/.config/quickshell/ii/` | Desktop shell, Settings, Lens Cap, services, scripts, and tests |
| `dots/.config/hypr/` | Hyprland configuration, monitor/keybinding customizations, and lock helpers |
| `dots/.config/systemd/user/` | Supporting palette synchronization units |
| `dots/.local/` | Supporting launchers, desktop entries, and MIME registration |
| `tools/validate.py` | Static checks and the reviewed offline test allowlist |
| `tools/deploy.py` | Scoped migration planning, backup, deployment, and rollback |
| `docs/` | Consolidation, validation, and deployment records |
| `AGENTS.md` | Instructions for agents working on this fork |

## Validation

Run from the repository root, after provisioning the dependencies described in
[VALIDATION.md](docs/VALIDATION.md):

```sh
# Source checks only
python tools/validate.py

# Source checks and reviewed offline tests
python tools/validate.py --tests

# Include Lens Cap tests using its existing dependency environment
python tools/validate.py --tests \
  --lens-python "$HOME/.local/share/lens-calibration/venv/bin/python"

# Exercise migration and rollback against temporary targets
python -m unittest discover -s tests -p test_deploy.py -v
```

The validator uses temporary HOME/XDG directories for its offline tests. Do not
start another desktop shell as a smoke test: shell initialization runs external
helpers and cleans cache paths, even when Qt renders offscreen.

## Deployment and local data

Follow [DEPLOYMENT.md](docs/DEPLOYMENT.md) to capture a baseline and review a
migration plan. The deployment tool defaults to a dry-run, manages only the
Quickshell and Hyprland source paths, and requires validation for the exact source
being applied. It checks for live drift, backs up touched files, and supports
rollback. It does not reload the desktop or activate services.

The live configuration remains a separate copy of the source. Personal settings
in `~/.config/illogical-impulse/config.json`, keyring credentials, runtime state,
user documents, generated assets, and migration backups stay outside Git.
Supporting services, Lens Cap registration, and privileged uninstall components
have separate installation requirements documented in the deployment guide.

## Credits and license

End-Borg builds on [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
and its contributors. The upstream [GPL-3.0 license](LICENSE) remains in effect.
Bundled fonts and other third-party assets retain their accompanying licenses;
the rounded-polygon shapes library remains an upstream Git submodule.
