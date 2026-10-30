pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id:root
    // Desktop selection is transient. Remembering a room/player in Home must
    // never hijack this computer's media controls.
    property string remoteId:""
    readonly property var localPlayer:MprisController.activePlayer
    readonly property bool localPlaying:localPlayer?.isPlaying || false
    readonly property var remotePlayer:remoteId ? HomeAssistant.mediaPlayers.find(p => p.entity_id===remoteId) || null : !localPlayer ? HomeAssistant.barPlayer : null
    readonly property bool useRemote:remotePlayer!==null
    onLocalPlayingChanged:if (localPlaying) remoteId=""
    onLocalPlayerChanged:if (localPlayer?.isPlaying) remoteId=""
    function select(choice) {
        if (!choice) return;
        remoteId=choice.entityId || "";
        if (choice.player) MprisController.trackedPlayer=choice.player;
    }
}
