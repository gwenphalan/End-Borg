pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root
    readonly property bool settingsPreview: Quickshell.env("QS_SETTINGS_PREVIEW") === "1"
    readonly property string python: FileUtils.trimFileProtocol(Directories.home) + "/.local/state/quickshell/.venv/bin/python"
    readonly property bool busy: request.running || pendingOperation !== "" || rebuildTimer.running
    property string message: ""
    property string pendingOperation: ""
    property string pendingInput: ""
    property string refreshSummary: ""
    property bool outputFinished: false
    property bool processExited: false
    property string responseText: ""
    property int requestGeneration: 0
    property bool processStarted: false
    signal finished(string operation, bool succeeded, var result)

    function invoke(operation, payload) {
        if (settingsPreview && operation !== "status") return false;
        if (busy) return false;
        if (operation !== "rebuild") refreshSummary = "";
        outputFinished = false;
        processExited = false;
        processStarted = false;
        requestGeneration++;
        responseText = "";
        pendingOperation = operation;
        pendingInput = JSON.stringify(payload || {});
        message = operation === "refresh" ? "Fetching game icons…"
            : operation === "rebuild" ? "Rebuilding application icons…" : "Working…";
        request.command = [python, Directories.scriptPath + "/steamgriddb_icons.py", operation];
        request.stdinEnabled = true;
        request.running = true;
        return true;
    }
    function status() { return invoke("status", {}); }
    function storeKey(key) { return invoke("set_key", {key:key}); }
    function testConnection() { return invoke("test", {}); }
    function refresh() { return invoke("refresh", {force:true}); }
    function queueRebuild() { if (!settingsPreview) rebuildTimer.restart(); }
    function completeRequest() {
        // Do not release the busy guard until both streams and process settle.
        if (!outputFinished || !processExited || request.running || !pendingOperation) return;
        const generation = requestGeneration;
        Qt.callLater(() => {
            if (generation !== root.requestGeneration || request.running || !root.pendingOperation) return;
            root.finishRequest();
        });
    }
    function finishRequest() {
        const operation = pendingOperation;
        pendingOperation = "";
        try {
            const response = JSON.parse(responseText);
            message = response.ok
                ? operation === "test" ? "Connected to SteamGridDB"
                : operation === "set_key" ? "API key saved in the desktop keyring"
                : operation === "rebuild" ? (refreshSummary ? refreshSummary + " Application icons rebuilt." : "Application icons rebuilt")
                : operation === "refresh" ? "Updated " + response.result.updated + " icons; "
                    + response.result.missing + " unavailable, " + response.result.failed + " failed, "
                    + response.result.deferred + " deferred. Existing artwork kept as fallback."
                : "Keyring status checked"
                : response.error?.message || "SteamGridDB request failed";
            if (operation === "refresh" && (response.ok || response.partial?.updated > 0)) {
                refreshSummary = message;
                queueRebuild();
            }
            finished(operation, !!response.ok, response.ok ? response.result : response.partial || null);
        } catch (error) {
            message = "SteamGridDB client exited without a valid response";
            finished(operation, false, null);
        }
        responseText = "";
    }

    Timer {
        id: rebuildTimer
        interval: 300
        onTriggered: {
            if (!Config.ready || Config.lastError) {
                root.message = "Save valid settings before rebuilding icons";
                return;
            }
            if (Config.saving || request.running || root.pendingOperation) {
                restart();
                return;
            }
            root.invoke("rebuild", {enabled:Config.options.appearance.steamGridDb.enabled});
        }
    }
    Process {
        id: request
        stdout: StdioCollector {
            onStreamFinished: {
                root.responseText = text;
                root.outputFinished = true;
                root.completeRequest();
            }
        }
        onStarted: {
            root.processStarted = true;
            write(root.pendingInput);
            root.pendingInput = "";
            stdinEnabled = false;
        }
        onRunningChanged: {
            if (running || !root.pendingOperation) return;
            if (root.processStarted) {
                root.completeRequest();
                return;
            }
            const generation = root.requestGeneration;
            Qt.callLater(() => {
                if (generation !== root.requestGeneration || request.running || root.processStarted || !root.pendingOperation) return;
                root.pendingInput = "";
                root.responseText = "";
                root.outputFinished = true;
                root.processExited = true;
                root.completeRequest();
            });
        }
        onExited: (code, status) => {
            root.pendingInput = "";
            root.processExited = true;
            root.completeRequest();
        }
    }
}
