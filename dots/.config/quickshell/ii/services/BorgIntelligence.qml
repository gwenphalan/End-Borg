pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root
    readonly property var options: Config.options.borgIntelligence
    property bool busy: request.running || pendingOperation !== ""
    property string message: ""
    property var lastResult: null
    signal finished(string operation, bool succeeded, var result, string error)
    property string pendingOperation: ""
    property string pendingInput: ""

    function invoke(operation, payload) {
        if (busy || pendingOperation) return false;
        if (["complete", "classify_icon", "label", "label_apps", "refresh_launcher"].includes(operation) && !options.enabled) return false;
        if (operation === "classify_icon" && !options.iconAssistance) return false;
        pendingOperation = operation;
        message = operation === "refresh_launcher" ? "Updating launcher; text and vision run sequentially…" : "Working…";
        pendingInput = JSON.stringify(Object.assign({}, payload || {}, {
            endpoint: options.endpoint,
            text_model: options.textModel,
            vision_model: options.visionModel,
            timeout: options.timeoutSeconds,
            allow_public_icon: ["classify_icon", "refresh_launcher"].includes(operation) && options.iconAssistance
        }));
        request.command = ["python3", Quickshell.shellPath("scripts/borg_intelligence.py"), operation];
        request.stdinEnabled = true;
        request.running = true;
        return true;
    }
    function status() { return invoke("status", {}); }
    function models() { return invoke("models", {}); }
    function clearCache() { return invoke("clear_cache", {}); }
    function improveLauncher() { return invoke("refresh_launcher", {}); }
    function complete(prompt) { return invoke("complete", {prompt: prompt}); }
    function label(appName, desktopId) { return invoke("label", {app_name: appName, desktop_id: desktopId}); }
    function classifyIcon(iconName, appName, desktopId, iconPath) {
        return invoke("classify_icon", {icon_name: iconName, app_name: appName, desktop_id: desktopId, icon_path: iconPath || ""});
    }
    function storeKey(value) {
        if (!value || busy || pendingOperation) return false;
        const started = invoke("set_key", {key:value});
        return started;
    }
    IpcHandler {
        target: "borgIntelligence"
        function configure() {
            root.options.enabled = true;
            root.options.iconAssistance = true;
            root.status();
        }
        function testConnection() { root.models(); }
        function credentialStatus() { root.status(); }
    }
    Process {
        id: request
        stdout: StdioCollector {
            id: collector
            onStreamFinished: {
                try {
                    const response = JSON.parse(text);
                    root.lastResult = response.ok ? response.result : null;
                    root.message = response.ok && root.pendingOperation === "refresh_launcher"
                        ? "Updated " + response.result.labels + " labels and " + response.result.icons + " icons"
                          + ((response.result.failed_batches || response.result.vision_failures)
                             ? " (some model requests failed; cached results kept)" : "")
                        : response.ok ? "Request completed" : response.error?.message || "Request failed";
                    root.finished(root.pendingOperation, !!response.ok, root.lastResult, root.message);
                } catch (error) {
                    root.lastResult = null;
                    root.message = "Invalid client response";
                    root.finished(root.pendingOperation, false, null, root.message);
                }
                root.pendingOperation = "";
            }
        }
        onStarted: {
            write(root.pendingInput);
            root.pendingInput = "";
            stdinEnabled = false;
        }
        onExited: (code, status) => {
            Qt.callLater(() => {
                if (!root.pendingOperation) return;
                const operation = root.pendingOperation;
                root.pendingOperation = "";
                root.message = "Client exited without a response";
                root.finished(operation, false, null, root.message);
            });
        }
    }
}
