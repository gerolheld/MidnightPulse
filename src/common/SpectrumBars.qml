// Live equalizer bars fed by PulseSource. Mirrored = bass in the centre.
import QtQuick
import "." as MP
Item {
    id: bars
    property var source
    property int count: 16
    property real spacing: 2
    property bool mirrored: false
    property bool rounded: true
    property real minLevel: 0.08
    property real gain: 1.15
    MP.Palette { id: mp; paused: bars.paused }
    property color colorLow: mp.accent2
    property color colorHigh: mp.accentHi
    property bool idle: !source || !source.hasSignal
    property bool paused: false
    property bool centered: false     // grow from the vertical centre (island style)
    Row {
        anchors.fill: parent
        spacing: bars.spacing
        Repeater {
            model: bars.count
            Item {
                width: (bars.width - bars.spacing * (bars.count - 1)) / bars.count
                height: bars.height
                readonly property real t: bars.mirrored ? Math.abs(index / Math.max(1, bars.count - 1) * 2 - 1) : index / Math.max(1, bars.count - 1)
                property real idlePhase: 0
                SequentialAnimation on idlePhase {
                    running: bars.idle && bars.visible && !bars.paused
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 1; duration: 1100 + index * 37; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 1; to: 0; duration: 1100 + index * 37; easing.type: Easing.InOutSine }
                }
                readonly property real level: bars.idle ? bars.minLevel + idlePhase * 0.12
                                              : Math.max(bars.minLevel, Math.min(1, bars.source.at(Math.pow(t, 0.7)) * bars.gain))
                Rectangle {
                    anchors.bottom: bars.centered ? undefined : parent.bottom
                    anchors.verticalCenter: bars.centered ? parent.verticalCenter : undefined
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: Math.max(width, parent.height * parent.level)
                    radius: bars.rounded ? width / 2 : 1
                    gradient: Gradient {
                        GradientStop { position: 0; color: bars.colorHigh }
                        GradientStop { position: 1; color: bars.colorLow }
                    }
                    opacity: 0.55 + parent.level * 0.45
                }
            }
        }
    }
}
