// Live spectrum under the lock-screen media controls.
import QtQuick
Item {
    implicitHeight: 46
    PulseSource { id: pulse; active: true }
    SpectrumBars {
        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
        source: pulse; count: 36; spacing: 3; mirrored: true
        opacity: pulse.hasSignal ? 0.9 : 0.35
        Behavior on opacity { NumberAnimation { duration: 600 } }
    }
}
