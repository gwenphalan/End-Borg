pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
Singleton {
    id:root
    readonly property var settings:Config.options.musicAssistant
    readonly property bool connected:HomeAssistant.connected && !!HomeAssistant.services.music_assistant?.get_library && !!HomeAssistant.services.music_assistant?.search
    readonly property var availablePlayers:HomeAssistant.connected ? HomeAssistant.entities.filter(e=>HomeAssistant.domain(e)==="media_player" && HomeAssistant.available(e) && !Config.options.homeAssistant.hiddenEntities.includes(e.entity_id) && HomeAssistant.entityRegistry.some(r=>r.entity_id===e.entity_id && ["music_assistant","mass"].includes(r.platform))).map(e=>({player_id:e.entity_id,name:HomeAssistant.name(e),entity:e})) : []
    property string error:""
    property string message:""
    onMessageChanged:if(message)noticeTimer.restart()
    Timer { id:noticeTimer;interval:5000;onTriggered:root.message="" }
    function entryId(playerId){return HomeAssistant.entityRegistry.find(r=>r.entity_id===playerId)?.config_entry_id || "";}
    function invoke(service,data,playerId,response,callback){
        if(!connected){if(callback)callback(null,Translation.tr("Music Assistant is not available through Home Assistant"));return;}
        const payload={domain:"music_assistant",service:service,service_data:data};
        if(playerId)payload.target={entity_id:playerId};
        if(response)payload.return_response=true;
        HomeAssistant.send("call_service",payload,(result,failure)=>{if(callback)callback(response ? result?.response : result,failure);});
    }
    function browse(type,query,favorites,offset,playerId,callback){
        const id=entryId(playerId);
        if(!id){callback(null,Translation.tr("Choose a Music Assistant player first"));return;}
        const size=settings.pageSize;
        const searching=query.trim().length>0;
        const args=searching ? {config_entry_id:id,name:query.trim(),media_type:[type],limit:Math.min(size,100)} : {config_entry_id:id,media_type:type,favorite:favorites,limit:size,offset:offset,order_by:"sort_name"};
        invoke(searching ? "search" : "get_library",args,"",true,callback);
    }
    function browseFolder(item,playerId,callback){
        if(!connected || !availablePlayers.some(p=>p.player_id===playerId)){callback(null,Translation.tr("Choose an available Music Assistant player first"));return;}
        HomeAssistant.send("media_player/browse_media",{entity_id:playerId,media_content_id:item.uri,media_content_type:item.media_type},(result,failure)=>{
            if(failure){callback(null,failure);return;}
            callback({items:(result?.children || []).map(child=>({name:child.title,uri:child.media_content_id,media_type:child.media_content_type,image:child.thumbnail,can_browse:child.can_expand,can_play:child.can_play}))},null);
        });
    }
    function play(item,playerId,option,callback){
        if(!availablePlayers.some(p=>p.player_id===playerId) || !item?.uri){error=Translation.tr("Choose an available Music Assistant player first");if(callback)callback(null,error);return;}
        invoke("play_media",{media_id:[item.uri],media_type:item.media_type || "track",enqueue:option || "replace"},playerId,false,(result,failure)=>{error=failure || "";if(!failure)Persistent.states.homeAssistant.mediaEntityId=playerId;message=failure ? "" : option==="add" ? Translation.tr("Added to queue") : Translation.tr("Playing on %1").arg(availablePlayers.find(p=>p.player_id===playerId)?.name || playerId);if(callback)callback(result,failure);});
    }
    function openSettings(){Quickshell.execDetached(["env","QS_SETTINGS_PAGE=musicAssistant","QS_SETTINGS_CATEGORY=home","QS_SETTINGS_SUBSECTION=musicAssistant","qs","-p",Quickshell.shellPath("settings.qml")]);}
    onConnectedChanged:{error="";message="";}
}
