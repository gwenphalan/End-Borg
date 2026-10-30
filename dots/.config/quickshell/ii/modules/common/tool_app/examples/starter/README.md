# Starter scaffold

This example connects a compiled YAML definition, shared chrome, grouped settings,
a custom profile editor and a Python worker. It is scaffolding for an application,
not a finished document editor. Open, Save, canvas rendering, viewport transforms
and undo are deliberate domain hooks. The shared footer, dirty Save marker and
operation feedback are wired without assuming a domain viewport. The Process action demonstrates protocol
routing; settings acknowledgement returns the submitted values without persisting
a project document. Named profiles use the real persistent profile store.

## Integrate without changing the Quickshell root

Keep the executed entry in the `ii` configuration root so `qs.modules.*` imports
and `Quickshell.shellPath("scripts/...")` resolve correctly. For a new tool, copy
this starter directory to an application-specific directory beneath `ii`, give it
its own app ID and profile namespace, and add a small root entry such as
`ii/myTool.qml`:

```qml
//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import "modules/common/tool_app/examples/starter" as StarterExample

StarterExample.Starter {}
```

Adjust the import to your copied directory. `Starter.qml` resolves its `app.yaml`
relative to itself. YAML resolves `backend.py` and `qml/ProfileEditor.qml` relative
to that definition. Do not invoke the nested directory as a separate Quickshell
config: this tree relies on the established `ii` root.

After implementing the domain hooks, explicitly launch the root entry with
`qs -n -p /absolute/path/to/ii/myTool.qml`. Nothing should add the example to
`shell.qml` or open it when the desktop reloads. Do not launch this example merely
to inspect the library while someone is using the desktop.

The YAML header points editors to `scripts/tool_app/definition.schema.json` for
completion. Keep that comment relative to the definition when copying it; `$schema`
is not a supported top-level declaration key. Conditions can reference declared
settings with `settings.<path>`; settings rows evaluate these against the draft,
while toolbar actions use committed values.

## Replace the hooks

1. Set `app.id`, `app.name` and `app.icon` in `app.yaml`; choose an independent
   `ProfileStore` namespace in `backend.py`.
2. Implement document Open/Save using `ToolDocumentController`, `ToolFilePicker`
   and your worker. On successful loading set `hasDocument` and other domain state.
   Do not mark a document loaded merely because a picker returned a filename.
3. Supply the canvas through `canvasContent`; bind undo/redo availability and
   handlers to your domain history. Connect zoom to your viewport transform.
4. Replace `settings.apply` with actual validation/persistence. The QML host keeps
   settings open until its backend acknowledgement and reports failures with
   `settingsDialog.complete(false, message)`.
5. Define your worker operations explicitly in `protocol.serve`. Keep stdout for
   `{id, ok, result|error}` messages and send diagnostics to stderr.

The profile custom editor receives `settingsStore`, `actionController` and
`editorContext`. Its Save/Rename handlers pass the picker instance back to the
host; the host completes the naming modal only when the matching operation
acknowledges success. Profile selection populates the settings draft. It does not
save or apply a project by itself. The example's `settings.apply` echo is also not
a persistence guarantee.

## Headless inspection

From the `ii` root, compile and inspect without opening a window:

```sh
python scripts/tool_app/definition.py \
  modules/common/tool_app/examples/starter/app.yaml --output /tmp/tool-starter.json
python -m py_compile modules/common/tool_app/examples/starter/backend.py
```

A protocol smoke test can send a `process` request to `backend.py` through stdin.
Use isolated `XDG_DATA_HOME` if testing profile writes. See the library
[declarative contract](../../DECLARATIVE.md) for supported schema fields, runtime
callbacks, acknowledgements and persistence boundaries.
