// Midnight Pulse splash: pulsing star with expanding rings over a twinkling sky.
import QtQuick

Rectangle {
    id: root
    color: "#070B18"
    property int stage
    onStageChanged: if (stage === 2) intro.start()

    // twinkling stars
    Repeater {
        model: 90
        Rectangle {
            readonly property real r: Math.random()
            x: Math.random() * root.width; y: Math.random() * root.height
            width: 1 + r * 2; height: width; radius: width / 2
            color: r > 0.8 ? "#9FDCFF" : "#DCE8FF"
            SequentialAnimation on opacity { loops: Animation.Infinite
                PauseAnimation { duration: Math.random() * 2000 }
                NumberAnimation { from: 0.1; to: 0.9; duration: 1200 + Math.random() * 1200; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.9; to: 0.1; duration: 1200 + Math.random() * 1200; easing.type: Easing.InOutSine } }
        }
    }
    // horizon glow
    Rectangle {
        anchors.bottom: parent.bottom; width: parent.width; height: parent.height * 0.5
        gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: "#1A1EB0EA" } }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        Item {
            id: core
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -30
            width: 120; height: 120
            Repeater {
                model: 3
                Rectangle {
                    anchors.centerIn: parent
                    width: 120; height: 120; radius: 60
                    color: "transparent"; border.width: 2; border.color: "#5FD0FF"
                    SequentialAnimation on scale { loops: Animation.Infinite
                        PauseAnimation { duration: index * 700 }
                        NumberAnimation { from: 0.4; to: 2.4; duration: 2100; easing.type: Easing.OutCubic } }
                    SequentialAnimation on opacity { loops: Animation.Infinite
                        PauseAnimation { duration: index * 700 }
                        NumberAnimation { from: 0.8; to: 0; duration: 2100; easing.type: Easing.OutCubic } }
                }
            }
            Image {
                anchors.centerIn: parent
                width: 84; height: 84
                source: "images/logo.svg"; sourceSize: Qt.size(168, 168)
                RotationAnimator on rotation { from: 0; to: 360; duration: 9000; loops: Animation.Infinite }
                SequentialAnimation on scale { loops: Animation.Infinite
                    NumberAnimation { to: 1.12; duration: 520; easing.type: Easing.OutQuad }
                    NumberAnimation { to: 1.0; duration: 880; easing.type: Easing.InOutSine } }
            }
        }
        Text {
            id: title
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: core.bottom; anchors.topMargin: 56
            text: "MIDNIGHT  PULSE"
            color: "#DCE8FF"; font.family: "Inter Display"; font.pixelSize: 22; font.weight: Font.Light
            font.letterSpacing: 2 + content.opacity * 8
        }
        // progress line
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: title.bottom; anchors.topMargin: 26
            width: 240; height: 3; radius: 1.5; color: "#1AFFFFFF"
            Rectangle {
                height: parent.height; radius: 1.5
                width: parent.width * Math.min(1, root.stage / 6)
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                gradient: Gradient { orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#3D6BFF" } GradientStop { position: 1; color: "#5FD0FF" } }
            }
        }
    }
    OpacityAnimator { id: intro; target: content; from: 0; to: 1; duration: 900; easing.type: Easing.InOutQuad }
}
