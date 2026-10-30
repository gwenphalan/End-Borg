# Validation

Run from the repository root:

```sh
python tools/validate.py
python tools/validate.py --tests
python tools/validate.py --tests \
  --lens-python "$HOME/.local/share/lens-calibration/venv/bin/python"
```

The first command checks source only. `--tests` opts into the reviewed offline
allowlist, and `--lens-python` adds the Lens Cap Python suite using its existing
dependency environment. Missing tools or dependencies fail the requested check;
the runner does not install packages. Python, Bash, `luac`, Qt 6 `qmlformat`, and
Node.js are needed for the full basic run. Python tests additionally need pytest,
PyYAML, Pillow, NumPy, and the icon renderer dependencies. Lens Cap uses its own
requirements file and environment.

The runner checks Python compilation in memory, JSON decoding, `.sh` files with
`bash -n`, Lua with `luac -p`, internal relative symlink targets, and QML parsing
with `qmlformat -n`. It discards formatter output and never uses `--inplace`.
Qt 6 binaries are preferred over the Qt 5 binaries that may occupy `/usr/bin`;
`--qmlformat /path/to/qt6/qmlformat` overrides detection.

Two upstream file formats need explicit handling:

- `hyprland/scripts/fuzzel-emoji.sh` has an emoji database after its unconditional
  `exit` and `### DATA ###` delimiter. Only its executable header is shell syntax.
- `models/LauncherSearchResult.qml` is accepted by Qt 6 `qmllint` but cannot be
  round-tripped by Qt 6.12 `qmlformat`. Only this exact file can fall back to the
  adjacent `qmllint --ignore-settings`, and that fallback is reported separately.

Absolute and out-of-repository symlinks are counted as unchecked. `.git`, virtual
environments, Python caches, `node_modules`, `local`, and backup directories are
excluded. Python's nonfatal syntax warnings do not count as compilation errors.
This is source validation, not a dependency resolver or a complete shell linter.

## Offline test coverage

The explicit allowlist exercises Bed Lock payload validation, launcher helpers
and source contracts, icon rendering and publication in temporary directories,
wallpaper palette selection, tool definition compilation, worker protocol,
profile stores, generic file/history/registration helpers, sleep schedule
conversion, and pure JavaScript drawing/selection helpers. The Lens Cap addition
covers image geometry, calibration diagnostics, temporary project save/reopen,
annotation conversion, spatial calculations, and mocked Blender integration.

Tests receive temporary HOME, XDG configuration/cache/data/state/runtime,
TMPDIR, and preview directories. They inherit no display variables, active
compositor signature, session bus address, user Python paths, credential
variables, or proxy variables. The session bus points at a nonexistent socket.
This environment separation is not an operating-system network sandbox; only
reviewed offline tests are in the allowlist. Imported helpers may read installed
system resources such as icon themes.

The runner deliberately excludes desktop `shell.qml`/`settings.qml` startup,
Quickshell UI and transport process tests, real Blender process/render tests,
and external Home Assistant/Music Assistant/Borg service calls. Optional LabelMe
parser checks inside the Lens Cap tests are not exercised when the parser is
absent from the isolated HOME. Running an offscreen shell without isolation is
unsafe: startup code can clean shared cache directories or run commands.

A passing run does not establish visual fidelity, actual launcher input behavior,
compositor rule acceptance, lock security, physical audio/light behavior, service
connectivity, or successful desktop deployment. Those require a separate isolated
runtime session and explicit behavioral checks. Do not mark a deployment report
`runtime_validated: true` from this runner's result.

## Recorded staging result

The consolidation run on 2026-10-30 uses Qt 6.12, the system Python interpreter,
and the existing Lens Cap dependency environment. Exact final counts and suite
results are recorded below after the final run. Source and test counts may change
as the repository evolves; rerun the command before deployment.

```text
CHECKED json: 24
CHECKED lua: 20
CHECKED python: 108
CHECKED qml_parse: 741
CHECKED qml_qmllint_fallback: 1
CHECKED relative_symlink: 4
CHECKED shell: 70
PASS test: scripts/test_bedlock_lan_status.py (11 tests)
PASS test: scripts/tests/test_launcher_helpers.py (11 tests)
PASS test: scripts/tool_app (definitions, protocol, files, history, registration) (75 passed)
PASS test: scripts/tests (offline icon suites) (142 passed)
PASS test: scripts/colors/test_scheme_for_image.py (6 tests)
PASS test: scripts/lens_calibration (offline Python suites) (164 passed)
PASS test: scripts/settings/test_sleep_schedule.mjs
PASS test: scripts/lens_calibration/test_context_hints.mjs
PASS test: scripts/lens_calibration/test_curve_diagnostics.mjs
PASS test: scripts/lens_calibration/test_curve_geometry.mjs
PASS test: scripts/lens_calibration/test_region_geometry.mjs
PASS test: scripts/lens_calibration/test_selection_headless.mjs
PASS test: scripts/tool_app/tests/test_runtime.mjs
RESULT: 0 failure(s); desktop and QML runtime not exercised
```

This run passed 409 Python tests and seven JavaScript harnesses. The counts
include 740 QML files parsed with `qmlformat` and one accepted by the documented
`qmllint` fallback. No required dependency was missing from these requested
suites. Real Blender subprocess/render tests, Quickshell UI/process transport
tests, and the optional external LabelMe parser were outside this run.

One existing launcher assertion was stale: it expected the scrollbar to depend
only on active/scrolling state. It now checks the existing interaction state and
linger timer, preserving the current delayed-hide behavior without changing the
runtime component.

## Deployment verification — 2026-10-30

The final source run again passed all 409 Python tests and static checks above.
The allowlist now also includes `tests/test_sleep_integration.mjs`, bringing the
JavaScript harness count to eight. Its ten cases exercise wake-day/bedtime-day
roundtrips, week boundaries, invalid intervals, disabled days, and disabled-plan
acknowledgements. Run it directly with `node tests/test_sleep_integration.mjs`.
The migration suite now has 14 passing tests, including an explicitly authorized
partial-runtime deployment path that retains digest/drift checks and records
incomplete runtime verification truthfully.

In a private bwrap filesystem/network/session-bus sandbox, KWin's virtual output
allowed `toolAppTest.qml` to report `TOOL APP TOTAL {passed:7,failed:0}`. Eight
additional headless QML/controller and real Process transport pytest tests passed.
The longer Lens Cap harnesses and full shell reached `Configuration Loaded`, but
the private KWin compositor then crashed; no Lens TOTAL or stable isolated shell
result is claimed. Expected missing isolated-service warnings are separate from
actual application failures. No test compositor or test window was attached to
the host desktop.

Live verification followed explicit deployment authorization. The main shell and
open Settings processes hot-reloaded successfully. Hyprland's installed binary
accepted the staged configuration with `--verify-config` in isolation, and the
live compositor reported no config errors after reload. Actual notification
creation and immediate dismissal passed after the stale-timer guard repair.
The final reload log contained no TypeError, ReferenceError, or undefined-binding
assignment diagnostics; an absent optional generated translation file and toolkit
focus diagnostics remain separate, nonfatal messages.

Read-only host checks confirmed Home Assistant REST/websocket availability,
fresh Bed Lock data, Music Assistant service discovery, Borg model discovery,
launcher IPC responsiveness, unchanged monitor geometry/modes, unchanged volume,
and byte-identical user preferences/generated lock files. Runtime state changed
only through cache refreshes and Settings navigation. Physical authentication,
alarm/light/audio actions, reboot behavior, and full Lens Cap UI/export behavior
were not exercised. See [DEPLOYED.md](DEPLOYED.md) for rollback and scope.
