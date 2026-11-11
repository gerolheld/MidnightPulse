// Midnight Pulse · Dynamic Island — music pill that morphs with the track and pulses on the beat.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "common" as Common

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.constraintHints: Plasmoid.CanFillArea
    preferredRepresentation: compactRepresentation
    toolTipMainText: media.present ? media.title : "Midnight Pulse"
    toolTipSubText: media.present ? media.artist : "Ничего не играет"

    Common.Palette { id: mp; paused: occ.covered }
    Common.MediaSource { id: media }
    Common.Occlusion { id: occ; fullscreenOnly: true }
    Common.PulseSource { id: pulse; active: media.playing && !occ.covered }

    compactRepresentation: Island {}
    fullRepresentation: BigPlayer {}

    component Island: Item {
        id: island
        readonly property bool showTrack: media.present && media.title.length > 0
        // HoverHandler isn't stolen by the child buttons (a MouseArea's containsMouse is), and a short
        // linger stops the controls from flickering away while the pointer travels onto a button.
        HoverHandler { id: hh }
        property bool hovered: false
        Timer { id: unhover; interval: 350; onTriggered: island.hovered = false }
        Connections { target: hh; function onHoveredChanged() { if (hh.hovered) { unhover.stop(); island.hovered = true; } else unhover.restart(); } }
        readonly property real targetWidth: !showTrack ? 92
                                        : Math.min(440, Math.max(250, 30 + 10 + titleMetrics.width + 14 + 96 + 22))   // fixed: room for the controls is always reserved, so hovering never resizes/moves the island
        // the panel layout owns `width`, so the springy morph has to drive the Layout hints instead
        property real animWidth: targetWidth
        Behavior on animWidth { SpringAnimation { spring: 3.2; damping: 0.32; epsilon: 0.25 } }
        Layout.preferredWidth: animWidth
        Layout.minimumWidth: animWidth
        Layout.maximumWidth: animWidth
        Layout.fillHeight: true
        clip: false

        TextMetrics { id: titleMetrics; font.family: mp.font; font.pixelSize: 12; font.weight: Font.DemiBold
                      text: media.title + (media.artist ? "  ·  " + media.artist : "") }

        // --- pill body ---
        Item {
            id: pill
            anchors.centerIn: parent
            width: island.animWidth
            height: Math.min(parent.height - 6, 30)
            scale: 1 + pulse.beatPulse * 0.035
            Behavior on scale { NumberAnimation { duration: 90 } }

            // outer glow, brighter on beats
            Rectangle {
                anchors.fill: parent; anchors.margins: -3; radius: height / 2
                color: "transparent"
                border.width: 3
                border.color: mp.tint(0.37, 0.82, 1.0, 0.10 + pulse.beatPulse * 0.35 + (media.playing ? 0.06 : 0))
                visible: media.playing
            }
            Rectangle {
                id: body
                anchors.fill: parent
                radius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: mp.tint(0.08, 0.12, 0.26, 0.96) }
                    GradientStop { position: 1; color: mp.tint(0.02, 0.04, 0.10, 0.96) }
                }
                border.width: 1
                border.color: island.hovered || root.expanded ? mp.strokeHi : mp.tint(0.47, 0.75, 1, 0.20 + pulse.beatPulse * 0.4)
                Behavior on border.color { ColorAnimation { duration: mp.fast } }
                clip: true

                // travelling shimmer while playing
                Rectangle {
                    width: 80; height: parent.height * 2; rotation: 20; y: -parent.height / 2
                    visible: media.playing
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: mp.tint(0.37, 0.82, 1, 0.10) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    NumberAnimation on x { from: -120; to: body.width + 40; duration: 4200; loops: Animation.Infinite; running: media.playing && !occ.covered }
                }
            }

            // --- idle content: breathing dots ---
            Row {
                anchors.centerIn: parent
                spacing: 5
                opacity: island.showTrack ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: mp.normal } }
                Repeater {
                    model: 5
                    Rectangle {
                        width: 5; height: 5; radius: 2.5
                        anchors.verticalCenter: parent.verticalCenter
                        color: mp.accentHi
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: !island.showTrack && !occ.covered
                            PauseAnimation { duration: index * 140 }
                            NumberAnimation { from: 0.25; to: 1; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 1; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                            PauseAnimation { duration: (4 - index) * 140 }
                        }
                    }
                }
            }

            // --- track content ---
            Item {
                anchors.fill: parent
                anchors.leftMargin: 3; anchors.rightMargin: 12
                opacity: island.showTrack ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: mp.normal } }

                // spinning vinyl-ish art
                Item {
                    id: artBox
                    width: pill.height - 6; height: width
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle { anchors.fill: parent; radius: width / 2; color: mp.surface }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: media.art
                        sourceSize: Qt.size(96, 96)
                        fillMode: Image.PreserveAspectCrop
                        smooth: true; mipmap: true
                        visible: false
                        asynchronous: true
                    }
                    MultiEffect {
                        anchors.fill: art; source: art
                        maskEnabled: true; maskSource: artMask
                        maskThresholdMin: 0.5; maskSpreadAtMin: 1.0
                        visible: art.status === Image.Ready
                    }
                    Item { id: artMask; anchors.fill: parent; visible: false; layer.enabled: true; layer.smooth: true
                        Rectangle { anchors.fill: parent; radius: width / 2; antialiasing: true } }
                    Kirigami.Icon { anchors.centerIn: parent; width: 14; height: 14; source: "audio-x-generic"; visible: art.status !== Image.Ready; color: mp.accentHi }
                    Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 2.5; color: mp.bg; border.color: Qt.rgba(1,1,1,0.3) }
                    RotationAnimation on rotation { from: 0; to: 360; duration: 9000; loops: Animation.Infinite; running: media.playing && !occ.covered }
                }

                // title marquee
                Item {
                    id: marquee
                    anchors.left: artBox.right; anchors.leftMargin: 10
                    anchors.right: tail.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    height: 16
                    clip: true
                    readonly property bool overflow: label.implicitWidth > width
                    Text {
                        id: label
                        text: titleMetrics.text
                        color: mp.text
                        font.family: mp.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                        x: 0
                        SequentialAnimation on x {
                            running: marquee.overflow && media.playing && !occ.covered
                            loops: Animation.Infinite
                            PauseAnimation { duration: 1800 }
                            NumberAnimation { to: marquee.width - label.implicitWidth; duration: Math.max(1500, (label.implicitWidth - marquee.width) * 28); easing.type: Easing.InOutSine }
                            PauseAnimation { duration: 1400 }
                            NumberAnimation { to: 0; duration: 700; easing.type: Easing.OutCubic }
                        }
                        onTextChanged: x = 0
                    }
                }

                // right side: spectrum ↔ controls
                Item {
                    id: tail
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 86
                    height: pill.height - 10
                    Common.SpectrumBars {
                        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 56
                        anchors.topMargin: 1; anchors.bottomMargin: 1
                        paused: occ.covered; source: pulse; count: 7; spacing: 3; mirrored: true
                        centered: true; gain: 2.2; minLevel: 0.18
                        idle: !media.playing || !pulse.hasSignal
                        opacity: island.hovered ? 0 : 1
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: mp.fast } }
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        opacity: island.hovered ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: mp.fast } }
                        MiniButton { icon: "media-skip-backward"; onClicked: media.previous() }
                        MiniButton { icon: media.playing ? "media-playback-pause" : "media-playback-start"; big: true; onClicked: media.toggle() }
                        MiniButton { icon: "media-skip-forward"; onClicked: media.next() }
                    }
                }

                // progress hairline along the bottom
                Rectangle {
                    anchors.left: artBox.right; anchors.leftMargin: 10
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                    height: 2; radius: 1
                    width: (marquee.width) * media.progress
                    color: mp.accent
                    opacity: 0.7
                    Behavior on width { enabled: !occ.covered; NumberAnimation { duration: 500 } }
                }
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            z: -1
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) media.toggle();
                else root.expanded = !root.expanded;
            }
            onWheel: wheel => { if (wheel.angleDelta.y > 0) media.previous(); else media.next(); }
        }
    }

    component MiniButton: Rectangle {
        id: mb
        property string icon
        property bool big: false
        signal clicked()
        width: big ? 22 : 18; height: width; radius: width / 2
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: big ? mp.accent : (mba.containsMouse ? mp.surfaceHi : "transparent")
        scale: mba.pressed ? 0.85 : (mba.containsMouse ? 1.12 : 1)
        Behavior on scale { NumberAnimation { duration: 110 } }
        Behavior on color { ColorAnimation { duration: 110 } }
        Kirigami.Icon { anchors.centerIn: parent; width: mb.big ? 12 : 12; height: width; source: mb.icon; color: mb.big ? mp.bg : mp.text; isMask: true }
        MouseArea { id: mba; anchors.fill: parent; hoverEnabled: true; onClicked: mb.clicked() }
    }

    component BigPlayer: Item {
        id: big
        Layout.minimumWidth: 460; Layout.maximumWidth: 460
        Layout.minimumHeight: 250; Layout.maximumHeight: 250
        clip: true

        // blurred album-art backdrop
        Image { id: backArt; anchors.fill: parent; source: media.art; fillMode: Image.PreserveAspectCrop; visible: false; asynchronous: true; sourceSize: Qt.size(256, 256) }
        MultiEffect {
            anchors.fill: parent; anchors.margins: -40
            source: backArt; blurEnabled: true; blur: 1.0; blurMax: 64; saturation: 0.2
            opacity: backArt.status === Image.Ready ? 0.45 : 0
            Behavior on opacity { NumberAnimation { duration: mp.slow } }
        }
        Rectangle { anchors.fill: parent; gradient: Gradient {
            GradientStop { position: 0; color: mp.tint(0.03, 0.05, 0.12, 0.35) }
            GradientStop { position: 1; color: mp.tint(0.03, 0.05, 0.12, 0.85) } } }

        // album art with glow, breathing with the bass
        Item {
            id: cover
            x: 16; y: 16; width: 150; height: 150
            scale: 1 + pulse.bass * 0.04
            Rectangle { anchors.fill: parent; anchors.margins: -6; radius: 24; color: "transparent"
                border.width: 6; border.color: mp.tint(0.12, 0.69, 0.92, 0.12 + pulse.beatPulse * 0.4) }
            Image { id: coverImg; anchors.fill: parent; source: media.art; fillMode: Image.PreserveAspectCrop; visible: false; asynchronous: true; sourceSize: Qt.size(300, 300) }
            MultiEffect { anchors.fill: parent; source: coverImg; maskEnabled: true; maskSource: coverMask; visible: coverImg.status === Image.Ready }
            Item { id: coverMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: 18 } }
            Rectangle { anchors.fill: parent; radius: 18; color: mp.surface; visible: coverImg.status !== Image.Ready
                Kirigami.Icon { anchors.centerIn: parent; width: 56; height: 56; source: "spotify-client"; fallback: "audio-x-generic" } }
        }

        ColumnLayout {
            anchors { left: cover.right; leftMargin: 18; right: parent.right; rightMargin: 18; top: parent.top; topMargin: 22 }
            spacing: 2
            Text { Layout.fillWidth: true; text: media.title || "Ничего не играет"; color: mp.text; elide: Text.ElideRight
                   font.family: mp.fontDisplay; font.pixelSize: 19; font.weight: Font.DemiBold }
            Text { Layout.fillWidth: true; text: media.artist || "Включи что-нибудь в Spotify"; color: mp.accentHi; elide: Text.ElideRight
                   font.family: mp.font; font.pixelSize: 13 }
            Text { Layout.fillWidth: true; text: media.album; color: mp.textDim; elide: Text.ElideRight; visible: text.length > 0
                   font.family: mp.font; font.pixelSize: 11 }
            Item { Layout.preferredHeight: 10 }
            // progress
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: 14
                Rectangle { id: track; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Qt.rgba(1,1,1,0.10) }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; height: 4; radius: 2; width: parent.width * (seekArea.pressed ? seekArea.preview : media.progress)
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: mp.accent2 } GradientStop { position: 1; color: mp.accentHi } } }
                Rectangle { width: 10; height: 10; radius: 5; color: "white"; anchors.verticalCenter: parent.verticalCenter
                    x: parent.width * (seekArea.pressed ? seekArea.preview : media.progress) - 5
                    scale: seekArea.containsMouse ? 1.2 : 0.8; Behavior on scale { NumberAnimation { duration: 120 } } }
                MouseArea { id: seekArea; anchors.fill: parent; hoverEnabled: true; property real preview: 0
                    onPressed: m => preview = Math.max(0, Math.min(1, m.x / width))
                    onPositionChanged: m => { if (pressed) preview = Math.max(0, Math.min(1, m.x / width)); }
                    onReleased: media.seek(preview) }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: media.clock(media.position); color: mp.textDim; font.family: mp.font; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                Text { text: media.clock(media.length); color: mp.textDim; font.family: mp.font; font.pixelSize: 10 }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 14
                BigButton { icon: "media-playlist-shuffle"; small: true; active: media.player && media.player.shuffle === true
                            onClicked: if (media.player) media.player.shuffle = !media.player.shuffle }
                BigButton { icon: "media-skip-backward"; onClicked: media.previous() }
                BigButton { icon: media.playing ? "media-playback-pause" : "media-playback-start"; primary: true; onClicked: media.toggle() }
                BigButton { icon: "media-skip-forward"; onClicked: media.next() }
                BigButton { icon: "media-playlist-repeat"; small: true; onClicked: media.raise() }
            }
        }

        Common.SpectrumBars {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 10 }
            height: 56
            paused: occ.covered; source: pulse; count: 48; spacing: 3; mirrored: true
            idle: !media.playing || !pulse.hasSignal
            opacity: 0.85
        }
    }

    component BigButton: Rectangle {
        id: bb
        property string icon
        property bool primary: false
        property bool small: false
        property bool active: false
        signal clicked()
        implicitWidth: primary ? 46 : (small ? 28 : 34); implicitHeight: implicitWidth; radius: implicitWidth / 2
        color: primary ? mp.accent : (bba.containsMouse ? Qt.rgba(1,1,1,0.10) : "transparent")
        border.width: primary ? 0 : 1
        border.color: active ? mp.accentHi : (bba.containsMouse ? mp.stroke : "transparent")
        scale: bba.pressed ? 0.88 : (bba.containsMouse ? 1.08 : 1)
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle { anchors.fill: parent; anchors.margins: -5; radius: width / 2; visible: bb.primary; color: "transparent"
            border.width: 2; border.color: mp.tint(0.37, 0.82, 1, 0.2 + pulse.beatPulse * 0.6) }
        Kirigami.Icon { anchors.centerIn: parent; width: bb.primary ? 22 : (bb.small ? 14 : 18); height: width; source: bb.icon
            color: bb.primary ? mp.bg : (bb.active ? mp.accentHi : mp.text); isMask: true }
        MouseArea { id: bba; anchors.fill: parent; hoverEnabled: true; onClicked: bb.clicked() }
    }
}
