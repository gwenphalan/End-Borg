# Staging and deployment

The repository is the source tree; the running desktop uses separate copies. Do not run upstream `setup` to deploy this fork. Keep staging separate from the live session. Reload or activate only after an explicit deployment instruction, and verify both shell and compositor are unlocked before restarting a shell. Do not force lock/authentication, audio, alarm, or light trials as incidental checks. Host runtime commands must use the active desktop's session environment; a sandbox process listing alone cannot establish whether the desktop is running. The completed deployment and remaining test limits are recorded in [DEPLOYED.md](DEPLOYED.md).

`tools/deploy.py` manages only `dots/.config/quickshell/ii` and `dots/.config/hypr`. It copies changed files only and never removes existing live-only files. It excludes backup/cache artifacts and generated Hyprlock configuration, lock wallpapers and generated color files. Personal settings under `~/.config/illogical-impulse`, Secret Service credentials and all XDG state/data/cache stores are outside its scope. Supporting theme services and helper installations require separate reviewed deployment.

First take a baseline before staging changes. The baseline contains content hashes, permissions and symlink targets, never file contents. Keep `local/` ignored and private:

```sh
python3 tools/deploy.py snapshot
python3 tools/deploy.py plan > local/deployment-plan.json
```

All actions default to dry-run except explicit baseline snapshot creation. `deploy` without `--apply` is also a plan. Review the exact changed paths and `drift` array. Any live drift since the original baseline blocks apply; inspect and reconcile it rather than replacing the baseline to bypass the check. Existing baseline files are never overwritten by the CLI. Refresh a baseline only after deliberately archiving it and reviewing subsequent live edits.

Complete static and isolated runtime validation, including the requested desktop features. Save a JSON validation report with these required fields:

```json
{
  "passed": true,
  "runtime_validated": true,
  "source_manifest_sha256": "the exact digest printed by the deployment plan"
}
```

Record actual commands, results and runtime evidence alongside those fields. `passed` means all required checks passed. Set `runtime_validated` to false when runtime checks are unavailable; do not promote static checks into a runtime claim. A source change invalidates the report digest. These fields are an operator attestation, not an automatic behavioral test.

Once the concrete plan and validation evidence are acceptable, application requires both flags:

```sh
python3 tools/deploy.py deploy --apply --validated local/validation.json
```

Before any live write the tool backs up every changed existing file, verifies backup content and modes, and rechecks source/live drift. Backups default to a fresh timestamped directory under `~/.local/state/end-borg/backups/`; `--backup /absolute/external/directory` can select a new directory outside source and target. The transaction journal includes before/after hashes and the exact touched paths. Files and symlinks are replaced atomically one at a time. The whole tree is not an atomic transaction: an interrupted apply can leave a partial deployment. Keep the printed backup path and use its journal to roll back. The tool does not reload, restart or activate anything.

Plan rollback first, then restore only the exact touched paths:

```sh
python3 tools/deploy.py rollback --backup /absolute/backup/directory
python3 tools/deploy.py rollback --backup /absolute/backup/directory --apply
```

Rollback verifies backups, refuses to overwrite edits made after deployment, restores original content/permissions/symlinks and removes newly created files. Already restored or unapplied entries are skipped, so partial transactions are recoverable. Empty directories created by deployment remain. Neither apply nor rollback follows symlink ancestors in the managed tree. Ordinary filesystem race protection cannot eliminate changes by another process between the final check and replacement; perform deployment during a controlled maintenance window.

Test the deploy mechanism with temporary targets only:

```sh
python3 -m unittest discover -s tests -p test_deploy.py -v
```

Supporting sources also include Lens Cap launchers, desktop/MIME registration,
and the uninstall helper/Polkit policy. The narrow migration tool intentionally
leaves these existing installations in place. Do not activate them by running
arbitrary source scripts as root. Lens Cap's generated icon stays in the local
icon store. Dependencies and user settings must be provisioned separately on a
new host; this consolidation is not a universal installer.

## Explicit deployment with incomplete runtime checks

When the user explicitly authorizes deployment before a complete runtime trial,
`deploy --apply --allow-partial-runtime --validated REPORT` accepts a report with
`static_passed: true`, `runtime_smoke_passed: true`, and the exact source digest.
It does not require or rewrite `runtime_validated: true`. The transaction journal
records the incomplete verification and explicit partial-runtime authorization.
The ordinary path still requires complete validation. Both paths retain all
source-digest, drift, backup, copy-verification, and rollback protections.

Use this only to carry out an explicit deployment instruction, after reviewing
the missing checks and the actual code differences. Record what was checked
before and after activation; never describe partial evidence as a complete
physical lock, audio, device, or exported-artifact trial.
