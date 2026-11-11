// Picks Spotify (or, failing that, any playing MPRIS player) and keeps its position fresh.
import QtQuick
import org.kde.plasma.private.mpris as Mpris

Item {
    id: media
    visible: false
    Mpris.Mpris2Model { id: players }
    property var player: null
    readonly property bool present: !!player
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property string title: player && player.track ? player.track : ""
    readonly property string artist: player && player.artist ? player.artist : ""
    readonly property string album: player && player.album ? player.album : ""
    readonly property string art: player && player.artUrl ? player.artUrl : ""
    readonly property real length: player ? player.length : 0
    readonly property real position: player ? player.position : 0
    readonly property real progress: length > 0 ? Math.min(1, position / length) : 0
    readonly property string identity: player ? (player.identity || "") : ""

    function choose() {
        var p = players.playerForLauncherUrl("applications:spotify.desktop", 0)
             || players.playerForLauncherUrl("applications:com.spotify.Client.desktop", 0)
             || players.playerForLauncherUrl("applications:spotify-launcher.desktop", 0);
        if (!p && players.currentPlayer && players.currentPlayer.playbackStatus === Mpris.PlaybackStatus.Playing) p = players.currentPlayer;
        if (!p && player && player.playbackStatus !== undefined) return;   // keep the last one while it exists
        player = p || players.currentPlayer || null;
    }
    Connections {
        target: players
        function onRowsInserted() { Qt.callLater(media.choose); }
        function onRowsRemoved() { media.player = null; Qt.callLater(media.choose); }
        function onModelReset() { media.player = null; Qt.callLater(media.choose); }
    }
    Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: media.choose() }
    onPlayerChanged: if (player) player.updatePosition()
    Timer { interval: 500; running: media.playing; repeat: true; triggeredOnStart: true; onTriggered: if (media.player) media.player.updatePosition() }

    function toggle() { if (player) player.PlayPause(); }
    function next() { if (player && player.canGoNext) player.Next(); }
    function previous() { if (player && player.canGoPrevious) player.Previous(); }
    function raise() { if (player) player.Raise(); }
    function seek(frac) { if (player && player.canSeek && length > 0) player.position = frac * length; }
    function clock(us) { var s = Math.max(0, Math.floor(us / 1e6)); return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60); }
}
