// Midnight Pulse · Chat — one Telegram conversation on the desktop, fully featured:
// text, photos/files (📎 or drag & drop), voice notes (record + play), stickers, replies,
// edit/delete, reactions, older history on scroll, open media full size.
// Talks to midnight-pulse-tg (ws://127.0.0.1:47801). Messages are only marked read when you
// hover the card; while a game is fullscreen nothing animates, only the unread badge updates.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import QtMultimedia
import QtWebSockets
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5
import org.kde.kirigami as Kirigami
import "common" as Common

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: fullRepresentation
    Common.Occlusion { id: occ }
    Common.Palette { id: mp; paused: occ.covered }
    readonly property bool calm: occ.covered

    // ---------------- state ----------------
    property string token: ""
    property string connState: "connecting"
    property string stateMsg: ""
    property var peer: ({ name: "", avatar: "", status: "", online: false })
    property int unread: 0
    property bool typing: false
    property int loveTick: 0
    property real upload: -1            // 0..1 while a file goes up / down
    property bool recording: false
    property int recSec: 0
    property var replyTo: null          // { id, who, text }
    property var editing: null          // { id, text }
    property var stickers: []
    property bool loadingOlder: false
    property bool noMoreOlder: false
    property bool olderReady: false     // no "load older" until the first history has settled
    property string toast: ""
    property int playingId: -1
    property var attachments: []        // files waiting to be sent (pasted screenshot, copied files)
    property bool pasteWaiting: false
    ListModel { id: msgs }
    signal scrollToEnd()

    P5.DataSource {
        id: exec; engine: "executable"
        onNewData: (src, data) => { root.token = (data.stdout || "").trim(); disconnectSource(src); }
    }
    function readToken() { exec.connectSource("cat \"$HOME/.config/midnight-pulse/tg-token\" 2>/dev/null"); }
    Component.onCompleted: readToken()

    WebSocket {
        id: ws
        url: root.token ? "ws://127.0.0.1:47801/?token=" + root.token : ""
        active: false
        onTextMessageReceived: m => root.handle(JSON.parse(m))
        onStatusChanged: if (ws.status === WebSocket.Error || ws.status === WebSocket.Closed) { root.connState = "offline"; retry.start(); }
    }
    onTokenChanged: { ws.active = false; ws.active = token.length > 0; }
    Timer { id: retry; interval: 4000; onTriggered: { if (!root.token) root.readToken(); else { ws.active = false; ws.active = true; } } }
    function sendCmd(o) { if (ws.status === WebSocket.Open) ws.sendTextMessage(JSON.stringify(o)); }

    function toRow(m) {
        return { mid: m.id, out: m.out, date: m.date, text: m.text, kind: m.kind, media: m.media ? "file://" + m.media : "",
                 mw: m.w || 0, mh: m.h || 0, label: m.label || "", reactions: JSON.stringify(m.reactions || []), read: !!m.read,
                 fresh: false, edited: !!m.edited, fwd: m.fwd || "", file: m.file || "", dur: m.dur || 0,
                 rid: m.reply ? m.reply.id : 0, rwho: m.reply ? (m.reply.who || "") : "", rtext: m.reply ? (m.reply.text || "") : "" };
    }
    function indexOfId(id) { for (var i = msgs.count - 1; i >= 0; i--) if (msgs.get(i).mid === id) return i; return -1; }
    function showToast(t) { toast = t; toastOff.restart(); }
    Timer { id: toastOff; interval: 2600; onTriggered: root.toast = "" }
    Timer { id: settle; interval: 1200; onTriggered: root.olderReady = true }

    function handle(o) {
        switch (o.t) {
        case "state": connState = o.state; stateMsg = o.msg || ""; break;
        case "peer": peer = o; break;
        case "history":
            msgs.clear(); noMoreOlder = false; olderReady = false;
            for (var i = 0; i < o.msgs.length; i++) msgs.append(toRow(o.msgs[i]));
            root.scrollToEnd(); settle.restart();
            break;
        case "older":
            loadingOlder = false;
            if (!o.msgs.length) { noMoreOlder = true; break; }
            for (var q = o.msgs.length - 1; q >= 0; q--) if (indexOfId(o.msgs[q].id) < 0) msgs.insert(0, toRow(o.msgs[q]));
            break;
        case "msg": {
            var e = indexOfId(o.m.id);
            if (e >= 0) { msgs.set(e, toRow(o.m)); break; }
            var r = toRow(o.m); r.fresh = true;
            msgs.append(r);
            if (!o.m.out) { typing = false; loveTick++; }
            root.scrollToEnd();
            break; }
        case "edit": { var k = indexOfId(o.m.id); if (k >= 0) msgs.set(k, toRow(o.m)); break; }
        case "del": for (var d = 0; d < o.ids.length; d++) { var j = indexOfId(o.ids[d]); if (j >= 0) msgs.remove(j); } break;
        case "read": for (var n = 0; n < msgs.count; n++) if (msgs.get(n).out) msgs.setProperty(n, "read", msgs.get(n).mid <= o.max); break;
        case "typing": typing = true; typingOff.restart(); break;
        case "unread": unread = o.n; break;
        case "progress": upload = o.p; break;
        case "recording": recording = o.on; recSec = o.sec; break;
        case "stickers": stickers = o.items; break;
        case "toast": showToast(o.text); break;
        case "clip":
            if (!pasteWaiting) break;
            pasteWaiting = false; pasteFallback.stop();
            if (o.files.length) attachments = attachments.concat(o.files).slice(0, 10);
            else pasteText();
            break;
        case "voice": player.stop(); player.source = "file://" + o.path; playingId = o.id; player.play(); break;
        }
    }
    Timer { id: typingOff; interval: 6000; onTriggered: root.typing = false }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {}
        onPlaybackStateChanged: if (playbackState === MediaPlayer.StoppedState) root.playingId = -1
    }

    function hhmm(sec) { return Qt.formatTime(new Date(sec * 1000), "hh:mm"); }
    function dayLabel(sec) {
        var d = new Date(sec * 1000), now = new Date();
        var a = new Date(d.getFullYear(), d.getMonth(), d.getDate()), b = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        var diff = Math.round((b - a) / 86400000);
        return diff === 0 ? "Сегодня" : diff === 1 ? "Вчера" : Qt.formatDate(d, diff < 300 ? "d MMMM" : "d MMMM yyyy");
    }
    function sameDay(a, b) { return new Date(a * 1000).toDateString() === new Date(b * 1000).toDateString(); }
    function mmss(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60); }
    // Ctrl+V: ask the daemon for clipboard images / files first; plain text pastes as usual.
    signal pasteText()
    function requestPaste() {
        if (ws.status !== WebSocket.Open) { pasteText(); return; }
        pasteWaiting = true; sendCmd({ t: "paste" }); pasteFallback.restart();
    }
    Timer { id: pasteFallback; interval: 1500; onTriggered: if (root.pasteWaiting) { root.pasteWaiting = false; root.pasteText(); } }
    function isImage(p) { return /\.(png|jpe?g|webp|gif|bmp)$/i.test(p); }
    function baseName(p) { return String(p).split("/").pop(); }
    function sendFiles(urls, caption) {
        for (var i = 0; i < urls.length; i++)
            sendCmd({ t: "send_file", path: decodeURIComponent(String(urls[i]).replace("file://", "")),
                      caption: i === 0 ? (caption || "") : "", reply: replyTo ? replyTo.id : 0 });
        replyTo = null;
    }

    // ---------------- card ----------------
    fullRepresentation: Item {
        id: card
        Layout.minimumWidth: 320; Layout.minimumHeight: 360
        Layout.preferredWidth: 360; Layout.preferredHeight: 460

        // privacy mode (screen recordings): only the message list is blurred and ignores the mouse;
        // header, composer and card stay normal. Hovering doesn't mark messages read meanwhile.
        readonly property bool privacy: Plasmoid.configuration.privacy

        HoverHandler { id: hover }
        Timer { interval: 700; running: hover.hovered && root.unread > 0 && !card.privacy; onTriggered: root.sendCmd({ t: "read" }) }

        // drag & drop files onto the card
        DropArea {
            id: drop
            anchors.fill: parent
            onEntered: d => { d.accepted = d.hasUrls; }
            onDropped: d => { if (d.hasUrls) { root.sendFiles(d.urls, input.text.trim()); input.text = ""; d.acceptProposedAction(); } }
        }
        Rectangle {
            anchors.fill: parent; radius: 18; z: 50
            visible: drop.containsDrag
            color: mp.tint(0.04, 0.07, 0.16, 0.92); border.color: mp.accent; border.width: 2
            Column { anchors.centerIn: parent; spacing: 6
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "📎"; font.pixelSize: 34 }
                Text { text: "Отпусти, чтобы отправить"; color: mp.text; font.family: mp.font; font.pixelSize: 13 } }
        }

        // love glow on new incoming messages
        Rectangle {
            id: glow
            anchors.fill: parent; anchors.margins: -6; radius: 22
            color: "transparent"; border.width: 2; border.color: "#FF6E96"
            opacity: 0
            SequentialAnimation {
                id: glowAnim
                NumberAnimation { target: glow; property: "opacity"; to: 0.85; duration: 260; easing.type: Easing.OutCubic }
                NumberAnimation { target: glow; property: "opacity"; to: 0; duration: 2200; easing.type: Easing.InOutSine }
            }
        }
        Connections { target: root; function onLoveTickChanged() { if (!root.calm) { glowAnim.restart(); heart.burst(); } } }

        // ---- header ----
        Item {
            id: header
            x: 4; y: 2; width: parent.width - 8; height: 46
            Item {
                id: av
                width: 40; height: 40; anchors.verticalCenter: parent.verticalCenter
                Rectangle { anchors.fill: parent; radius: 20; gradient: Gradient {
                    GradientStop { position: 0; color: mp.accent } GradientStop { position: 1; color: mp.accent2 } } }
                Image { id: avImg; anchors.fill: parent; source: root.peer.avatar ? "file://" + root.peer.avatar : ""; visible: false
                        fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(96, 96); cache: false }
                MultiEffect { anchors.fill: avImg; source: avImg; maskEnabled: true; maskSource: avMask; visible: avImg.status === Image.Ready
                              maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                Item { id: avMask; anchors.fill: parent; visible: false; layer.enabled: true; layer.smooth: true
                       Rectangle { anchors.fill: parent; radius: width / 2; antialiasing: true } }
                Text { anchors.centerIn: parent; visible: avImg.status !== Image.Ready; text: (root.peer.name || "♥").charAt(0)
                       color: "white"; font.family: mp.font; font.pixelSize: 17; font.weight: Font.Bold }
                Rectangle {
                    width: 12; height: 12; radius: 6; x: 29; y: 29
                    visible: root.peer.online; color: "#3EE6A0"; border.color: mp.bg; border.width: 2
                    SequentialAnimation on scale { running: root.peer.online && !root.calm; loops: Animation.Infinite
                        NumberAnimation { to: 1.18; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine } }
                }
            }
            Column {
                anchors.left: av.right; anchors.leftMargin: 10; anchors.right: heartBox.left; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text { width: parent.width; text: root.peer.name || "Telegram"; elide: Text.ElideRight
                       color: mp.text; font.family: mp.fontDisplay; font.pixelSize: 15; font.weight: Font.DemiBold }
                Row {
                    spacing: 4
                    Text { text: root.typing ? "печатает" : (root.peer.status || ""); color: root.typing || root.peer.online ? mp.accentHi : mp.textDim
                           font.family: mp.font; font.pixelSize: 11 }
                    Row {
                        visible: root.typing; spacing: 2; anchors.bottom: parent.bottom; anchors.bottomMargin: 3
                        Repeater { model: 3
                            Rectangle { width: 3; height: 3; radius: 1.5; color: mp.accentHi
                                SequentialAnimation on opacity { running: root.typing && !root.calm; loops: Animation.Infinite
                                    PauseAnimation { duration: index * 160 }
                                    NumberAnimation { from: 0.2; to: 1; duration: 300 } NumberAnimation { from: 1; to: 0.2; duration: 300 }
                                    PauseAnimation { duration: (2 - index) * 160 } } } }
                    }
                }
            }
            Item {
                id: heartBox
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40
                Text {
                    id: heart
                    anchors.centerIn: parent
                    text: "♥"; font.pixelSize: 22
                    color: root.unread > 0 ? "#FF6E96" : mp.textFaint
                    Behavior on color { ColorAnimation { duration: 400 } }
                    function burst() { beat.restart(); for (var i = 0; i < 5; i++) floater.createObject(heartBox, { delay: i * 120, dx: (Math.random() - 0.5) * 34 }); }
                    SequentialAnimation { id: beat
                        NumberAnimation { target: heart; property: "scale"; to: 1.45; duration: 140; easing.type: Easing.OutQuad }
                        NumberAnimation { target: heart; property: "scale"; to: 0.95; duration: 160 }
                        NumberAnimation { target: heart; property: "scale"; to: 1.25; duration: 120 }
                        NumberAnimation { target: heart; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack } }
                    SequentialAnimation on opacity { running: root.unread > 0 && !root.calm; loops: Animation.Infinite
                        NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine } }
                }
                Rectangle {
                    visible: root.unread > 0
                    x: 24; y: 2; height: 16; width: Math.max(16, badgeText.implicitWidth + 8); radius: 8
                    color: "#FF6E96"; border.color: mp.bg; border.width: 2
                    Text { id: badgeText; anchors.centerIn: parent; text: root.unread > 99 ? "99+" : root.unread
                           color: "white"; font.family: mp.font; font.pixelSize: 9; font.weight: Font.Bold }
                }
                Component {
                    id: floater
                    Text {
                        id: fl
                        property int delay: 0
                        property real dx: 0
                        text: "♥"; color: "#FF8FB0"; font.pixelSize: 11 + Math.random() * 6
                        x: heartBox.width / 2 - 5; y: 10; opacity: 0
                        SequentialAnimation {
                            running: true
                            PauseAnimation { duration: fl.delay }
                            ParallelAnimation {
                                NumberAnimation { target: fl; property: "y"; to: -46; duration: 1300; easing.type: Easing.OutCubic }
                                NumberAnimation { target: fl; property: "x"; to: fl.x + fl.dx; duration: 1300; easing.type: Easing.OutSine }
                                SequentialAnimation {
                                    NumberAnimation { target: fl; property: "opacity"; to: 0.95; duration: 200 }
                                    NumberAnimation { target: fl; property: "opacity"; to: 0; duration: 1100 } }
                            }
                            ScriptAction { script: fl.destroy() }
                        }
                    }
                }
            }
        }
        Rectangle { id: sep; y: header.y + header.height + 6; x: 4; width: parent.width - 8; height: 1; color: mp.stroke }
        // transfer progress on the separator
        Rectangle { y: sep.y - 1; x: 4; height: 3; radius: 1.5; visible: root.upload >= 0
                    width: (parent.width - 8) * Math.max(0.03, root.upload); color: mp.accentHi
                    Behavior on width { NumberAnimation { duration: 200 } } }

        // ---- not connected states ----
        Column {
            anchors.centerIn: list
            width: list.width - 40
            spacing: 8
            visible: root.connState !== "ok"
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.connState === "offline" ? "☁" : "✦"; font.pixelSize: 30; color: mp.accentHi }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                color: mp.textDim; font.family: mp.font; font.pixelSize: 12
                text: root.connState === "no_config" || root.connState === "need_login"
                      ? "Подключи Telegram: открой терминал и выполни\nmidnight-pulse-tg-login"
                      : root.connState === "offline" ? "Служба чата не запущена" : root.connState === "error" ? "Ошибка: " + root.stateMsg : "Подключаюсь…"
            }
        }

        // ---- messages ----
        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; top: sep.bottom; bottom: composer.top; topMargin: 6; bottomMargin: 6 }
            enabled: !card.privacy
            layer.enabled: card.privacy
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 32; blurMultiplier: 0.5 }
            visible: root.connState === "ok"
            clip: true
            spacing: 6
            model: msgs
            boundsBehavior: Flickable.StopAtBounds
            Connections { target: root; function onScrollToEnd() { Qt.callLater(list.positionViewAtEnd); } }
            QQC2.ScrollBar.vertical: QQC2.ScrollBar { width: 4; policy: QQC2.ScrollBar.AsNeeded }
            // older history when scrolled to the top
            onContentYChanged: if (root.olderReady && atYBeginning && msgs.count > 0 && !root.loadingOlder && !root.noMoreOlder && contentHeight > height) {
                root.loadingOlder = true; root.sendCmd({ t: "more", before: msgs.get(0).mid });
            }
            header: Item { width: list.width; height: root.loadingOlder ? 26 : 0
                Text { anchors.centerIn: parent; visible: root.loadingOlder; text: "загружаю…"; color: mp.textFaint; font.family: mp.font; font.pixelSize: 10 } }

            delegate: Item {
                id: row
                required property int index
                required property int mid
                required property bool out
                required property int date
                required property string text
                required property string kind
                required property string media
                required property int mw
                required property int mh
                required property string label
                required property string reactions
                required property bool read
                required property bool fresh
                required property bool edited
                required property string fwd
                required property string file
                required property int dur
                required property int rid
                required property string rwho
                required property string rtext
                readonly property var rx: JSON.parse(reactions)
                readonly property bool isSticker: kind === "sticker" && media.length > 0
                readonly property bool hasPic: (kind === "photo" || kind === "video") && media.length > 0
                readonly property bool isVoice: kind === "voice"
                readonly property bool dayBreak: index === 0 || !root.sameDay(date, msgs.get(Math.max(0, index - 1)).date)
                readonly property real dayH: dayBreak ? 30 : 0
                width: list.width
                height: dayH + bubble.height + (rx.length ? 24 : 0)

                // `fresh` animates once and is cleared in the model right away, so a recycled or
                // re-created delegate (scrolling, leaving a game) always shows the message fully.
                transform: Translate { id: slide; x: 0 }
                Component.onCompleted: {
                    if (!fresh) return;
                    if (!root.calm) { opacity = 0; slide.x = out ? 30 : -30; appear.start(); }
                    msgs.setProperty(index, "fresh", false);
                }
                ParallelAnimation { id: appear
                    NumberAnimation { target: row; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                    NumberAnimation { target: slide; property: "x"; to: 0; duration: 420; easing.type: Easing.OutBack } }

                HoverHandler { id: rowHover }

                // date separator
                Rectangle {
                    visible: row.dayBreak
                    anchors.horizontalCenter: parent.horizontalCenter; y: 4
                    height: 20; width: dayText.implicitWidth + 18; radius: 10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    Text { id: dayText; anchors.centerIn: parent; text: root.dayLabel(row.date); color: mp.textDim; font.family: mp.font; font.pixelSize: 10 }
                }

                Rectangle {
                    id: bubble
                    y: row.dayH
                    readonly property real maxW: list.width * 0.80
                    readonly property real picW: Math.min(maxW - 8, 230)
                    readonly property real picH: row.mw > 0 ? Math.min(250, picW * row.mh / row.mw) : 150
                    readonly property real topH: (row.fwd ? 18 : 0) + (row.rid ? 40 : 0)
                    x: row.out ? list.width - width - 6 : 4
                    width: row.isSticker ? 124 : Math.max(timeLine.implicitWidth + 24, row.isVoice ? 210 : 0, row.rid ? 160 : 0,
                           row.hasPic ? picW + 8 : Math.min(maxW, Math.max(body.implicitWidth, fwdText.visible ? fwdText.implicitWidth : 0) + 24))
                    height: row.isSticker ? 124 + topH + 14
                          : topH + (row.hasPic ? picH + 8 : 0) + (row.isVoice ? 42 : 0) + (body.visible ? body.implicitHeight + 12 : 4) + 16
                    radius: 16
                    color: row.isSticker ? "transparent" : (row.out ? "transparent" : mp.tint(0.10, 0.16, 0.34, 0.85))
                    border.color: row.isSticker || row.out ? "transparent" : mp.stroke
                    gradient: row.out && !row.isSticker ? outGrad : null
                    Gradient { id: outGrad; orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.darker(mp.accent2, 1.55) } GradientStop { position: 1; color: Qt.darker(mp.accent, 1.45) } }

                    // forwarded
                    Text { id: fwdText; visible: row.fwd.length > 0; x: 12; y: 6; text: "↪ Переслано от " + row.fwd
                           width: Math.min(implicitWidth, bubble.width - 24); elide: Text.ElideRight
                           color: row.out ? Qt.rgba(1, 1, 1, 0.8) : mp.accentHi; font.family: mp.font; font.pixelSize: 10; font.italic: true }
                    // reply quote
                    Rectangle {
                        visible: row.rid > 0
                        x: 8; y: (row.fwd ? 22 : 6); width: bubble.width - 16; height: 32; radius: 8
                        color: row.out ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                        Rectangle { width: 3; height: parent.height - 8; y: 4; x: 4; radius: 1.5; color: row.out ? "white" : mp.accent }
                        Column { x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 18
                            Text { width: parent.width; text: row.rwho; elide: Text.ElideRight; color: row.out ? "white" : mp.accentHi
                                   font.family: mp.font; font.pixelSize: 10; font.weight: Font.DemiBold }
                            Text { width: parent.width; text: row.rtext; elide: Text.ElideRight; color: row.out ? Qt.rgba(1, 1, 1, 0.8) : mp.textDim
                                   font.family: mp.font; font.pixelSize: 10; textFormat: Text.PlainText; maximumLineCount: 1 } }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { var k = root.indexOfId(row.rid); if (k >= 0) list.positionViewAtIndex(k, ListView.Center); } }
                    }

                    // picture (photo / video thumb / sticker)
                    Image {
                        id: pic
                        visible: false
                        source: row.hasPic || row.isSticker ? row.media : ""
                        asynchronous: true; fillMode: row.isSticker ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                        sourceSize: Qt.size(460, 500)
                        x: row.isSticker ? 0 : 4; y: bubble.topH + (row.isSticker ? 0 : 4)
                        width: row.isSticker ? 124 : bubble.picW; height: row.isSticker ? 124 : bubble.picH
                    }
                    MultiEffect {
                        anchors.fill: pic; source: pic; visible: pic.status === Image.Ready && (row.hasPic || row.isSticker)
                        maskEnabled: row.hasPic; maskSource: picMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0
                        scale: picArea.containsMouse && row.hasPic ? 1.02 : 1
                        Behavior on scale { NumberAnimation { duration: 160 } }
                    }
                    Item { id: picMask; anchors.fill: pic; visible: false; layer.enabled: true; layer.smooth: true
                           Rectangle { anchors.fill: parent; radius: 12; antialiasing: true } }
                    Rectangle {
                        visible: row.kind === "video" && row.hasPic
                        anchors.centerIn: pic; width: 40; height: 40; radius: 20; color: Qt.rgba(0, 0, 0, 0.5)
                        Text { anchors.centerIn: parent; text: "▶"; color: "white"; font.pixelSize: 16 }
                    }
                    Rectangle {
                        visible: row.kind === "video" && row.hasPic && row.dur > 0
                        x: pic.x + 8; y: pic.y + 8; height: 18; width: durT.implicitWidth + 12; radius: 9; color: Qt.rgba(0, 0, 0, 0.55)
                        Text { id: durT; anchors.centerIn: parent; text: root.mmss(row.dur); color: "white"; font.family: mp.font; font.pixelSize: 10 }
                    }
                    MouseArea { id: picArea; anchors.fill: pic; enabled: row.hasPic; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: root.sendCmd({ t: "open", id: row.mid }) }

                    // voice note player
                    Row {
                        id: voiceRow
                        visible: row.isVoice
                        x: 10; y: bubble.topH + 8; spacing: 10
                        readonly property bool mine: root.playingId === row.mid
                        readonly property bool playing: mine && player.playbackState === MediaPlayer.PlayingState
                        readonly property real progress: mine && player.duration > 0 ? player.position / player.duration : 0
                        Rectangle {
                            width: 32; height: 32; radius: 16
                            color: row.out ? Qt.rgba(1, 1, 1, 0.22) : mp.accent
                            Text { anchors.centerIn: parent; text: voiceRow.playing ? "❚❚" : "▶"; color: "white"; font.pixelSize: voiceRow.playing ? 10 : 13 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (voiceRow.mine) { if (voiceRow.playing) player.pause(); else player.play(); }
                                             else root.sendCmd({ t: "voice", id: row.mid }); } }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: 4
                            Row { spacing: 2; height: 14
                                Repeater { model: 22
                                    Rectangle { width: 3; radius: 1.5; anchors.verticalCenter: parent.verticalCenter
                                        height: 3 + Math.abs(Math.sin((index + row.mid) * 1.7)) * 11
                                        color: index / 22 < voiceRow.progress ? (row.out ? "white" : mp.accentHi) : (row.out ? Qt.rgba(1, 1, 1, 0.4) : mp.textFaint) } } }
                            Text { text: voiceRow.mine ? root.mmss(player.position / 1000) : root.mmss(row.dur)
                                   color: row.out ? Qt.rgba(1, 1, 1, 0.75) : mp.textDim; font.family: mp.font; font.pixelSize: 10 }
                        }
                    }

                    Text {
                        id: body
                        readonly property string fallback: row.isSticker || row.isVoice || row.hasPic ? ""
                            : row.kind === "text" ? "" : (row.label || "[" + row.kind + "]") + (row.file && row.kind === "other" ? "\n" + row.file : "")
                        visible: text.length > 0
                        x: 12; y: bubble.topH + (row.hasPic ? bubble.picH + 12 : (row.isVoice ? 48 : 8))
                        width: bubble.width - 24
                        text: row.text.length ? row.text : fallback
                        wrapMode: Text.Wrap
                        color: row.out ? "white" : mp.text
                        font.family: mp.font; font.pixelSize: 13
                        textFormat: Text.PlainText
                        MouseArea { anchors.fill: parent; enabled: !row.text.length && (row.kind === "other" || row.kind === "video")
                                    cursorShape: Qt.PointingHandCursor; onClicked: root.sendCmd({ t: "open", id: row.mid }) }
                    }
                    Row {
                        id: timeLine
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                        spacing: 3
                        Text { visible: row.edited; text: "изм."; font.family: mp.font; font.pixelSize: 9; font.italic: true
                               color: row.out && !row.isSticker ? Qt.rgba(1, 1, 1, 0.65) : mp.textFaint }
                        Text { text: root.hhmm(row.date); font.family: mp.font; font.pixelSize: 9
                               color: row.out && !row.isSticker ? Qt.rgba(1, 1, 1, 0.75) : mp.textFaint }
                        Text { visible: row.out; text: row.read ? "✓✓" : "✓"; font.pixelSize: 9; font.weight: Font.Bold
                               color: row.isSticker ? mp.accentHi : (row.read ? "white" : Qt.rgba(1, 1, 1, 0.6)) }
                    }
                }

                // reactions under the bubble
                Row {
                    anchors.top: bubble.bottom; anchors.topMargin: 3
                    x: row.out ? bubble.x + bubble.width - width : bubble.x
                    spacing: 4
                    Repeater {
                        model: row.rx
                        Rectangle {
                            id: chip
                            required property var modelData
                            height: 20; width: rxText.implicitWidth + 12; radius: 10
                            color: modelData.mine ? mp.tint(0.12, 0.69, 0.92, 0.30) : Qt.rgba(1, 1, 1, 0.06)
                            border.color: modelData.mine ? mp.strokeHi : mp.stroke
                            Text { id: rxText; anchors.centerIn: parent; text: chip.modelData.e + (chip.modelData.n > 1 ? " " + chip.modelData.n : "")
                                   color: mp.text; font.pixelSize: 11 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.sendCmd({ t: "react", id: row.mid, e: chip.modelData.e }) }
                        }
                    }
                }

                // hover action bar: reactions + reply / edit / delete
                Rectangle {
                    id: actions
                    readonly property var emojis: ["❤️", "😂", "🔥", "👍", "😢"]
                    z: 5
                    height: 28; width: actRow.implicitWidth + 14; radius: 14
                    color: mp.tint(0.05, 0.09, 0.19, 0.97); border.color: mp.strokeHi
                    y: Math.max(0, bubble.y - 10)
                    x: row.out ? Math.max(0, bubble.x - width + 24) : Math.min(list.width - width, bubble.x + bubble.width - 24)
                    opacity: rowHover.hovered && root.connState === "ok" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    Row {
                        id: actRow; anchors.centerIn: parent; spacing: 3
                        Repeater {
                            model: actions.emojis
                            Text {
                                id: emo
                                required property string modelData
                                text: modelData; font.pixelSize: 14
                                scale: em.containsMouse ? 1.35 : 1
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                MouseArea { id: em; anchors.fill: parent; anchors.margins: -2; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.sendCmd({ t: "react", id: row.mid, e: emo.modelData }) }
                            }
                        }
                        Rectangle { width: 1; height: 16; color: mp.stroke; anchors.verticalCenter: parent.verticalCenter }
                        ActionIcon { pal: mp; icon: "mail-reply-sender"; tip: "Ответить"
                            onClicked: { root.editing = null; root.replyTo = { id: row.mid, who: row.out ? "Вы" : root.peer.name,
                                         text: row.text || row.label || (row.hasPic ? "📷 фото" : row.isSticker ? "стикер" : "") }; input.forceActiveFocus(); } }
                        ActionIcon { pal: mp; visible: row.out && row.kind === "text"; icon: "document-edit"; tip: "Изменить"
                            onClicked: { root.replyTo = null; root.editing = { id: row.mid, text: row.text }; input.text = row.text;
                                         input.cursorPosition = input.text.length; input.forceActiveFocus(); } }
                        ActionIcon { pal: mp; visible: row.out; icon: "edit-delete"; tip: "Удалить у всех"; danger: true
                            onClicked: confirmDel.ask(row.mid) }
                    }
                }
            }
        }

        // jump-to-bottom button
        Rectangle {
            anchors.right: list.right; anchors.rightMargin: 10; anchors.bottom: list.bottom; anchors.bottomMargin: 6
            width: 30; height: 30; radius: 15; z: 6
            visible: root.connState === "ok" && !list.atYEnd && list.contentHeight > list.height
            color: mp.tint(0.05, 0.09, 0.19, 0.95); border.color: mp.strokeHi
            Text { anchors.centerIn: parent; text: "⌄"; color: mp.text; font.pixelSize: 16 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: list.positionViewAtEnd() }
        }

        // delete confirmation
        Rectangle {
            id: confirmDel
            property int target: 0
            function ask(id) { target = id; visible = true; }
            visible: false; z: 40
            anchors.centerIn: parent; width: 240; height: 96; radius: 16
            color: mp.tint(0.05, 0.09, 0.19, 0.98); border.color: mp.strokeHi
            Column { anchors.centerIn: parent; spacing: 12
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Удалить сообщение у всех?"; color: mp.text; font.family: mp.font; font.pixelSize: 13 }
                Row { anchors.horizontalCenter: parent.horizontalCenter; spacing: 10
                    PillButton { pal: mp; label: "Отмена"; onClicked: confirmDel.visible = false }
                    PillButton { pal: mp; label: "Удалить"; danger: true; onClicked: { root.sendCmd({ t: "delete", id: confirmDel.target }); confirmDel.visible = false; } } } }
        }

        // toast
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter; y: sep.y + 10; z: 30
            height: 26; width: toastT.implicitWidth + 22; radius: 13
            color: mp.tint(0.05, 0.09, 0.19, 0.96); border.color: mp.strokeHi
            opacity: root.toast ? 1 : 0; visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Text { id: toastT; anchors.centerIn: parent; text: root.toast; color: mp.text; font.family: mp.font; font.pixelSize: 11 }
        }

        // emoji + sticker panel
        Rectangle {
            id: stickerPanel
            property bool open: false
            z: 20
            anchors { left: parent.left; right: parent.right; bottom: composer.top; bottomMargin: 6; leftMargin: 2; rightMargin: 2 }
            height: open ? 196 : 0; clip: true; radius: 16
            visible: height > 0
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            color: mp.panel; border.color: mp.stroke
            Column {
                anchors.fill: parent; anchors.margins: 8; spacing: 6
                Flow { width: parent.width; spacing: 4
                    Repeater { model: ["😘", "🥰", "❤️", "😂", "😭", "🥺", "😍", "🔥", "👍", "🤗", "😴", "💙"]
                        Text { id: emj; required property string modelData; text: modelData; font.pixelSize: 19
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { input.insert(input.cursorPosition, emj.modelData); input.forceActiveFocus(); } } } } }
                GridView {
                    id: grid
                    width: parent.width; height: parent.height - 34
                    cellWidth: Math.floor(width / 5); cellHeight: 62; clip: true
                    model: root.stickers
                    delegate: Item {
                        id: st
                        required property var modelData
                        width: grid.cellWidth; height: 62
                        Image { anchors.centerIn: parent; width: 54; height: 54; source: "file://" + st.modelData.path; fillMode: Image.PreserveAspectFit
                                asynchronous: true; sourceSize: Qt.size(108, 108)
                                scale: sa2.containsMouse ? 1.15 : 1; Behavior on scale { NumberAnimation { duration: 120 } } }
                        MouseArea { id: sa2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.sendCmd({ t: "send_sticker", id: st.modelData.id, reply: root.replyTo ? root.replyTo.id : 0 });
                                         root.replyTo = null; stickerPanel.open = false; } }
                    }
                    Text { anchors.centerIn: parent; visible: !root.stickers.length; text: "Загружаю стикеры…"; color: mp.textFaint
                           font.family: mp.font; font.pixelSize: 11 }
                }
            }
        }

        Dialogs.FileDialog {
            id: filePicker
            title: "Отправить " + (root.peer.name || "")
            fileMode: Dialogs.FileDialog.OpenFiles
            nameFilters: ["Фото и видео (*.jpg *.jpeg *.png *.webp *.gif *.mp4 *.mov *.webm)", "Все файлы (*)"]
            onAccepted: { root.sendFiles(selectedFiles, input.text.trim()); input.text = ""; }
        }

        // ---- composer ----
        Column {
            id: composer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 2; rightMargin: 2 }
            visible: root.connState === "ok"
            spacing: 6

            // reply / edit bar
            Rectangle {
                width: parent.width; height: 36; radius: 12
                visible: root.replyTo !== null || root.editing !== null
                color: Qt.rgba(1, 1, 1, 0.05); border.color: mp.stroke
                Rectangle { x: 8; y: 7; width: 3; height: 22; radius: 1.5; color: mp.accent }
                Column { x: 18; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 54
                    Text { text: root.editing ? "✏ Редактирование" : "↩ " + (root.replyTo ? root.replyTo.who : "")
                           color: mp.accentHi; font.family: mp.font; font.pixelSize: 10; font.weight: Font.DemiBold }
                    Text { width: parent.width; elide: Text.ElideRight; color: mp.textDim; font.family: mp.font; font.pixelSize: 10
                           textFormat: Text.PlainText; maximumLineCount: 1
                           text: root.editing ? root.editing.text : (root.replyTo ? root.replyTo.text : "") } }
                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "✕"
                       color: mp.textDim; font.pixelSize: 13
                       MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                           onClicked: { if (root.editing) input.text = ""; root.replyTo = null; root.editing = null; } } }
            }

            // pending attachments (pasted / copied) — Enter sends them, the text becomes the caption
            Rectangle {
                width: parent.width; height: 72; radius: 14
                visible: root.attachments.length > 0
                color: Qt.rgba(1, 1, 1, 0.05); border.color: mp.stroke
                ListView {
                    anchors.fill: parent; anchors.margins: 8
                    orientation: ListView.Horizontal; spacing: 8; clip: true
                    model: root.attachments
                    delegate: Item {
                        id: att
                        required property string modelData
                        required property int index
                        width: 56; height: 56
                        Rectangle { anchors.fill: parent; radius: 10; color: mp.surface; visible: !root.isImage(att.modelData)
                            Column { anchors.centerIn: parent; width: parent.width - 6
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "📄"; font.pixelSize: 18 }
                                Text { width: parent.width; text: root.baseName(att.modelData); elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter
                                       color: mp.textDim; font.family: mp.font; font.pixelSize: 8 } } }
                        Image { id: thumb; anchors.fill: parent; visible: false; source: root.isImage(att.modelData) ? "file://" + att.modelData : ""
                                fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(112, 112); asynchronous: true }
                        MultiEffect { anchors.fill: thumb; source: thumb; visible: thumb.status === Image.Ready
                                      maskEnabled: true; maskSource: thumbMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
                        Item { id: thumbMask; anchors.fill: parent; visible: false; layer.enabled: true; layer.smooth: true
                               Rectangle { anchors.fill: parent; radius: 10; antialiasing: true } }
                        Rectangle {
                            x: parent.width - 14; y: -4; width: 18; height: 18; radius: 9
                            color: mp.panel; border.color: mp.strokeHi
                            Text { anchors.centerIn: parent; text: "✕"; color: mp.text; font.pixelSize: 9 }
                            MouseArea { anchors.fill: parent; anchors.margins: -3; cursorShape: Qt.PointingHandCursor
                                onClicked: { var a = root.attachments.slice(); a.splice(att.index, 1); root.attachments = a; } }
                        }
                    }
                }
            }

            Rectangle {
                id: inputBox
                width: parent.width
                height: Math.min(100, Math.max(42, input.contentHeight + 22)); radius: 21
                color: Qt.rgba(1, 1, 1, 0.05)
                border.width: input.activeFocus ? 1.5 : 1
                border.color: root.recording ? "#FF6E96" : (input.activeFocus ? mp.accent : mp.stroke)
                Behavior on border.color { ColorAnimation { duration: mp.fast } }

                // attach + stickers
                Row {
                    id: leftTools
                    anchors.left: parent.left; anchors.leftMargin: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                    visible: !root.recording
                    ToolIcon { pal: mp; icon: "mail-attachment"; tip: "Фото или файл (можно перетащить на карточку)"; onClicked: filePicker.open() }
                    ToolIcon { pal: mp; icon: "smiley-shape-symbolic"; tip: "Эмодзи и стикеры"; active: stickerPanel.open
                        onClicked: { stickerPanel.open = !stickerPanel.open; if (stickerPanel.open) root.sendCmd({ t: "stickers" }); } }
                }
                // recording indicator replaces the text field
                Row {
                    visible: root.recording
                    anchors.left: parent.left; anchors.leftMargin: 16; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Rectangle { width: 10; height: 10; radius: 5; color: "#FF4D6D"; anchors.verticalCenter: parent.verticalCenter
                        SequentialAnimation on opacity { running: root.recording; loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 500 } NumberAnimation { to: 1; duration: 500 } } }
                    Text { text: "Запись " + root.mmss(root.recSec); color: mp.text; font.family: mp.font; font.pixelSize: 13 }
                    Text { text: "· отмена"; color: mp.textDim; font.family: mp.font; font.pixelSize: 12
                        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                                    onClicked: root.sendCmd({ t: "rec_stop", send: false }) } }
                }
                Flickable {
                    id: flick
                    visible: !root.recording
                    anchors { left: leftTools.right; right: send.left; top: parent.top; bottom: parent.bottom; leftMargin: 4; rightMargin: 6; topMargin: 12; bottomMargin: 10 }
                    contentHeight: input.contentHeight; clip: true
                    TextEdit {
                        id: input
                        width: flick.width
                        wrapMode: TextEdit.Wrap
                        color: mp.text; selectionColor: mp.accent; font.family: mp.font; font.pixelSize: 13
                        selectByMouse: true
                        onTextChanged: if (text.length && !root.editing) root.sendCmd({ t: "typing" })
                        Keys.onPressed: e => {
                            if (e.matches(StandardKey.Paste)) { e.accepted = true; root.requestPaste(); }
                            else e.accepted = false;      // everything else: normal typing
                        }
                        Connections { target: root; function onPasteText() { input.paste(); } }
                        Keys.onReturnPressed: e => { if (e.modifiers & Qt.ShiftModifier) e.accepted = false; else send.go(); }
                        Keys.onEnterPressed: send.go()
                        Keys.onEscapePressed: { root.attachments = []; root.replyTo = null; if (root.editing) { root.editing = null; text = ""; } stickerPanel.open = false; }
                        Keys.onUpPressed: e => {     // ↑ in an empty field edits your last message, like Telegram
                            if (text.length) { e.accepted = false; return; }
                            for (var i = msgs.count - 1; i >= 0; i--) { var m = msgs.get(i);
                                if (m.out && m.kind === "text") { root.replyTo = null; root.editing = { id: m.mid, text: m.text }; text = m.text; cursorPosition = text.length; return; } }
                        }
                        Text { text: root.editing ? "Изменить сообщение…" : "Сообщение…"; color: mp.textFaint; font: input.font; visible: !input.text.length }
                    }
                }
                // send / mic button
                Rectangle {
                    id: send
                    anchors.right: parent.right; anchors.rightMargin: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                    width: 32; height: 32; radius: 16
                    readonly property bool hasText: input.text.trim().length > 0 || root.attachments.length > 0
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: root.recording ? "#FF4D6D" : mp.accent2 }
                        GradientStop { position: 1; color: root.recording ? "#FF6E96" : mp.accent } }
                    scale: sa.pressed ? 0.88 : 1
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                    Kirigami.Icon { anchors.centerIn: parent; width: 16; height: 16; isMask: true; color: "white"
                                    source: root.recording || send.hasText || root.editing ? "document-send" : "audio-input-microphone" }
                    QQC2.ToolTip.visible: sa.containsMouse && !send.hasText && !root.editing; QQC2.ToolTip.delay: 600
                    QQC2.ToolTip.text: root.recording ? "Отправить голосовое" : "Записать голосовое"
                    function go() {
                        var t = input.text.trim();
                        if (root.editing) {
                            if (t.length && t !== root.editing.text) root.sendCmd({ t: "edit", id: root.editing.id, text: t });
                            root.editing = null; input.text = ""; return;
                        }
                        if (root.attachments.length) {
                            root.sendFiles(root.attachments, t); root.attachments = []; input.text = ""; return;
                        }
                        if (!t.length) return;
                        root.sendCmd({ t: "send", text: t, reply: root.replyTo ? root.replyTo.id : 0 });
                        root.replyTo = null; input.text = "";
                    }
                    MouseArea { id: sa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.recording) { root.sendCmd({ t: "rec_stop", send: true, reply: root.replyTo ? root.replyTo.id : 0 }); root.replyTo = null; }
                            else if (send.hasText || root.editing) send.go();
                            else root.sendCmd({ t: "rec_start" });
                        } }
                }
            }
        }
    }

    // ---------------- small components (inline components get the palette passed in as `pal`) ----------------
    component ActionIcon: Item {
        id: ai
        property var pal
        property string icon
        property string tip
        property bool danger: false
        signal clicked()
        width: 20; height: 20
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Kirigami.Icon { anchors.centerIn: parent; width: 14; height: 14; source: ai.icon; isMask: true
                        color: aia.containsMouse ? (ai.danger ? "#FF6E96" : ai.pal.accentHi) : ai.pal.textDim
                        scale: aia.containsMouse ? 1.2 : 1; Behavior on scale { NumberAnimation { duration: 110 } } }
        QQC2.ToolTip.visible: aia.containsMouse; QQC2.ToolTip.text: ai.tip; QQC2.ToolTip.delay: 500
        MouseArea { id: aia; anchors.fill: parent; anchors.margins: -2; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ai.clicked() }
    }
    component ToolIcon: Rectangle {
        id: ti
        property var pal
        property string icon
        property string tip
        property bool active: false
        signal clicked()
        width: 32; height: 32; radius: 16
        color: active ? ti.pal.tint(0.12, 0.69, 0.92, 0.22) : (tia.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
        Kirigami.Icon { anchors.centerIn: parent; width: 17; height: 17; source: ti.icon; isMask: true
                        color: ti.active || tia.containsMouse ? ti.pal.accentHi : ti.pal.textDim }
        QQC2.ToolTip.visible: tia.containsMouse; QQC2.ToolTip.text: ti.tip; QQC2.ToolTip.delay: 600
        MouseArea { id: tia; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ti.clicked() }
    }
    component PillButton: Rectangle {
        id: pb
        property var pal
        property string label
        property bool danger: false
        signal clicked()
        height: 28; width: pbt.implicitWidth + 26; radius: 14
        color: danger ? (pba.containsMouse ? "#FF4D6D" : "#E0405C") : (pba.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07))
        Text { id: pbt; anchors.centerIn: parent; text: pb.label; color: "white"; font.family: pb.pal ? pb.pal.font : "Inter"; font.pixelSize: 12; font.weight: Font.DemiBold }
        MouseArea { id: pba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }
}
