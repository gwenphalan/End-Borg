# Display resume on unimatrix-02

The Nov 15–16 S3 incident left the desktop alive and all outputs reporting
DPMS enabled, but physical displays had no signal. A user-confirmed DPMS off/on
cycle recovered video without restarting applications. Untimestamped atomic
modeset failures support a graphics restoration hypothesis but cannot establish
when or why this incident occurred.

Hypridle's `general.after_sleep_cmd` now invokes `display_wake.py`.
The first trial uses the standard explicit DPMS-on action, with bounded retries
only when dispatch is rejected or times out. An accepted command is not physical
recovery evidence. The helper never uses DPMS status as a physical-health oracle.
It discovers the current compositor rather than retaining a numeric instance.

`python3 ~/.config/hypr/hyprland/scripts/display_wake.py --reinitialize`
provides the observed off/on recovery as an explicit, bounded operator action.
It is not the automatic hook until controlled trials support that choice.
Neither path edits monitor rules, refresh rates, mirroring, lock or Bed Lock state,
or restarts applications. No NVIDIA service, kernel or BIOS setting is changed.

## Ownership and deployment

This task's historical worktree predates End-Borg consolidation. Its obsolete
Quickshell lock/focus hooks were reconciled to canonical/live `lock-session.sh`.
Canonical ownership is `/home/gwenp/repositories/end-borg/dots/.config/hypr`.
The canonical `tools/deploy.py` is used with a sparse source containing only
`hypr/hypridle.conf` and `hypr/hyprland/scripts/display_wake.py`, a fresh baseline
of reviewed live content, exact source digest, private backups and drift checks.
Unrelated canonical dirty files and the historical worktree's other configs
must not be deployed. Canonical startup must retain the current live Hypridle
startup; that single-line reconciliation does not require a compositor reload.

Local logs and deployment attestations belong under ignored `local/display-wake/`.
A pretrial deployment uses truthful partial-runtime authorization: config/helper
smoke success does not attest physical sleep/wake success.

## Controlled trial

1. Obtain the user's readiness before lock/suspend. Capture UTC time, discovered
   compositor signature, monitor state including `monitors all`, lock state and
   compositor log byte offset. Do not infer active processes from a sandbox.
2. Leave lock command, `before_sleep_cmd`, `inhibit_sleep=3`, and idle timers
   unchanged. Restart only the already-running Hypridle with its existing session
   environment to load the config. Capture its startup log and confirm one owner.
3. Suspend through logind after the user is ready. Let the user wake the machine.
   Before recovery commands, ask whether DP-2, HDMI-A-1 and mirrored DP-3 physically
   display video. Record each output and time to video; user confirmation is required.
4. Capture kernel, suspend, helper and user journals since baseline; save only new
   compositor bytes with the bounding UTC times. Its lines lack intrinsic timestamps.
   Compare names, resolution, refresh, position, scale, transform and mirrorOf.
5. If physically dark despite accepted on: capture that failure first, invoke
   `--reinitialize` once, then capture/confirm again. Promote an automatic bounded
   cycle only if supported by this result and repeat a controlled sleep trial.
6. A successful short test does not prove overnight reliability or identify the
   driver/platform cause. Do not obscure those limits with DPMS=true.

## Rollback

Use canonical `tools/deploy.py rollback --backup BACKUP` to review, then add
`--apply` to restore the exact transaction. It refuses post-deployment drift.
Restart only Hypridle with its session environment to load the restored config.
Restore the canonical source config/startup reconciliation and remove the new
helper only if their hashes still match this task's writes. Preserve unrelated
source work. The live transaction covers only the config and helper; its rollback
leaves Hypridle startup unchanged. Restoring the original source
`hyprland/execs.lua`, however, removes `hl.exec_cmd("hypridle")`. After a later
source deployment and login, Hypridle may then fail to start, leaving its idle,
lock and sleep hooks inactive. To roll back only the wake fix while preserving
current idle/lock behavior, retain that startup line or provide another Hypridle
startup mechanism, then verify exactly one instance is running after login.
Exact paths and results are appended after deployment.

## Deployed and physically checked — 2026-11-16

Canonical source config/helper and the offline tests were updated. Canonical
`hyprland/execs.lua` was reconciled from its stale disabled comment to the existing
live Hypridle startup; unrelated dirty edits in that file were preserved. The
live deployment touched only the config and new helper. No compositor/shell
restart or monitor-rule change was performed. Only Hypridle was restarted,
using its previous environment, and verified as the sole running owner.

Validation:

- Canonical `python3 tools/validate.py`: zero failures, including after the new
  helper and canonical source reconciliation.
- `python3 -B -m unittest discover -s tests -p test_display_wake.py -v`: 10 passed.
- Canonical deployment suite: 14 passed. Rollback dry-run verified exact two paths.
- Host read-only preflight discovered the current compositor; ordinary on-only
  smoke returned `ok`. Hypridle startup accepted the config and retained all
  three listeners plus lock-notify sleep inhibition.
- User explicitly authorized the controlled trial and confirmed: **all three
  physical displays returned normally**. No manual recovery/cycle was issued.
- Kernel recorded S3/deep entry at **04:37:10 MST** and suspend exit at
  **04:37:28 MST**. Hypridle logged Wayland lock before releasing its delay
  inhibitor, then invoked the after-sleep hook on `PrepareForSleep(false)`.
  First on dispatch was accepted at **04:37:29.141 MST**.
- All three outputs retained resolution, refresh rate, geometry, scale, transform,
  enabled state and mirroring; all four original application windows survived.
  Checked preferences, lock helpers and monitor config hashes were unchanged.
- Newly captured compositor lines contain no atomic-restore/EINVAL failure;
  kernel capture has no NVRM/Xid/NV_ERR match. USB-controller resume reset and
  NVIDIA HDMI pixel-clock warnings occurred during this successful recovery;
  their presence does not prove they caused the original failure.

The initial normal suspend request was refused by T3's sole **block** inhibitor
(`Agents are working`). The controlled trial used
`systemctl --check-inhibitors=no suspend`; the installed systemd manual specifies
that this skips block inhibitors and has no effect on **delay** inhibitors.
Logs independently confirm the original Hypridle lock-before-sleep delay ran.
No inhibitor process or persistent inhibitor setting was changed.

The standard on hook was sufficient for this one short S3 trial; there is no
current trial evidence requiring an automatic cycle. The helper's command-error
retry path and explicit reinitialization path have offline tests only, and were
not needed in the physical trial. This does not reproduce the original overnight
failure, prove its root cause, or establish long-duration reliability. Actual
time-to-video was not instrumented; the user reported normal recovery.

Private evidence in this worktree: `local/display-wake/before/`, `after/`,
`hypridle-activation.log`, `deployment.json`, `validation.json`,
`physical-validation.json`, and `rollback-plan.json`.
The original predeployment report/journal intentionally retain their
partial-runtime status; subsequent physical evidence is recorded separately.

Live backup/rollback journal:
`/home/gwenp/.local/state/end-borg/backups/display-wake-20261116T1135Z/transaction.json`.

Exact live rollback (reviewed dry-run; not applied):

```sh
python3 /home/gwenp/repositories/end-borg/tools/deploy.py rollback \
  --backup /home/gwenp/.local/state/end-borg/backups/display-wake-20261116T1135Z
# Add --apply to restore the original config and remove the new helper.
```

Then restart only the active Hypridle with its current session environment.
For source rollback, original canonical `hypridle.conf` and `execs.lua` copies
are in this worktree's ignored `local/display-wake/canonical-before/`; reconcile
only this task's changed lines after checking for subsequent source edits.
Do not overwrite all of execs.lua with that backup if unrelated edits arrived.
Remove this task's canonical helper/test and restore the worktree config hook
as appropriate, so a future source deployment does not reapply the change.

References: [Hypridle general hooks](https://wiki.hypr.land/hypr-ecosystem/user/hypridle/),
[systemd login API](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.login1.html).
