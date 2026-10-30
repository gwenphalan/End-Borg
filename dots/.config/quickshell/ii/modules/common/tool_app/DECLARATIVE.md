# Declarative application contract, version 1

Definitions contain configuration and identifiers, never executable expressions.
The compiler rejects unknown keys, invalid references, duplicate YAML keys and
unsupported versions. Use the system Python with PyYAML installed:

```sh
python scripts/tool_app/definition.py path/to/app.yaml --output /tmp/app.json
```

Editor completion is available from `scripts/tool_app/definition.schema.json`.
Reference it in a YAML comment, not a top-level `$schema` key (which is rejected):

```yaml
# yaml-language-server: $schema=../../../../../scripts/tool_app/definition.schema.json
```

That relative path fits the bundled starter; adjust it for a copied definition.
The compiler additionally validates cross-references, file existence, placements
and defaults; editor schema validation does not replace compilation.

Paths to Python scripts and custom QML components resolve relative to `app.yaml`,
not the working directory. Compilation checks that these files exist, but does
not import QML, execute Python, launch a worker or register file types. YAML has a
1 MiB limit. Only finite JSON-compatible data is accepted.

## Top-level schema

Required fields are `version: 1` and `app: {id, name, icon}`. App ID and other
identifiers start with a letter and contain letters, digits, dots, underscores or
hyphens. `icon` is a shared Material Symbols name.

Optional sections:

| Key | Input shape and defaults |
| --- | --- |
| `state` | Mapping of declared state names to JSON values; `canUndo` and `canRedo` default false. |
| `backends` | Mapping of IDs to `{program, script, args?}`. Script must be an existing `.py`; args is a string list. |
| `components` | Mapping of IDs to existing `.qml` files. Compiled values are absolute file URLs. |
| `actions` | Mapping of IDs to action declarations below. |
| `toolbar` | List of action-ID lists and the literal `stretch`; groups are separated visually. |
| `tools` | Action-ID list for the primary tool pill. |
| `utilities` | `{includeHistory: true, actions: [], placement: topRight}`; placement can also be `bottomLeft`. |
| `contextActions` | `{actions: [], placement: belowTools, visibleWhen: true}`; placement can also be `topRight`. |
| `settings` | `{title: Project settings, groups: []}`, described below. |

Action IDs must exist and cannot repeat within one list. Context and utility
pills cannot both occupy `topRight` with nonempty actions. Undo/Redo are inserted
first into utilities unless `includeHistory: false`. Their built-in callbacks are
`undo`/`redo`, enabled by `canUndo`/`canRedo`, with `Ctrl+Z`/`Ctrl+Shift+Z`.
They may be overridden by complete action declarations. Other duplicate shortcut
strings are rejected.

The compiler normalizes this input: toolbar entries become `{actions: [...]}` or
`{stretch: true}`, backend entries become `{command: [...]}`, built-ins are
expanded, conditions receive defaults and settings defaults become a flat map.
Pass this compiled result to QML, not the raw parsed YAML.

## Actions and conditions

```yaml
actions:
  process:
    label: Process
    icon: play_arrow
    tooltip: Process the current document
    shortcut: Ctrl+Return
    enabledWhen: {all: [hasDocument, {not: busy}]}
    visibleWhen: true
    checkedWhen: false
    dirtyWhen: false
    arguments: {quality: balanced}
    target: {kind: backend, backend: worker, operation: process}
  settings:
    label: Settings
    icon: tune
    target: {kind: qml, handler: openSettings}
```

`label`, `icon` and `target` are required. `tooltip` and `shortcut` are optional.
`arguments` defaults to `{}`. `dirtyWhen` defaults false and accepts the same
conditions as enabled/visible/checked state. Use `dirtyWhen: dirty` on Save after
declaring a `dirty` state; the measured marker does not move adjacent labels.
`ToolActionController.dirtyFor(id)` exposes this presentation state. QML targets require a `handler`; backend targets
require a declared `backend` and an `operation`. Targets accept only their own
keys. Runtime QML handlers are registered in `ToolConfiguredApp.handlers`.
Arguments are a shallow merge of declaration values and invocation overrides.
A callback returning false cancels dispatch; exceptions emit `actionFailed`.

Conditions are booleans, declared state names, or one operator:

- `{all: [condition, ...]}` or `{any: [condition, ...]}`; lists cannot be empty.
- `{not: condition}`.
- `{eq: [stateName, literalJsonValue]}`.

State references must be declared, including strings used in `eq`. Settings fields
are also addressable as `settings.<declaredFieldPath>`, including forward
references to fields declared later. For example, `enabledWhen:
settings.processing.enabled` or `{eq: [settings.processing.quality, precise]}`.
Unknown setting paths are rejected. Host `state` keys may not use the reserved
`settings.` prefix. A string used
as the second `eq` item is a literal, not another state lookup. No JavaScript or
Python expressions are evaluated. The host supplies current state; declared
values are defaults. `ToolActionController.settingsValues` supplies committed
settings as the `settings.*` condition namespace (wired by `ToolConfiguredApp`).
Inside the settings form, conditions use the current draft, so dependent controls
react before Apply without changing live toolbar/tool state. Visibility controls
presentation and dispatch eligibility.

The action controller does not change state, implement undo or infer a busy flag.
Bind busy to the relevant worker and domain operation state. Disable shortcuts
when text inputs or modals own the keyboard. `ToolConfiguredApp.shortcutsEnabled`
is provided for this purpose.

## Settings

Groups require unique `id`, `title`, `icon` and `items`, with optional
`visibleWhen`. Headers use the shared `ContentSection` title and heavier icon
style, with the desktop's actual grouped Settings rows beneath each header.
Items have one of three kinds:

```yaml
settings:
  title: Project settings
  groups:
    - id: processing
      title: Processing
      icon: tune
      items:
        - kind: field
          path: processing.amount
          label: Amount
          icon: straighten
          type: real
          default: 1.0
          min: 0
          max: 10
          step: 0.1
          unit: px
        - kind: action
          action: process
        - kind: component
          component: profileEditor
```

All items support `visibleWhen` and `enabledWhen`. Fields require unique `path`,
`label`, `type` and `default`. Supported types are `bool`, `int`, `real`, `string`
and `label`. Label fields are read-only; explicitly setting `readOnly: false`
on a label is rejected. Numeric (`int`/`real`) fields without `choices` require
explicit `min` and `max`; this keeps validation aligned with the shared numeric
control. Numeric choice fields may omit bounds. Other field keys are `icon`, `min`, `max`, `step`, `unit`,
`readOnly`, and `choices: [{name, value}, ...]`. Defaults must match the field
type, numeric bounds and any choice list. Choice values must match the field
type and bounds. Each item kind accepts only its own keys. Bounds must be finite, min cannot exceed
max and step must be positive. Use type-compatible choice values.

Setting paths are flat keys: `{ "processing.amount": 1.0 }`, not nested objects.
They are independent of desktop `Config`. `ToolSettingsStore.begin(values)` merges
field defaults and values into committed and draft snapshots. Valid edits update
the draft; invalid edits report errors. Apply emits a copy of the draft without
committing it. The host must validate/persist its domain settings, then call
`app.settingsDialog.complete(true, "")`, or `complete(false, message)` to keep the
modal open with an error. Cancel discards draft edits.

A custom settings component is loaded from its declared URL. If it declares these
properties, the form injects them after loading:

```qml
property var settingsStore: null
property var actionController: null
property var editorContext: ({})
```

Use `settingsStore.get(path)`, `write(path, value)` and `invalid(path, message)` for
schema fields. Custom state not represented by declared fields needs explicit host
handling. `editorContext` supplies application callbacks/data, such as profile
operations; the framework does not discover methods or import arbitrary code from
a YAML request.

## Worker protocol

`ToolBackendProcess` starts lazily on the first request and keeps one worker alive.
It supports one outstanding request at a time. Diagnostics belong on stderr.
Newline-delimited stdout messages are JSON only:

```json
{"id":1,"op":"process","payload":{"quality":"balanced"}}
{"id":1,"ok":true,"result":{"processed":1}}
```

Failure: `{"id":1,"ok":false,"error":"Readable reason"}`. Request IDs are positive
JavaScript-safe integers (at most `2^53 - 1`); the response must carry the matching ID. `result` is finite JSON data.
Unknown operations and non-object payloads fail through `protocol.serve`. Callback
prints are redirected to stderr so they cannot corrupt protocol stdout.
Unmatched messages become `eventReceived` events in the QML transport.

```python
from tool_app.protocol import serve
serve({"process": lambda payload: {"processed": 1}})
```

`ToolConfiguredApp.backend(id)` exposes the transport for explicit requests;
`backendCompleted(backend, operation, result)` and
`backendFailed(backend, operation, message)` route acknowledgements to the host.
Requests do not supply executable names: worker command vectors come only from the
compiled definition. There is no shell interpolation or dynamic operation import.

## Named profiles

`ToolProfilePicker` provides selection, Save Profile, Rename, Update and Delete.
QML receives opaque `{id, name}` records and emits requests; it has no filesystem
policy. The host wires `selectionRequested`, `saveRequested`, `renameRequested`,
`updateRequested` and `deleteRequested` to its own callbacks/worker operations.
For Save/Rename, call the picker instance's `complete(success, message)` only after
that operation finishes; success closes the naming modal, failure keeps it open.

`ProfileStore(namespace)` stores versioned JSON profiles under
`$XDG_DATA_HOME/<namespace>/profiles` (default `~/.local/share`). Payloads are
application-owned finite JSON. IDs are UUID hex strings and survive renaming.
Names are trimmed, 1–120 characters and unique ignoring case. Invalid profile
files are omitted from listing. Writes are atomic and mutations use a lock.
Selecting a profile does not silently apply it to a live document: the host chooses
whether to populate a settings draft or perform an explicit domain operation.

No image caches, generated assets, document association or file type registration
are implied by this contract. Those use the separate reusable helpers and host
policy described in [README.md](README.md).
