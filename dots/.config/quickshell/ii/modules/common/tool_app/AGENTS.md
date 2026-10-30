# Shared tool_app library

This is the reusable Quickshell tool application shell. Read `README.md` before
changing its API. Lens Cap is its first consumer, not its owner.

## Boundaries

- Keep window chrome, toolbars, floating pills, canvas framing, dialogs and
  document workflows here, with one public QML component per file.
- Import as `qs.modules.common.tool_app`. Reuse `qs.modules.common.widgets`,
  `Appearance`, and the existing Settings components. Do not invent a parallel
  theme, grouped-row implementation, icon system or button style.
- Application content is supplied through component properties, slots and
  signals. No calibration, OpenCV, LabelMe, camera assumptions or Lens Cap paths
  belong in generic components.
- `ToolDocumentController` owns dirty-state and Save/Open continuation only.
  An application owns its data, worker protocol, load/save implementation, undo
  history, view transforms and migrations. Report successful save/open back to
  the controller; selecting a filename alone is not a successful save.
- `ToolFileType` describes extensions and normalization. Legacy conversion
  remains an explicit application operation with confirmation and no overwrite.
- Python utilities live in `scripts/tool_app/`; do not duplicate them in each
  application. Namespace history per application. Generated working assets are
  temporary; history is metadata, not an asset cache.

## Interaction invariants

- Keep tools separate from operations: tool pill above left, utility pill below
  left, contextual action pill above right. Supply actions through `ToolApp`
  slots; do not duplicate their placement in application code. Contextual action
  buttons are icon-only with accessible names and tooltips. Keep labels for actual
  controls/inputs and the main labeled top-bar operations.
- Opening a document and explicit Fit may frame the canvas. Saving, editing,
  toggling a view, resizing or opening a modal must not reset zoom/pan.
- Reuse shared modal surfaces, scrims, transitions and filled action buttons.
  Settings bodies use the actual `SettingsGroup`/`SettingRow` components with an
  application-local value store. Never write tool preferences to desktop Config.
- Save updates the current path. Save As always asks. Cancel or failure must
  preserve the document and clear pending destructive continuations.
- Preserve the exact pending path through Save-before-Open and the close
  confirmation sequence. Do not clear continuation merely because a dialog
  closes deliberately for Save or Discard.
- A picker must open only after an explicit operation; picker cancellation
  returns control to the application. Keep native picker processes asynchronous.

## Verification

From the Quickshell `ii` root:

```sh
qs -p toolAppTest.qml --no-color
QS_LENS_TEST_FIXTURE=/tmp/lens-real-verification QS_LENS_TEST_ORDER=2 \
XDG_STATE_HOME=/tmp/tool-app-verification-state \
qs -p lensCalibrationTest.qml --no-color
~/.local/share/lens-calibration/venv/bin/python -m pytest -q scripts/tool_app scripts/lens_calibration
```

QtTest results are printed as `TOOL APP TOTAL` and `LENS TOTAL`. Inspect the
failure count; the Quickshell exit code alone does not establish test success.
Use isolated history state for tests, and never overwrite user originals. GUI
tests need the active user's Wayland/DBus environment. Do not send global input
while the user is using the desktop. Use QtTest against its own test window.

When changing a shared component, check Lens Cap and default desktop Settings
behavior, not only a detached demonstration. Inspect a rendered settings modal
for row grouping, icons, clipping and action-button styling. Do not claim visual
verification from process liveness or a parser-only check.

## Declarative framework

- Read `DECLARATIVE.md` for the version 1 input and worker contracts before
  extending `definition.py` or the declarative QML components. Keep strict compiler
  validation and runtime consumption aligned; update docs and headless tests with
  schema changes. Do not introduce executable expressions in definitions.
- `ToolConfiguredApp` composes chrome and routes actions; it does not implement
  an application's canvas, undo stack, domain persistence, profile semantics or
  project migrations. Preserve the direct-composition `ToolApp` API.
- Custom settings editors receive `settingsStore`, `actionController` and
  `editorContext`. Keep injected data reactive when the host replaces it.
- Settings Apply is a request, not a successful commit. Complete its modal only
  after validation/persistence acknowledges success. Likewise Save/Rename Profile
  keeps its naming modal open until the matching operation completes.
- Declare worker operations in `protocol.serve`; stdout is JSON lines only.
  Keep one outstanding request per transport and correlate acknowledgements by ID.
  Never claim a successfully dispatched action means its backend work succeeded.
- The starter is intentionally a domain scaffold. Keep its placeholders explicit
  and its headless compilation valid. Run it through an `ii`-root shim so shared
  `qs` imports and `Quickshell.shellPath` preserve the actual config root.
- Do not launch sample windows, reload the desktop or mutate a live Lens Cap
  project just to test the library. Prefer schema/compiler, protocol and temporary
  profile-store tests. Interactive verification requires an explicit suitable
  user context; never send global keyboard input.
- Reset view remains visible and disabled/grey when already reset. Preserve this
  invariant in shared zoom controls and examples.

- Keep `scripts/tool_app/definition.schema.json` aligned with compiler contracts.
  Editor `$schema` belongs in a YAML-language-server comment, never an input key.
  Preserve `settings.<declaredPath>` condition forward references, reject unknown
  paths and keep host state out of that reserved namespace. Form conditions use
  the draft; action chrome uses committed settings.

- Version 1 numeric fields without choices require explicit min/max; never rely
  on shared Settings numeric-control fallback bounds. Numeric choice fields may
  omit bounds. Keep editor schema, compiler and docs consistent with this rule.

- Prefer `ToolCanvasFooter`, `ToolPointCoordinates`, `ToolSaveButton`/`dirtyWhen`
  and `ToolOperationFeedback` when extracting canvas-editor behavior. Keep precise
  model coordinates unchanged on focus-only edits; group moves preserve spacing.
  Routine successful Save/Save As is silent, while actual errors surface.
- Selection/polyline JavaScript helpers are pure and return copies. Hosts own
  undo entries, modifier semantics and index-dependent state after joining.
  Keep direct `ToolApp` composition compatible when adding configured defaults.

- Compact top chrome uses `ToolTopBar` and a separate `ToolOperationsBar`, never
  application-local copies. Expose operations through `operationsLeft` and
  `operationsRight`, keeping floating tool pills intact. Preserve both direct
  and configured composition APIs; empty optional bars collapse.
- Footer view toggles belong in the compatible `leadingControls` slot after reset/zoom; `toolInputs`
  remains the existing right-side slot. Do not move domain actions by default.

- Header vertical margins match its 8 px sides; compact button labels use the
  shared smaller font, including dirty Save label measurement. Operation chrome
  reserves two rows (40+8+40 by default); second-row slots must remain optional
  and available on both direct and configured shells. Footer contextual hints align left
  inside flexible width. The right group is selected coordinates, cursor
  coordinates, reset, zoom and view toggle; view mode remains rightmost.

- Toolbar/icon controls must not participate in native Tab traversal. Keep click
  focus and preserve numeric/text input editing focus. The host owns any explicit
  canvas Tab behavior; shared controls must not steal it.
