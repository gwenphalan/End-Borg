pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.home

ColumnLayout {
    id:root
    signal dismissed()
    property string collection:"tracks"
    property string query:""
    property bool favorites:false
    property bool loading:false
    property string failure:""
    property string playerId:Config.options.musicAssistant.defaultPlayerId || HomeAssistant.barPlayer?.entity_id || ""
    property int serial:0
    property int offset:0
    property bool more:false
    property var items:[]
    property var folders:[]
    readonly property var folder:folders[folders.length-1] || null
    function openFolder(item){folders=folders.concat([item]);load(false);}
    function back(){folders=folders.slice(0,-1);load(false);}
    function resetBrowse(){folders=[];load(false);}
    readonly property var types:[{id:"tracks",title:Translation.tr("Songs")},{id:"albums",title:Translation.tr("Albums")},{id:"artists",title:Translation.tr("Artists")},{id:"playlists",title:Translation.tr("Playlists")},{id:"radios",title:Translation.tr("Radio")}]
    readonly property int playerIndex:MusicAssistant.availablePlayers.findIndex(p=>p.player_id===playerId)
    function load(append) {
        const request=++serial;failure="";
        if(!MusicAssistant.connected){loading=false;items=[];more=false;return;}
        loading=true;
        if(!append){offset=0;items=[];}
        const size=Config.options.musicAssistant.pageSize;
        const searching=query.trim().length>0;
        const type=collection==="tracks" ? "track" : collection==="radios" ? "radio" : collection.slice(0,-1);
        const completed=(result,error)=>{
            if(request!==serial)return;loading=false;failure=error || "";
            if(error && append)return; // Preserve the loaded page and allow retry.
            const rows=error ? [] : searching && !folder ? result?.[collection==="radios" ? "radio" : collection] || [] : Array.isArray(result) ? result : result?.items || [];
            items=append ? items.concat(rows) : rows;offset=items.length;more=!searching && !folder && rows.length===size;
        };
        if(folder)MusicAssistant.browseFolder(folder,playerId,completed);
        else MusicAssistant.browse(type,query,favorites,offset,playerId,completed);
    }
    function syncPlayer(){
        if (playerIndex>=0) return;
        const ids=MusicAssistant.availablePlayers.map(p=>p.player_id);
        playerId=[Config.options.musicAssistant.defaultPlayerId,HomeAssistant.selectedMediaId].find(id=>ids.includes(id)) || ids[0] || "";
    }
    onPlayerIdChanged:resetBrowse()
    onCollectionChanged:resetBrowse()
    onFavoritesChanged:load(false)
    onQueryChanged:{++serial;loading=true;items=[];more=false;folders=[];searchDelay.restart();}
    Component.onCompleted:{syncPlayer();load(false);}
    Connections { target:MusicAssistant
        function onConnectedChanged(){root.load(false);}
        function onAvailablePlayersChanged(){root.syncPlayer();}
    }
    Timer { id:searchDelay;interval:300;onTriggered:root.load(false) }
    spacing:14
    RowLayout {
        Layout.fillWidth:true
        MaterialSymbol { text:"library_music";iconSize:24;color:Appearance.colors.colPrimary }
        StyledText { Layout.fillWidth:true;text:Translation.tr("Music");font.pixelSize:Appearance.font.pixelSize.larger;font.weight:Font.Medium }
        HomeAction { symbol:"refresh";label:Translation.tr("Refresh library");enabled:MusicAssistant.connected && !root.loading;onClicked:root.load(false) }
        HomeAction { symbol:"settings";label:Translation.tr("Music Assistant settings");onClicked:{root.dismissed();MusicAssistant.openSettings();} }
        HomeAction { symbol:"close";label:Translation.tr("Close library");onClicked:root.dismissed() }
    }
    RowLayout {
        Layout.fillWidth:true
        MaterialTextArea { id:search;Layout.fillWidth:true;placeholderText:Translation.tr("Search your library and music providers");clip:true;wrapMode:TextEdit.NoWrap;Accessible.name:Translation.tr("Search music");Keys.onReturnPressed:event => { event.accepted=true; };onTextChanged:root.query=text;Keys.onEscapePressed: { if (text.length) clear(); else root.dismissed(); } }
        HomeAction { symbol:"close";label:Translation.tr("Clear search");visible:search.text.length>0;onClicked:search.clear() }
    }
    RowLayout {
        Layout.fillWidth:true
        StyledComboBox { Layout.fillWidth:true;buttonIcon:"speaker";textRole:"name";model:MusicAssistant.availablePlayers;currentIndex:root.playerIndex;displayText:MusicAssistant.availablePlayers[root.playerIndex]?.name || Translation.tr("Choose a player");onActivated:root.playerId=model[currentIndex].player_id }
        HomeAction { symbol:"star";label:Translation.tr("Favorites only");accent:root.favorites && !root.query;enabled:!root.query;onClicked:root.favorites=!root.favorites }
    }
    RowLayout {
        Layout.fillWidth:true
        spacing:4
        Repeater { model:root.types
            delegate:RippleButton {
                required property var modelData
                Layout.fillWidth:true
                implicitHeight:38;buttonRadius:Appearance.rounding.full
                colBackground:root.collection===modelData.id ? Appearance.colors.colSecondaryContainer : "transparent"
                onClicked:root.collection=modelData.id
                contentItem:StyledText { text:parent.modelData.title;horizontalAlignment:Text.AlignHCenter;verticalAlignment:Text.AlignVCenter;font.pixelSize:Appearance.font.pixelSize.small;color:root.collection===parent.modelData.id ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext }
            }
        }
    }
    RowLayout {
        Layout.fillWidth:true;visible:root.folder!==null
        HomeAction { symbol:"arrow_back";label:Translation.tr("Back to library");onClicked:root.back() }
        StyledText { Layout.fillWidth:true;text:root.folder?.name || "";elide:Text.ElideRight;font.weight:Font.Medium }
        HomeAction { visible:root.folder?.media_type!=="artist";symbol:"play_arrow";label:Translation.tr("Play all");enabled:root.playerIndex>=0;onClicked:MusicAssistant.play(root.folder,root.playerId,"replace") }
    }
    StyledText { Layout.fillWidth:true;visible:!!(root.failure || MusicAssistant.error);text:root.failure || MusicAssistant.error;wrapMode:Text.Wrap;color:Appearance.colors.colError;font.pixelSize:Appearance.font.pixelSize.small }
    StyledText { Layout.fillWidth:true;visible:!!MusicAssistant.message;text:MusicAssistant.message;wrapMode:Text.Wrap;color:Appearance.colors.colPrimary;font.pixelSize:Appearance.font.pixelSize.small }
    Item {
        Layout.fillWidth:true;Layout.fillHeight:true
        clip:true
        StyledFlickable {
            anchors.fill:parent;visible:MusicAssistant.connected
            contentHeight:list.implicitHeight
            ColumnLayout {
                id:list;width:parent.width;spacing:2
                Repeater { model:root.items
                    delegate:RippleButton {
                        id:row
                        required property var modelData
                        readonly property bool artist:modelData.media_type==="artist"
                        readonly property bool expandable:modelData.can_browse===true || ["album","artist"].includes(modelData.media_type)
                        Layout.fillWidth:true;implicitHeight:68;buttonRadius:Appearance.rounding.small
                        colBackground:Appearance.colors.colLayer1
                        padding:10
                        enabled:MusicAssistant.connected && root.playerIndex>=0 && (expandable || modelData.can_play!==false)
                        onClicked:if(expandable)root.openFolder(modelData);else MusicAssistant.play(modelData,root.playerId,"replace")
                        contentItem:RowLayout {
                            spacing:12
                            Rectangle { implicitWidth:44;implicitHeight:44;radius:Appearance.rounding.small;color:Appearance.colors.colSecondaryContainer
                                Image { id:art;anchors.fill:parent;source:row.modelData.image || "";asynchronous:true;fillMode:Image.PreserveAspectCrop }
                                MaterialSymbol { visible:art.status!==Image.Ready;anchors.centerIn:parent;text:row.artist ? "person" : root.collection==="albums" ? "album" : root.collection==="playlists" ? "queue_music" : root.collection==="radios" ? "radio" : "music_note";iconSize:22;color:Appearance.colors.colOnSecondaryContainer }
                            }
                            ColumnLayout { Layout.fillWidth:true;spacing:3
                                StyledText { Layout.fillWidth:true;text:row.modelData.name || Translation.tr("Untitled");elide:Text.ElideRight;font.weight:Font.Medium;font.pixelSize:Appearance.font.pixelSize.small }
                                StyledText { Layout.fillWidth:true;visible:text.length>0;text:(row.modelData.artists || []).map(a=>a.name).join(", ") || row.modelData.owner || row.modelData.provider || "";elide:Text.ElideRight;color:Appearance.colors.colSubtext;font.pixelSize:Appearance.font.pixelSize.smaller }
                            }
                            HomeAction { visible:!row.artist && row.modelData.can_play!==false;symbol:"playlist_add";label:Translation.tr("Add to queue");enabled:MusicAssistant.connected && root.playerIndex>=0;onClicked:MusicAssistant.play(row.modelData,root.playerId,"add") }
                            MaterialSymbol { text:row.expandable ? "chevron_right" : "play_arrow";iconSize:20;color:Appearance.colors.colSubtext }
                        }
                    }
                }
                DialogButton { Layout.alignment:Qt.AlignHCenter;visible:root.more;enabled:!root.loading;buttonText:root.loading ? Translation.tr("Loading…") : Translation.tr("Load more");onClicked:root.load(true) }
            }
        }
        ColumnLayout {
            anchors.centerIn:parent;width:Math.min(parent.width-32,380);spacing:12
            visible:!MusicAssistant.connected || (!root.items.length && !root.loading)
            MaterialSymbol { Layout.alignment:Qt.AlignHCenter;text:MusicAssistant.connected ? "search_off" : "library_music";iconSize:44;color:Appearance.colors.colSubtext }
            StyledText { Layout.fillWidth:true;horizontalAlignment:Text.AlignHCenter;wrapMode:Text.Wrap;text:MusicAssistant.connected ? root.failure ? Translation.tr("Could not load music") : root.query ? Translation.tr("No music found") : Translation.tr("Your library is empty here") : HomeAssistant.connected ? Translation.tr("Add Music Assistant in Home Assistant to browse your library") : Translation.tr("Connect Home Assistant to browse your music");font.pixelSize:Appearance.font.pixelSize.large }
            RippleButtonWithIcon { Layout.alignment:Qt.AlignHCenter;visible:!MusicAssistant.connected;materialIcon:"settings";mainText:Translation.tr("Set up in Settings");onClicked:{root.dismissed();MusicAssistant.openSettings();} }
        }
        StyledText { anchors.centerIn:parent;visible:root.loading && !root.items.length;text:Translation.tr("Loading music…");color:Appearance.colors.colSubtext }
    }
}
