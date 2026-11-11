// Midnight Pulse lock-screen clock: thin display digits, blinking accent colon, soft glow.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.clock as PlasmaClock

ColumnLayout {
    id: root
    property Item shadow: null
    spacing: 0
    PlasmaClock.Clock { id: timeSource; trackSeconds: true }
    Row {
        Layout.alignment: Qt.AlignHCenter
        Text { text: Qt.formatTime(timeSource.dateTime, "hh"); color: "#DCE8FF"
               font.family: "Inter Display"; font.pixelSize: 132; font.weight: Font.Thin; font.features: { "tnum": 1 } }
        Text { text: ":"; color: "#1EB0EA"; font.family: "Inter Display"; font.pixelSize: 132; font.weight: Font.Thin
               opacity: timeSource.dateTime.getSeconds() % 2 ? 0.3 : 1; Behavior on opacity { NumberAnimation { duration: 500 } } }
        Text { text: Qt.formatTime(timeSource.dateTime, "mm"); color: "#5FD0FF"
               font.family: "Inter Display"; font.pixelSize: 132; font.weight: Font.Thin; font.features: { "tnum": 1 } }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        text: Qt.formatDate(timeSource.dateTime, "dddd · d MMMM").toUpperCase()
        color: "#8FA3C8"; font.family: "Inter"; font.pixelSize: 15; font.letterSpacing: 4; font.weight: Font.Medium
    }
}
