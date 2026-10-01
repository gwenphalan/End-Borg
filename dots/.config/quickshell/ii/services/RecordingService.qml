pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property bool isRecording: false
    property bool isPaused: false
    property bool justSaved: false
    property int elapsedSeconds: 0

    onIsRecordingChanged: {
        if (root.isRecording) {
            GlobalStates.recordSelecting = false;
        }
    }

    Timer {
        id: justSavedResetTimer
        interval: 1200
        onTriggered: root.justSaved = false
    }

    readonly property string formattedTime: {
        const hrs = Math.floor(elapsedSeconds / 3600);
        const mins = Math.floor((elapsedSeconds % 3600) / 60);
        const secs = elapsedSeconds % 60;
        const pad = (n) => (n < 10 ? "0" + n : "" + n);
        return (hrs > 0 ? pad(hrs) + ":" : "") + pad(mins) + ":" + pad(secs);
    }

    readonly property string formattedTimeFull: {
        const hrs = Math.floor(elapsedSeconds / 3600);
        const mins = Math.floor((elapsedSeconds % 3600) / 60);
        const secs = elapsedSeconds % 60;
        const pad = (n) => (n < 10 ? "0" + n : "" + n);
        return pad(hrs) + ":" + pad(mins) + ":" + pad(secs);
    }

    function load(): void {}

    function start(): void {
        Quickshell.execDetached(["bash", "-c", `${Directories.recordScriptPath}`]);
    }

    function togglePause(): void {
        if (root.isPaused) {
            root.resume();
        } else {
            root.pause();
        }
    }

    function pause(): void {
        Quickshell.execDetached(["bash", "-c", `${Directories.recordScriptPath} --pause`]);
        root.isPaused = true;
    }

    function resume(): void {
        Quickshell.execDetached(["bash", "-c", `${Directories.recordScriptPath} --resume`]);
        root.isPaused = false;
    }

    function stop(): void {
        Quickshell.execDetached(["bash", "-c", `${Directories.recordScriptPath} --stop`]);
        root.isRecording = false;
        root.isPaused = false;
        root.elapsedSeconds = 0;
        GlobalStates.recordSelecting = false;
        root.justSaved = true;
        justSavedResetTimer.restart();
    }

    // Timer counting elapsed recording time
    Timer {
        id: secondTimer
        interval: 1000
        repeat: true
        running: root.isRecording && !root.isPaused
        onTriggered: {
            root.elapsedSeconds++;
        }
    }

    // Background poller to stay synchronized with wf-recorder under all circumstances
    Timer {
        id: statusCheckerTimer
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!checkProc.running) {
                checkProc.running = true;
            }
        }
    }

    Process {
        id: checkProc
        command: ["bash", "-c", "ps -o pid=,etimes=,state= -C wf-recorder 2>/dev/null || true"]
        stdout: StdioCollector {
            id: procCollector
            onStreamFinished: {
                const text = procCollector.text.trim();
                if (text.length > 0) {
                    const lines = text.split("\n");
                    const firstLine = lines[0].trim();
                    const parts = firstLine.split(/\s+/);
                    const etimes = parts.length > 1 ? parseInt(parts[1], 10) : 0;
                    const state = parts.length > 2 ? parts[2] : (parts.length > 1 ? parts[1] : "");
                    const paused = state.indexOf("T") !== -1;
                    if (!root.isRecording) {
                        root.isRecording = true;
                        if (!isNaN(etimes) && etimes >= 0) {
                            root.elapsedSeconds = etimes;
                        }
                    }
                    root.isPaused = paused;
                } else {
                    if (root.isRecording) {
                        root.isRecording = false;
                        root.isPaused = false;
                        root.elapsedSeconds = 0;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "recording"

        function start(): void {
            root.start();
        }

        function stop(): void {
            root.stop();
        }

        function pause(): void {
            root.pause();
        }

        function resume(): void {
            root.resume();
        }

        function togglePause(): void {
            root.togglePause();
        }

        function notifyStarted(): void {
            GlobalStates.recordSelecting = false;
            root.isRecording = true;
            root.isPaused = false;
            root.elapsedSeconds = 0;
        }

        function notifyStopped(): void {
            root.isRecording = false;
            root.isPaused = false;
            root.elapsedSeconds = 0;
            GlobalStates.recordSelecting = false;
            root.justSaved = true;
            justSavedResetTimer.restart();
        }

        function notifyCancelled(): void {
            GlobalStates.recordSelecting = false;
        }

        function notifyPaused(): void {
            root.isPaused = true;
        }

        function notifyResumed(): void {
            root.isPaused = false;
        }
    }
}
