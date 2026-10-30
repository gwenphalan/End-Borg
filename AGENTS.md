# End-Borg agent guide

End-Borg is a personal fork of end-4/dots-hyprland. Preserve upstream history,
GPL licensing, and attribution. `upstream` tracks end-4; `origin` is End-Borg.
Read docs/CONSOLIDATION.md and docs/VALIDATION.md before desktop work.

## Source and runtime boundaries

- Work in this repo, never directly in ~/.config to implement a change.
- The production trees are copies, not symlinks. Never run upstream `setup` to
  deploy this fork. Use the scoped migration procedure in docs/DEPLOYMENT.md.
- Never reload/restart/lock/unlock the desktop or enable services as a test.
  The user explicitly requires an undisturbed running desktop.
- Preserve the selected locker, disabled hypridle, current input bindings,
  monitor topology, sleep/Bed Lock behavior, and existing Settings UX.
- Never publish config.json, keys, tokens, keyring contents, runtime state,
  camera captures, user projects, generated lock files, caches or backups.
- Runtime preferences remain in ~/.config/illogical-impulse/config.json;
  keyring credentials and ~/.local/state/quickshell remain machine-local.
- Keep external theme-sync services/scripts in Git, but do not activate them
  during staging. Fish/Kitty/KDE custom commits are retained history, outside
  the scoped desktop deployment.
- Preserve the rounded-polygon shapes Git submodule and initialize it before
  validation. Do not replace its gitlink with loose source files.

## Changes and verification

- Reconcile live, legacy checkout, and upstream file by file. Missing live
  optional upstream resources do not imply deletion.
- Use subagents for substantial investigation, planning and implementation.
- Keep edits narrowly scoped. Do not redesign or swap backends during cleanup.
- Read nested AGENTS.md before modifying shared tool_app components.
- Run python tools/validate.py and the documented isolated source tests.
- Use temporary HOME and all XDG roots; unset compositor/session bus access.
  Qt offscreen alone is unsafe: startup code invokes external helpers and
  cleans shared paths. Never run shell.qml as a smoke test on the live session.
- Distinguish static validation, isolated automated tests, rendered artifact
  verification and physical desktop behavior. Do not call the latter tested
  without observing it. A passing process exit is insufficient for QtTest;
  inspect the TOTAL failure count.
- Recheck source and target drift before deployment. Back up only after
  planning, deploy atomically, and retain an exact rollback manifest.
