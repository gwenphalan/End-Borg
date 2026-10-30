# Deployment record — 2026-10-30

The user explicitly authorized deploying End-Borg and granted full host access.
Deployment is complete. The source repository remains at
`~/repositories/end-borg`; production configuration remains a separate copy.

## Applied changes

- Applied 426 reviewed Quickshell/Hyprland source copies, including restored
  optional upstream resources and the upstream configuration updates.
- Preserved concurrent live Sleep integration changes in the repository,
  including disabled-day/off-phase handling. The final managed source comparison
  is exact; generated runtime files remain excluded.
- Updated the Lens Cap desktop entry to the staged PATH-based launcher.
- Existing Lens Cap launchers/MIME registration, palette services/helper, and
  privileged uninstall helper/policy already matched the repository and were
  verified in place. Palette watchers were already active.
- Repaired missing-player reads in the bar and stale notification timers/default
  bindings, then deployed those two files in a separate rollback transaction.
- Quickshell and existing Settings processes hot-reloaded. Hyprland configuration
  was explicitly reloaded and reported no configuration errors.

The original end-4 checkout, private preferences, keyring credentials, generated
lock appearance, monitor modes and volume were preserved. No package upgrades,
compositor restart, logout, forced lock/unlock, alarm, light, or playback action
was performed. Retained Fish/Kitty/KDE history is outside this desktop deployment.

## Verification

All source/offline checks passed, along with 14 deployment tests, eight JavaScript
harnesses, seven isolated tool-app UI checks and eight QML/controller/process
checks. See [VALIDATION.md](VALIDATION.md) for exact coverage and limitations.

Live checks verified shell and Settings configuration loads, launcher IPC,
Home Assistant REST/websocket health, fresh Bed Lock data, Music Assistant
service discovery, Borg model discovery, both monitor geometries/modes, and
unchanged preferences and volume. Actual notification delivery and immediate
closure exercised the repaired timer path. The log after the final reload had
no QML binding TypeError/ReferenceError/undefined-assignment diagnostics. The bar
and Settings were inspected in private before/after captures.

The deployment used the explicit partial-runtime path: its journal retains
`runtime_validated: false`. This records the incomplete isolated Lens Cap GUI
run and absence of physical authentication/alarm/device/reboot trials; it does
not mean those tests passed. Subsequent live smoke checks are recorded separately.
The virtual KWin compositor crashed during the longer isolated UI runs.

## Backups and rollback

Verified backup root:

```text
~/.local/state/end-borg/backups/20261030T130924Z/
```

`before/` contains the verified pre-deployment source, preferences, persistent
state, launchers and supporting units (1,122 entries checked). Each source apply
also created a content/mode-verified transaction journal. Private plans, session
logs, screenshots and validation records are ignored under repository `local/`.

Rollback source changes in reverse order, planning each first:

```sh
python tools/deploy.py rollback --backup "$HOME/.local/state/end-borg/backups/20261030T130924Z/null-safety-repair"
python tools/deploy.py rollback --backup "$HOME/.local/state/end-borg/backups/20261030T130924Z/null-safety-repair" --apply
python tools/deploy.py rollback --backup "$HOME/.local/state/end-borg/backups/20261030T130924Z/desktop-transaction"
python tools/deploy.py rollback --backup "$HOME/.local/state/end-borg/backups/20261030T130924Z/desktop-transaction" --apply
```

The tools refuse to overwrite later live edits. The supporting desktop-entry
transaction is recorded separately in `supporting-transaction.json`; its original
is `before/.local/share/applications/lens-calibration.desktop`. Review its current
hash against the journal before restoring that single file. Do not restore the
entire backup tree over newer edits. Rollback does not itself reload services.
