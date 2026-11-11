// Midnight Pulse · synced lyrics on the wallpaper.
// Track from MPRIS (Spotify first), time-synced lyrics from LRCLIB (lrclib.net, open database —
// Spotify's own lyrics are not available to third-party apps). No synced lyrics → nothing is shown.
// Each line flies in word by word, is "sung" karaoke-style (fill runs through the letters), and
// floats away blurred when the next one comes. Everything stops while a fullscreen window covers us.
import QtQuick
import QtQuick.Effects
import "common" as Common

Item {
    id: ly
    property var pal                     // the wallpaper's Common.Palette
    property bool live: true             // false while covered → no timers, no animation
    property real offsetMs: 250          // lyrics a hair early feel more "in time"

    Common.MediaSource { id: media }
    property bool forcePlay: false       // previews/tests only
    readonly property bool playing: media.playing || forcePlay

    // ---------------- data ----------------
    property var lines: []               // [{ t: ms, text }]
    property string key: ""
    property var cache: ({})
    property int cur: -1
    property real lineP: 0               // karaoke progress through the current line, 0..1

    // smooth clock: MPRIS position is refreshed every 500 ms; interpolate in between
    property double anchorPos: 0
    property double anchorAt: 0
    Connections {
        target: media
        function onPositionChanged() { ly.anchorPos = media.position / 1000; ly.anchorAt = Date.now(); }
        function onTitleChanged() { Qt.callLater(ly.load); }
        function onArtistChanged() { Qt.callLater(ly.load); }
        function onLengthChanged() { Qt.callLater(ly.load); }
    }
    function nowMs() { return anchorPos + (playing ? Date.now() - anchorAt : 0) + offsetMs; }

    function enc(s) { return encodeURIComponent(s || ""); }
    function cleanTitle(t) {             // "Song (feat. X) - Remastered 2011" → "Song"
        return t.replace(/\s*[\(\[](feat|ft|with)\.?[^\)\]]*[\)\]]/ig, "")
                .replace(/\s+-\s+.*(remaster|version|edit|mix|live|mono|stereo).*$/i, "").trim();
    }
    function get(url, cb) {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            var d = null;
            try { d = x.status === 200 ? JSON.parse(x.responseText) : null; } catch (e) { d = null; }
            cb(d);
        };
        x.open("GET", url);
        x.setRequestHeader("Lrclib-Client", "Midnight Pulse KDE wallpaper");
        x.send();
    }
    function parse(lrc) {
        var out = [], re = /\[(\d+):(\d+(?:\.\d+)?)\]/g;
        var rows = String(lrc).split("\n");
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i], stamps = [], m;
            re.lastIndex = 0;
            while ((m = re.exec(row)) !== null) stamps.push(parseInt(m[1]) * 60000 + parseFloat(m[2]) * 1000);
            var text = row.replace(re, "").trim();
            if (text === "♪" || text === "♫") text = "";
            for (var j = 0; j < stamps.length; j++) out.push({ t: stamps[j], text: text });
        }
        out.sort(function (a, b) { return a.t - b.t; });
        return out;
    }
    function done(k, l) { cache[k] = l; if (k === key) { lines = l; cur = -1; tick(); } }

    function load() {
        if (!media.title) { key = ""; lines = []; cur = -1; return; }
        var dur = Math.round(media.length / 1e6);
        var k = media.artist + "\u0001" + media.title;
        if (k === key) return;
        key = k; lines = []; cur = -1; show("");
        if (cache[k] !== undefined) { lines = cache[k]; tick(); return; }
        var base = "https://lrclib.net/api/";
        get(base + "get?artist_name=" + enc(media.artist) + "&track_name=" + enc(media.title)
            + "&album_name=" + enc(media.album) + (dur > 0 ? "&duration=" + dur : ""), function (d) {
            if (d && d.syncedLyrics) { done(k, parse(d.syncedLyrics)); return; }
            if (d && d.instrumental) { done(k, []); return; }
            // fuzzy search; the duration check keeps slowed/sped-up edits from getting wrong timings
            get(base + "search?track_name=" + enc(cleanTitle(media.title)) + "&artist_name=" + enc(media.artist.split(",")[0]), function (arr) {
                var best = null;
                for (var i = 0; arr && i < arr.length; i++) {
                    var c = arr[i];
                    if (!c.syncedLyrics) continue;
                    if (dur > 0 && Math.abs((c.duration || 0) - dur) > 3) continue;
                    best = c; break;
                }
                done(k, best ? parse(best.syncedLyrics) : []);
            });
        });
    }
    Component.onCompleted: load()

    function tick() {
        if (!lines.length) { if (cur !== -1) { cur = -1; show(""); } return; }
        var t = nowMs(), i = cur;
        if (i < 0 || i >= lines.length || lines[i].t > t || (i + 1 < lines.length && lines[i + 1].t <= t)) {
            i = -1;
            for (var j = 0; j < lines.length; j++) { if (lines[j].t <= t) i = j; else break; }
        }
        if (i !== cur) { cur = i; show(i >= 0 ? lines[i].text : ""); }
        if (i >= 0) {
            var end = i + 1 < lines.length ? lines[i + 1].t : lines[i].t + 5000;
            var span = Math.min(end - lines[i].t, 400 + lines[i].text.length * 140);   // sing at a human pace
            lineP = Math.max(0, Math.min(1, (t - lines[i].t) / Math.max(1, span * 0.92)));
        }
    }
    Timer { interval: 33; repeat: true; running: ly.live && ly.playing && ly.lines.length > 0; onTriggered: ly.tick() }
    onLiveChanged: if (live) tick()

    // ---------------- view ----------------
    // two slots take turns: the new line flies in, the previous one floats up and dissolves
    property int slot: 0
    function show(text) {
        var incoming = slot === 0 ? b : a, outgoing = slot === 0 ? a : b;
        slot = 1 - slot;
        outgoing.leave();
        if (text.length) incoming.enter(text); else incoming.clear();
    }

    opacity: playing ? 1 : 0.35
    Behavior on opacity { NumberAnimation { duration: 600 } }

    LineView { id: a; host: ly }
    LineView { id: b; host: ly }

    // faint preview of the next line
    Text {
        id: nextLine
        readonly property string want: ly.cur >= 0 && ly.cur + 1 < ly.lines.length ? ly.lines[ly.cur + 1].text : ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height / 2 + Math.max(a.height, b.height) / 2 + 18
        width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        color: ly.pal ? ly.pal.textDim : "white"
        font.family: ly.pal ? ly.pal.font : "Inter"; font.pixelSize: 20; font.weight: Font.Medium
        opacity: 0
        onWantChanged: { if (!ly.live) { text = want; opacity = want ? 0.32 : 0; return; } swap.restart(); }
        SequentialAnimation {
            id: swap
            NumberAnimation { target: nextLine; property: "opacity"; to: 0; duration: 250 }
            ScriptAction { script: nextLine.text = nextLine.want }
            PauseAnimation { duration: 350 }
            NumberAnimation { target: nextLine; property: "opacity"; to: nextLine.want ? 0.32 : 0; duration: 600; easing.type: Easing.OutCubic }
        }
    }

    component LineView: Item {
        id: lv
        property var host                    // the Lyrics item (inline components can't see outer ids)
        property string text: ""
        property var words: []              // [{ w, c0, c1, row }]
        property int total: 1
        property real fs: 52
        property bool active: false
        readonly property real p: active ? lv.host.lineP : 1
        width: lv.host.width
        height: col.height
        y: (lv.host.height - height) / 2
        opacity: 0
        visible: opacity > 0.01

        function layout(t) {
            var ws = t.split(/\s+/).filter(function (w) { return w.length; });
            var chars = t.length;
            var maxW = lv.host.width;
            fs = Math.max(30, Math.min(56, maxW / (0.56 * Math.max(1, chars))));
            var twoRows = chars * 0.56 * fs > maxW;
            if (twoRows) fs = Math.max(28, Math.min(52, maxW / (0.56 * Math.ceil(chars / 2 + 4))));
            var out = [], c = 0, half = chars / 2;
            for (var i = 0; i < ws.length; i++) {
                var row = twoRows && c + ws[i].length / 2 > half ? 1 : 0;
                out.push({ w: ws[i], c0: c, c1: c + ws[i].length, row: row, i: i });
                c += ws[i].length + 1;
            }
            total = Math.max(1, c - 1);
            words = out;
        }
        function enter(t) {
            leaveAnim.stop();
            text = t; layout(t);
            active = true;
            lv.scale = 1; drift.y = 0; lv.blurAmount = 0;
            opacity = 1;
            stamp++;                           // restarts the per-word entrance
        }
        function leave() {
            if (opacity <= 0.01) return;
            active = false;
            leaveAnim.restart();
        }
        function clear() { leaveAnim.stop(); opacity = 0; text = ""; words = []; }
        property int stamp: 0

        transform: Translate { id: drift }
        ParallelAnimation {
            id: leaveAnim
            NumberAnimation { target: lv; property: "opacity"; to: 0; duration: 700; easing.type: Easing.InQuad }
            NumberAnimation { target: drift; property: "y"; to: -70; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: lv; property: "scale"; to: 0.9; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: lv; property: "blurAmount"; to: 1; duration: 700 }
        }

        // glow + blur for the whole line
        layer.enabled: lv.host.live && opacity > 0.01
        property real blurAmount: 0
        layer.effect: MultiEffect {
            blurEnabled: lv.blurAmount > 0.01; blur: lv.blurAmount; blurMax: 32
            shadowEnabled: true; shadowColor: lv.host.pal.accent; shadowBlur: 1.0; shadowOpacity: 0.85
            shadowHorizontalOffset: 0; shadowVerticalOffset: 0
        }

        Column {
            id: col
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: lv.fs * 0.12
            Repeater {
                model: lv.words.length && lv.words[lv.words.length - 1].row === 1 ? 2 : 1
                Row {
                    id: rowItem
                    required property int index
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: lv.fs * 0.3
                    Repeater {
                        model: lv.words.filter(function (w) { return w.row === rowItem.index; })
                        Item {
                            id: wd
                            required property var modelData
                            width: base.implicitWidth; height: base.implicitHeight
                            readonly property real f: Math.max(0, Math.min(1, (lv.p * lv.total - modelData.c0) / Math.max(1, modelData.c1 - modelData.c0)))
                            // entrance: rise, scale and fade in, one word after another
                            opacity: 0
                            transform: [Translate { id: rise; y: 0 }, Scale { id: sc; origin.x: wd.width / 2; origin.y: wd.height; xScale: 1; yScale: 1 }]
                            Connections {
                                target: lv
                                function onStampChanged() { wd.play(); }
                            }
                            Component.onCompleted: play()
                            function play() {
                                if (!lv.host.live) { opacity = 1; rise.y = 0; sc.xScale = sc.yScale = 1; return; }
                                opacity = 0; rise.y = lv.fs * 0.55; sc.xScale = sc.yScale = 0.8;
                                inAnim.restart();
                            }
                            SequentialAnimation {
                                id: inAnim
                                PauseAnimation { duration: wd.modelData.i * 55 }
                                ParallelAnimation {
                                    NumberAnimation { target: wd; property: "opacity"; to: 1; duration: 380; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: rise; property: "y"; to: 0; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                                    NumberAnimation { target: sc; properties: "xScale,yScale"; to: 1; duration: 620; easing.type: Easing.OutBack }
                                }
                            }
                            // unsung
                            Text {
                                id: base
                                text: wd.modelData.w
                                color: Qt.rgba(lv.host.pal.text.r, lv.host.pal.text.g, lv.host.pal.text.b, 0.34)
                                font.family: lv.host.pal.fontDisplay; font.pixelSize: lv.fs; font.weight: Font.Bold
                                font.letterSpacing: -0.5
                            }
                            // sung: the same word, revealed left → right
                            Item {
                                width: base.width * wd.f; height: base.height; clip: true
                                Text {
                                    text: wd.modelData.w
                                    color: "white"
                                    font: base.font
                                    style: Text.Normal
                                }
                            }
                            // a bright little "pen" at the fill edge while the word is being sung
                            Rectangle {
                                visible: wd.f > 0.02 && wd.f < 0.98
                                x: base.width * wd.f - 1; y: base.height * 0.18
                                width: 2; height: base.height * 0.64; radius: 1
                                color: lv.host.pal.accentHi; opacity: 0.9
                            }
                        }
                    }
                }
            }
        }
    }
}
