// Midnight Pulse · Player — desktop music card with album-tinted glow and a live spectrum.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "common" as Common

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: fullRepresentation
    Common.Palette { id: mp; paused: occ.covered }
    Common.MediaSource { id: media }
    Common.Occlusion { id: occ }
    Common.PulseSource { id: pulse; active: media.playing && !occ.covered }

    component Btn: Rectangle {
        id: b
        property string icon
        property bool primary: false
        signal clicked()
        implicitWidth: primary ? 44 : 32; implicitHeight: implicitWidth; radius: implicitWidth / 2
        color: primary ? mp.accent : (ba.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
        scale: ba.pressed ? 0.86 : (ba.containsMouse ? 1.1 : 1)
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        Rectangle { anchors.fill: parent; anchors.margins: -4; radius: width / 2; color: "transparent"; visible: b.primary
            border.width: 2; border.color: mp.tint(0.37, 0.82, 1, 0.15 + pulse.beatPulse * 0.6); scale: 1 + pulse.beatPulse * 0.12 }
        Kirigami.Icon { anchors.centerIn: parent; width: b.primary ? 20 : 16; height: width; source: b.icon; color: b.primary ? mp.bg : mp.text; isMask: true }
        MouseArea { id: ba; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }

    fullRepresentation: Item {
        id: card
        Layout.minimumWidth: 400; Layout.minimumHeight: 230
        Layout.preferredWidth: 430; Layout.preferredHeight: 236
        clip: false

        // ambient glow sampled from the cover
        Image { id: amb; source: media.art; visible: false; sourceSize: Qt.size(64, 64); asynchronous: true }
        MultiEffect {
            x: -10; y: -10; width: 170; height: 170
            source: amb; blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.6; brightness: 0.1
            opacity: amb.status === Image.Ready ? (0.45 + pulse.bass * 0.4) : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        // cover with track-change flip
        Item {
            id: cover
            x: 6; y: 6; width: 132; height: 132
            scale: 1 + pulse.bass * 0.035
            Image { id: art; anchors.fill: parent; source: media.art; fillMode: Image.PreserveAspectCrop; visible: false; asynchronous: true; sourceSize: Qt.size(264, 264) }
            Rectangle { anchors.fill: parent; anchors.topMargin: 6; radius: 18; color: "#000"; opacity: 0.35; visible: art.status === Image.Ready }
            MultiEffect { anchors.fill: parent; source: art; maskEnabled: true; maskSource: artMask; visible: art.status === Image.Ready }
            Item { id: artMask; anchors.fill: parent; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: 18 } }
            Rectangle { anchors.fill: parent; radius: 18; visible: art.status !== Image.Ready
                gradient: Gradient { GradientStop { position: 0; color: mp.surfaceHi } GradientStop { position: 1; color: mp.panel } }
                Kirigami.Icon { anchors.centerIn: parent; width: 54; height: 54; source: "spotify-client"; fallback: "audio-x-generic" } }
            transform: Rotation { id: flipRot; origin.x: 66; origin.y: 66; axis.x: 0; axis.y: 1; axis.z: 0; angle: 0 }
            Connections { target: media; function onTitleChanged() { flipAnim.restart(); } }
            SequentialAnimation { id: flipAnim
                NumberAnimation { target: flipRot; property: "angle"; from: 0; to: 90; duration: 180; easing.type: Easing.InQuad }
                NumberAnimation { target: flipRot; property: "angle"; from: -90; to: 0; duration: 260; easing.type: Easing.OutBack } }
        }

        ColumnLayout {
            anchors { left: cover.right; leftMargin: 18; right: parent.right; rightMargin: 6; top: parent.top; topMargin: 10 }
            spacing: 1
            Row {
                spacing: 6
                Rectangle { width: 7; height: 7; radius: 3.5; anchors.verticalCenter: parent.verticalCenter
                    color: media.playing ? mp.tx("#62E6C8") : mp.textFaint
                    SequentialAnimation on opacity { running: media.playing && !occ.covered; loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 } } }
                Text { text: media.playing ? "СЕЙЧАС ИГРАЕТ" : (media.present ? "ПАУЗА" : "SPOTIFY")
                       color: mp.textFaint; font.family: mp.font; font.pixelSize: 9; font.weight: Font.Bold; font.letterSpacing: 1.6 }
            }
            Text { Layout.fillWidth: true; Layout.topMargin: 4; text: media.title || "Тишина"; color: mp.text; elide: Text.ElideRight
                   font.family: mp.fontDisplay; font.pixelSize: 20; font.weight: Font.DemiBold }
            Text { Layout.fillWidth: true; text: media.artist || "Запусти Spotify"; color: mp.accentHi; elide: Text.ElideRight
                   font.family: mp.font; font.pixelSize: 13 }
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: 18; Layout.topMargin: 8
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.09) }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter; height: 4; radius: 2
                    width: parent.width * (sa.pressed ? sa.preview : media.progress)
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: mp.accent2 } GradientStop { position: 1; color: mp.accentHi } }
                }
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: "white"
                    x: parent.width * (sa.pressed ? sa.preview : media.progress) - 6
                    scale: sa.containsMouse || sa.pressed ? 1 : 0.6; Behavior on scale { NumberAnimation { duration: 120 } } }
                MouseArea { id: sa; anchors.fill: parent; hoverEnabled: true; property real preview: 0
                    onPressed: m => { preview = Math.max(0, Math.min(1, m.x / width)); }
                    onPositionChanged: m => { if (pressed) preview = Math.max(0, Math.min(1, m.x / width)); }
                    onReleased: media.seek(preview) }
            }
            RowLayout {
                Layout.fillWidth: true
                Text { text: media.clock(media.position); color: mp.textDim; font.family: mp.font; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                Text { text: "-" + media.clock(Math.max(0, media.length - media.position)); color: mp.textDim; font.family: mp.font; font.pixelSize: 10 }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 2
                spacing: 12
                Btn { icon: "media-skip-backward"; onClicked: media.previous() }
                Btn { icon: media.playing ? "media-playback-pause" : "media-playback-start"; primary: true; onClicked: media.toggle() }
                Btn { icon: "media-skip-forward"; onClicked: media.next() }
                Btn { icon: "window-new"; onClicked: media.raise() }
            }
        }

        // spectrum with falling peak caps
        Item {
            id: spec
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 6; rightMargin: 6 }
            height: 70
            readonly property int n: 40
            property var peaks: []
            Timer {
                interval: 33; running: media.playing && !occ.covered; repeat: true
                onTriggered: {
                    var p = spec.peaks.length === spec.n ? spec.peaks : new Array(spec.n).fill(0);
                    for (var i = 0; i < spec.n; i++) {
                        var v = Math.min(1, pulse.at(Math.pow(i / (spec.n - 1), 0.7)) * 1.2);
                        p[i] = v > p[i] ? v : Math.max(0, p[i] - 0.012);
                    }
                    spec.peaks = p.slice();
                }
            }
            Row {
                anchors.fill: parent
                spacing: 3
                Repeater {
                    model: spec.n
                    Item {
                        width: (spec.width - 3 * (spec.n - 1)) / spec.n; height: spec.height
                        readonly property real lv: media.playing ? Math.min(1, pulse.at(Math.pow(index / (spec.n - 1), 0.7)) * 1.2) : 0.04
                        Rectangle {
                            anchors.bottom: parent.bottom; width: parent.width; radius: 2
                            height: Math.max(3, parent.lv * (spec.height - 6))
                            gradient: Gradient {
                                GradientStop { position: 0; color: mp.accentHi }
                                GradientStop { position: 1; color: mp.tint(0.24, 0.42, 1, 0.35) }
                            }
                        }
                        Rectangle {
                            width: parent.width; height: 2; radius: 1; color: "white"; opacity: 0.8
                            visible: media.playing
                            y: spec.height - 4 - (spec.peaks[index] || 0) * (spec.height - 6)
                        }
                    }
                }
            }
        }
    }
}
