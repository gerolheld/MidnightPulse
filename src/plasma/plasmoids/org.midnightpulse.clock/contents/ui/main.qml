// Midnight Pulse · Clock — flip-digit panel clock with an animated calendar popup.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "common" as Common

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: compactRepresentation
    toolTipMainText: Qt.formatDate(now, "dddd, d MMMM yyyy")
    toolTipSubText: ""
    Common.Palette { id: mp; paused: occ.covered }
    Common.Occlusion { id: occ }
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    component FlipDigit: Item {
        id: fd
        property string value: "0"
        property string shown: value
        width: 8.4; height: 18; clip: true
        Text { id: cur; y: 0; text: fd.shown; color: mp.text; font.family: mp.font; font.pixelSize: 14; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
        Text { id: nxt; y: 18; text: fd.value; color: mp.accentHi; font: cur.font }
        onValueChanged: if (value !== shown) flip.restart()
        SequentialAnimation {
            id: flip
            ParallelAnimation {
                NumberAnimation { target: cur; property: "y"; to: -18; duration: 380; easing.type: Easing.InOutCubic }
                NumberAnimation { target: nxt; property: "y"; to: 0; duration: 380; easing.type: Easing.InOutCubic }
            }
            ScriptAction { script: { fd.shown = fd.value; cur.y = 0; nxt.y = 18; } }
        }
    }

    compactRepresentation: Item {
        Layout.minimumWidth: row.implicitWidth + 22; Layout.preferredWidth: Layout.minimumWidth; Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true
        Rectangle {
            anchors.centerIn: parent; width: parent.width; height: 28; radius: 14
            color: ma.containsMouse || root.expanded ? mp.tint(0.12, 0.69, 0.92, 0.16) : "transparent"
            border.color: root.expanded ? mp.strokeHi : "transparent"
            Behavior on color { ColorAnimation { duration: mp.fast } }
        }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Row {
                anchors.verticalCenter: parent.verticalCenter
                readonly property string hh: Qt.formatTime(root.now, "hh")
                readonly property string mm: Qt.formatTime(root.now, "mm")
                FlipDigit { value: parent.hh.charAt(0) }
                FlipDigit { value: parent.hh.charAt(1) }
                Text { text: ":"; color: mp.accent; font.family: mp.font; font.pixelSize: 14; font.weight: Font.Bold
                       opacity: root.now.getSeconds() % 2 ? 0.35 : 1; Behavior on opacity { NumberAnimation { duration: 400 } } }
                FlipDigit { value: parent.mm.charAt(0) }
                FlipDigit { value: parent.mm.charAt(1) }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.now, "ddd, d MMM")
                color: mp.textDim; font.family: mp.font; font.pixelSize: 11
            }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: root.expanded = !root.expanded }
    }

    fullRepresentation: Item {
        id: cal
        Layout.minimumWidth: 320; Layout.maximumWidth: 320
        Layout.minimumHeight: 360; Layout.maximumHeight: 360
        property int year: root.now.getFullYear()
        property int month: root.now.getMonth()
        property int dir: 0
        function shift(d) { dir = d; var m = month + d; year += Math.floor(m / 12); month = (m % 12 + 12) % 12; swap.restart(); }
        Connections { target: root; function onExpandedChanged() { if (root.expanded) { cal.year = root.now.getFullYear(); cal.month = root.now.getMonth(); } } }

        Column {
            x: 8; y: 6; spacing: 0
            Text { text: Qt.formatTime(root.now, "hh:mm"); color: mp.text; font.family: mp.fontDisplay; font.pixelSize: 46; font.weight: Font.Light }
            Text { text: Qt.formatDate(root.now, "dddd, d MMMM"); color: mp.accentHi; font.family: mp.font; font.pixelSize: 13 }
        }
        RowLayout {
            x: 8; y: 92; width: parent.width - 16
            Text { text: Qt.locale().standaloneMonthName(cal.month, Locale.LongFormat) + " " + cal.year; color: mp.text; font.family: mp.font; font.pixelSize: 14; font.weight: Font.DemiBold; font.capitalization: Font.Capitalize }
            Item { Layout.fillWidth: true }
            Repeater {
                model: [{ i: "go-previous", d: -1 }, { i: "go-next", d: 1 }]
                Rectangle {
                    required property var modelData
                    width: 26; height: 26; radius: 13; color: na.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    Kirigami.Icon { anchors.centerIn: parent; width: 14; height: 14; source: parent.modelData.i; color: mp.text; isMask: true }
                    MouseArea { id: na; anchors.fill: parent; hoverEnabled: true; onClicked: cal.shift(parent.modelData.d) }
                }
            }
        }
        Row {
            x: 8; y: 128
            Repeater { model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                Text { width: 43.4; horizontalAlignment: Text.AlignHCenter; text: modelData; color: index > 4 ? mp.accent : mp.textFaint; font.family: mp.font; font.pixelSize: 10; font.weight: Font.DemiBold } }
        }
        Grid {
            id: grid
            x: 8; y: 150; columns: 7
            opacity: 1
            SequentialAnimation {
                id: swap
                ParallelAnimation {
                    NumberAnimation { target: grid; property: "opacity"; from: 0; to: 1; duration: 260 }
                    NumberAnimation { target: grid; property: "x"; from: 8 + cal.dir * 30; to: 8; duration: 320; easing.type: Easing.OutCubic }
                }
            }
            Repeater {
                model: 42
                Item {
                    readonly property var first: new Date(cal.year, cal.month, 1)
                    readonly property int offset: (first.getDay() + 6) % 7
                    readonly property var day: new Date(cal.year, cal.month, 1 + index - offset)
                    readonly property bool inMonth: day.getMonth() === cal.month
                    readonly property bool today: day.toDateString() === root.now.toDateString()
                    width: 43.4; height: 34
                    Rectangle {
                        anchors.centerIn: parent; width: 30; height: 30; radius: 15
                        color: parent.today ? mp.accent : (da.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                        SequentialAnimation on scale { running: today; loops: Animation.Infinite
                            NumberAnimation { to: 1.08; duration: 1200; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine } }
                    }
                    Text { anchors.centerIn: parent; text: parent.day.getDate()
                        color: parent.today ? mp.bg : (parent.inMonth ? mp.text : mp.textFaint)
                        font.family: mp.font; font.pixelSize: 12; font.weight: parent.today ? Font.Bold : Font.Normal }
                    MouseArea { id: da; anchors.fill: parent; hoverEnabled: true }
                }
            }
        }
    }
}
