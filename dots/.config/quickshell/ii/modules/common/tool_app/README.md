# tool_app

Reusable canvas application chrome, declarative actions, project settings and file
workflows for this Quickshell desktop. It uses the existing shared widgets,
Settings groups, icons and Appearance tokens. Lens Cap is one consumer.

Import `qs.modules.common.tool_app` from a configuration rooted at `ii`.

## Choose an integration level

- **Compose QML directly:** `ToolApp` supplies toolbar, canvas, tool pill, utility
  pill, contextual pill and status slots. Use the individual components when an
  application needs a different composition.
- **Describe the shell in YAML:** `ToolDefinitionLoader` explicitly compiles an
  `app.yaml`; `ToolConfiguredApp` renders it and dispatches actions to registered
  QML callbacks or JSON-lines workers. See [DECLARATIVE.md](DECLARATIVE.md) for the
  version 1 contract and [examples/starter](examples/starter/README.md) for wiring.
- **Reuse workflow helpers:** document continuation, native file selection,
  file-type descriptors, named profiles and atomic writes work independently of
  either shell composition.

Importing the library does not start workers, register desktop file types or open
windows. The host decides when to instantiate its window and load a definition.
No definition supplies a canvas implementation or domain document format.

## Components

| Responsibility | Public components |
| --- | --- |
| Window and canvas shell | `ToolAppWindow`, `ToolApp`, `ToolCanvasArea`, `ToolTopBar`, `ToolOperationsBar`, `ToolHoverGroup`, `ToolBarButton`, `ToolPill`, `ToolStatusBar`, `ToolCanvasFooter` |
| Menus and feedback | `ToolMenu`, `ToolToast`, `ToolZoomControl`, `ToolShortcutHints`, `ToolCursorCoordinates`, `ToolPointCoordinates`, `ToolOperationFeedback` |
| Modal surfaces | `ToolModal`, `ToolConfirmDialog`, `ToolTextInputDialog`, `ToolSaveChangesDialog`, `ToolStartupDialog`, `ToolSettingsDialog` |
| Document/file workflow | `ToolDocumentController`, `ToolFileType`, `ToolFilePicker`, `ToolSaveButton`, `ToolActionLabel` |
| Declarative actions | `ToolDefinitionLoader`, `ToolConfiguredApp`, `ToolActionController`, `ToolActionButton`, `ToolActionStrip`, `ToolActionBar`, `ToolActionPill`, `ToolBackendProcess` |
| Project settings/profiles | `ToolSettingsStore`, `ToolSettingsForm`, `ToolProjectSettingsDialog`, `ToolProfilePicker` |

`ToolZoomControl` displays a numeric percentage and a reset button. Reset remains
visible and greyed out at the reset view; the host owns zoom math and supplies
`percent` and `atReset`. Handle `zoomEdited(percent)` and `resetRequested()`.
Disable canvas shortcuts while its `inputFocused` property is true.

`ToolShortcutHints.hints` accepts `[{keys: ["Shift", "LMB"], action: "Select curve"}]`
and renders compact inline hints using the existing shared `KeyboardKey` widget.
Mouse tokens use `ToolMouseHint` silhouettes with the corresponding button filled:
`LMB`, `RMB`, `MMB`, `Scroll`, `ScrollUp`, `ScrollDown`, and `Wheel`.

## Canvas footer, save feedback and startup

`ToolCanvasFooter` places contextual shortcut hints at the left. Its right-side
controls include selected-point `toolInputs`, cursor coordinates and `leadingControls`
(for the view toggle). The complete right-side order is selected/cursor
coordinates, reset, zoom and view mode at the far right. Inputs are `zoomPercent`,
`atReset`, `zoomEnabled`, `cursorActive`, `cursorX`, `cursorY`, `hints` and
`toolInputsEnabled`; it exposes `zoomFocused` and forwards `zoomEdited(percent)`
and `resetRequested()`. Put it in `ToolApp.status` or `ToolConfiguredApp.status`.

`ToolPointCoordinates` is a reusable tool input. Supply `position`,
`selectionCount`, optional `[width,height]` `bounds`, `decimals` and `fieldWidth`.
Handle `coordinateEdited(axis,value)` and `invalid(message)`; monitor
`inputFocused` when disabling canvas shortcuts. For multiple points, the host
supplies their centroid and applies an edit as a group translation. Display
rounding does not quantize the model merely because a field loses focus.

`ToolSaveButton.dirty` adds a measured `*` without shifting adjacent buttons.
For declarative actions, use `dirtyWhen` instead; action labels use the same
`ToolActionLabel` measurement. The marker is presentation, not persistence.

`ToolOperationFeedback.report(operation,message,failed)` emits `toastRequested`
unless the message is empty or a successful operation is in
`silentSuccessOperations` (default `save`, `save_as`). Errors always notify when
they have a message. Connect it to `ToolToast`; call document-controller success
methods separately after I/O acknowledgement. Routine saves need no success toast.
`ToolToast.show(text,isError,actionText)` optionally exposes one shared dialog-style
action button and emits `actionTriggered()`. Omitted action text clears a previous
action; the host owns its meaning and can gate it through `actionEnabled`.

`ToolStartupDialog` provides a centered horizontal icon/title header, recent
files and action slots directly below the list. `recentFiles` is a path list;
handle `recentFileRequested(path)`. Defaults `recentListHeight: 160` and
`recentHeaderInset: 8` keep the recent section compact; `actionsEnabled` gates
recent-file and supplied action buttons. It never starts a picker on its own.

`ToolZoomControl.resetBeforeInput` defaults false for existing standalone users;
the footer sets it true so reset precedes zoom. The view-mode slot follows both. `ToolCursorCoordinates.reservedWidth`
defaults 128; the footer uses zero to fit text without blank coordinate padding.
Tool bar/icon controls skip Tab traversal while keeping click focus. Numeric and
text inputs retain their editing focus.

## Pure selection and polyline helpers

Import `ToolPointSelection.js` and `ToolPolyline.js` by URL. Neither owns a canvas,
Qt input bindings, undo or domain data. Node selections are `[polylineIndex,
pointIndex]` pairs; coordinates stay in the host's image/model space.

- `normalizeNodes`, `wholePolylineNodes`, `toggleNode`, `selectNode` and
  `selectionResult` return normalized selections, primary node and change flags.
  `selectNode` options are `toggle`, `wholePolyline` and `preserveGroup`.
- `centroidNodes` computes group coordinates. `translateNodes` returns copied
  `polylines`, normalized `nodes`, `centroid`, actual bounded `delta` and
  `changed`. It clamps the group delta, preserving spacing. Finite bounds and
  translations are required; a group too large for the bounds is rejected.
- `canJoinSelectedEndpoints` and `joinSelectedEndpoints` require two endpoints
  from different open polylines. The latter returns `{ok,error}` on failure or
  copied `polylines`, normalized `selection`, `nodes`, `joinedIndex`,
  `joinPointIndex`, `sourceIndices`, `indexMap` and `deduplicated` on success.
  Endpoint tolerance defaults to `1e-9`; coincident join nodes are deduplicated.

The host interprets modifiers, creates undo entries, commits copied geometry and
updates other index-based state after joining.

## Document and file helpers

`ToolDocumentController` tracks `documentPath`, `dirty`, pending continuation and
`recentFiles`. Bind `available`, `hasDocument`, `busy` and `picking` to the app.
Connect `operationRequested(operation, path)` to actual I/O,
`pickerRequested(action)` to a picker and `discardConfirmationRequested()` to the
save-changes dialog. Handle `closeRequested()` through the host window.

Call `request(action, optionalPath)` for New/Open/Save/Save As and
`requestClose()` before closing. Defaults are `open` (new source), `load` (saved
document), `save` and `save_as`; properties allow other action names. Call
`saved(path)` or `opened(path)` only after successful I/O. Report failures with
`failed()` and picker cancellation with `pickerCancelled()`.

`saveAndContinue()`, `discardAndContinue()` and `cancelContinuation()` implement
the unsaved-change choices. Do not interpret a deliberately closed confirmation
modal as cancellation while Save or Discard is continuing.

`ToolFileType` describes `extension`, `legacyExtensions`, `label`, `mimeType` and
`icon`. Helpers are `accepts()`, `isLegacy()`, `suggestedName()` and `normalize()`.
Legacy conversion is an explicit host operation; this descriptor never renames a
file or silently converts a format.

`ToolFilePicker.open(descriptor)` starts an asynchronous GNOME Files chooser.
Connect `selected(path, paths)`, `cancelled()` and `failed(message)`. `commandFor()`
returns the configured command without opening the chooser. Descriptors provide
`appId`, `appName`, `mode`, `filters` (`[{name, patterns}]`), `folder`, optional
`name`, `multiple`, `purpose`, `historyNamespace`, `primaryExtension` and
`extensions`. Returned paths can be `file:` URLs; the shared Python `local_path`
normalizes them. Validate selected extensions in the host before loading.

## Python utilities

The companion package is `scripts/tool_app/`:

- `definition`: strict YAML validation and normalized JSON compilation.
- `protocol`: serial `{id, op, payload}` request/response dispatch.
- `profile_store`: named profiles with stable IDs, atomic writes and locking.
- `native_picker`, `history`: native picker transport and application-namespaced
  directory/recents metadata.
- `files`: local URL normalization, atomic JSON writes and no-overwrite renames.
- `registration`: configurable desktop/MIME/icon registration. Rendering is
  read-only; CLI writes require `--apply`, with separate refresh/default flags.

Profiles are persistent user presets in `$XDG_DATA_HOME/<namespace>/profiles`.
Generated images and other working assets belong in host-owned temporary storage,
not the profile store. The host decides what its saved document retains.

See [AGENTS.md](AGENTS.md) before editing shared APIs or verification flows.

## Migration and compatibility

The direct-composition `ToolApp` and individual component APIs remain available;
an existing tool does not need YAML or a backend-protocol rewrite to share chrome.
Adopt the footer, dirty Save label, feedback and geometry helpers independently.
`ToolConfiguredApp` adds declarative action routing and definition defaults;
callers provide declared state, committed settings, callbacks and domain content.
Do not replace an existing application-specific save format or worker protocol
merely to use the shared presentation components.

## Compact chrome and operation slots

The top bar is a full-width pill: 32 px surface plus 8 px top/bottom layout
margins matching the side margins, with 28 px labeled buttons, 18 px icons and
shared smaller text. `ToolBarButton.labelPixelSize` also controls Save label
measurement so its reserved dirty marker width matches the rendered text. Its default child list is
`buttons`; use `ToolApp.toolbar` for the normal composition. Configured action
bars retain their shared moving selection/hover indicator. Direct top/operation
bars and floating `ToolPill` groups use `ToolHoverGroup` with the same shared `SelectionIndicator`; separators
preserve the last hover target, disabled buttons clear it and compound inputs
keep their own input treatment. Local button hover fills are suppressed inside
these groups to avoid double backgrounds.

`ToolApp.operationsLeft` and `operationsRight` supply the first row of a separate
`ToolOperationsBar` between the top bar and canvas. `operationsSecondLeft` and
`operationsSecondRight` supply the second row. The bar reserves 88 px whenever
any slot is populated: two 40 px rows plus an 8 px gap. `rowHeight`/`rowSpacing`
on the standalone bar are configurable. `operationsEnabled` defaults to
`controlsEnabled`. Fully empty bars collapse; controls do not overlay the canvas.
`ToolConfiguredApp` offers the same four slots. Existing floating tool,
utility and context pills retain their defaults; opting into operation slots does
not silently move existing actions.

For a grouped ribbon or another layout spanning both rows, supply
`operationsContent: GridLayout { Layout.fillWidth: true; implicitHeight: 96; … }`
on either shell (`customContent` on a standalone `ToolOperationsBar`). The custom
slot replaces the legacy two-row presentation while populated; removing it restores
those rows. Its layout's implicit height determines the operation bar height.
Use an explicit `implicitHeight` or let the child layout calculate one; do not
anchor its height back to the bar. The host owns section labels and controls,
while shared spacing placement, enabled state and moving hover remain in the bar.
The slot is QML composition only and does not change the YAML definition schema.

`ToolCanvasFooter.leadingControls` retains its compatible name but now renders
after reset/zoom, at the far right (for view mode).
Its existing default `toolInputs` slot stays in the right-hand group, ahead of
cursor coordinates and reset/zoom. Hints occupy the remaining flexible
width at the left without wrapping.
`ToolShortcutHints.horizontalAlignment` also accepts `Qt.AlignLeft` (standalone
default) or `Qt.AlignHCenter`; overflow clips within its allocated width.
Applications can put their view toggle in that slot without reimplementing
the shared footer or changing coordinate editing behavior.

`ToolIconButton` is the compact operation control (28 px target, 18 px icon), with
disabled opacity. Floating editing tools retain their larger icon button targets.

`ToolCanvasFooter.prefixControls` places host controls before contextual shortcut hints.
`ToolModePicker` reuses the Settings dropdown with compact sizing; choices can
include `icon` (Material Symbol) and `separatorBefore`. Hosts own mode names and
transitions. The underlying Settings dropdown keeps iconless choices compatible.
