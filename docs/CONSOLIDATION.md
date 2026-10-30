# Consolidation record — 2026-10-30

## Provenance

- Upstream: https://github.com/end-4/dots-hyprland, main at
  `2f2a376fdb2ad738bf55f693dd0b474b64bb0ab8`, fetched 2026-10-30.
- Original checkout: `~/.config/end-4`, custom at `356b26ad` plus dirty and
  untracked changes. It remains untouched.
- Rebased four custom commits onto upstream main, retaining fish/Kitty/KDE,
  monitor, recording, icons and Qt compatibility history.
- Merged later source from `~/.config/quickshell/ii` and `~/.config/hypr`.
  Both are copies, not symlinks. No production file or service was changed.
- Shapes remains upstream submodule `e31ec4cb4ebf6a46b267f5c42eabf6874916fa16`;
  a byte comparison with the live copy found no difference.

## Reconciliation choices

Three inputs were compared: original committed custom HEAD, its working tree,
and live source. Those results were merged against the rebased tree.
`reconciliation.json` inventories differences, including missing live optional
resources; missing files were retained rather than interpreted as deletions.
`reconciliation-decisions.json` records 26 legacy/live conflicts resolved to the
later live implementations. All 34 untracked old-checkout sources also exist
live; none was uniquely stranded in that checkout.

The active Spotlight/controller/drawer replaces the earlier overview search UI.
Later Settings editors, schema, launcher helpers and icon policy take precedence.
Optional upstream Waffle/Fluent resources and reusable calendar widgets remain.
Upstream changes and custom changes rebased without Git conflicts. Static parsing
cannot establish compatibility of all Hyprland runtime APIs.

Preserved feature groups include Settings and clock fonts; Spotlight and app
management; HA/Music Assistant/Borg Intelligence; Bed Lock and sleep UI; Lens Cap
and shared tool_app; adaptive icons/SteamGridDB; recording, bar/background/media;
monitor/bed-mode scripts; current lock helpers and disabled hypridle.

Additional supporting source: the T3/VS Code palette systemd units and
`~/.local/bin/quickshell-t3-theme-sync`. They are tracked but not enabled or
included in the narrow desktop migration tool.

Cleanup removes backup/cache artifacts and the obsolete Icon Studio desktop
launcher (its launch script is absent). Generated Hyprlock colors/config and
wallpaper links stay machine-local. Font license files accompany the fonts.
No credentials or preferences were imported. Secret-service bridges are source;
keyring contents are not. A pattern scan of source and custom history checks
credential signatures without printing values; it is not a credential guarantee.

## Runtime and deployment limits

This execution environment exposes no active Hyprland/Quickshell process or
compositor socket. Do not infer the user's desktop is stopped. No session
reload, restart, lock, input, audio/monitor command, or service action was run.

The Lua entrypoint, settings source, tests, dependencies and source structure can
be inspected here. Physical lock/unlock, startup, Bed Lock, monitor topology,
recording/audio, right-click/Polkit flows, and exact visible fidelity require a
suitable isolated desktop session before any production migration.

Full shell startup is unsafe as a simple offscreen test: it runs external
commands and cache cleanup. See VALIDATION.md. The deployment tool defaults to a
plan and requires passing source-bound validation plus runtime verification.
The initial report deliberately records runtime verification as false.

Lens Cap's `lens-cap`/`lens-calibration` launchers, desktop entry, and MIME
registration are included as supporting source. The desktop Exec uses PATH
rather than an absolute home path; its generated icon remains local icon state.
The installed uninstall helper and Polkit policy were compared byte-for-byte
with their corresponding scripts and policy in this repo; they match. Installing
these system-wide files remains a separate privileged operation, outside deploy.
