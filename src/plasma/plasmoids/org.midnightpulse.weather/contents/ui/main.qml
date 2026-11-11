// Midnight Pulse · Clock & Weather — large desktop clock with live animated weather.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5
import org.kde.kirigami as Kirigami
import "common" as Common

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: fullRepresentation
    Common.Palette { id: mp; paused: occ.covered }
    Common.Occlusion { id: occ }

    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.now = new Date() }

    property var wx: ({ city: "", temp: "—", desc: "Загрузка…", kind: "clear", day: false, hours: [] })
    readonly property string script: Qt.resolvedUrl("../code/weather.py").toString().replace("file://", "")
    P5.DataSource {
        id: exec; engine: "executable"
        onNewData: (src, data) => {
            try { var v = JSON.parse(data.stdout); if (v.city) root.wx = v; } catch (e) {}
            disconnectSource(src);
        }
    }
    function refresh() { exec.connectSource("python3 '" + script + "' '" + (Plasmoid.configuration.city || "London").replace(/'/g, "") + "'"); }
    Timer { interval: 15 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
    Connections { target: Plasmoid.configuration; function onCityChanged() { root.refresh(); } }

    fullRepresentation: Item {
        id: card
        Layout.minimumWidth: 400; Layout.minimumHeight: 250
        Layout.preferredWidth: 430; Layout.preferredHeight: 262
        property real appear: 0
        Component.onCompleted: appearAnim.start()
        NumberAnimation { id: appearAnim; target: card; property: "appear"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }

        // ---- clock ----
        Column {
            id: clock
            x: 6; y: 0
            opacity: card.appear
            transform: Translate { x: (1 - card.appear) * -24 }
            Row {
                spacing: 0
                Text {
                    text: Qt.formatTime(root.now, "hh")
                    color: mp.text; font.family: mp.fontDisplay; font.pixelSize: 84; font.weight: Font.Thin
                }
                Text {
                    text: ":"; color: mp.accent; font.family: mp.fontDisplay; font.pixelSize: 84; font.weight: Font.Thin
                    opacity: root.now.getSeconds() % 2 ? 0.3 : 1
                    Behavior on opacity { enabled: !occ.covered; NumberAnimation { duration: 450 } }
                }
                Text {
                    text: Qt.formatTime(root.now, "mm")
                    font.family: mp.fontDisplay; font.pixelSize: 84; font.weight: Font.Thin
                    color: mp.accentHi
                }
            }
            Text {
                text: Qt.formatDate(root.now, "dddd, d MMMM")
                color: mp.textDim; font.family: mp.font; font.pixelSize: 14; font.capitalization: Font.Capitalize
                topPadding: -6
            }
            // seconds progress
            Item {
                width: 230; height: 10
                Rectangle { y: 5; width: parent.width; height: 2; radius: 1; color: Qt.rgba(1, 1, 1, 0.07) }
                Rectangle {
                    y: 5; height: 2; radius: 1
                    width: parent.width * root.now.getSeconds() / 59
                    Behavior on width { enabled: !occ.covered; NumberAnimation { duration: 950 } }
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: mp.accent2 } GradientStop { position: 1; color: mp.accentHi } }
                }
            }
        }

        // ---- current weather ----
        Item {
            id: now
            anchors.right: parent.right; anchors.rightMargin: 4
            y: 2; width: 150; height: 150
            opacity: card.appear
            transform: Translate { x: (1 - card.appear) * 24 }
            WeatherGlyph {
                id: glyph
                anchors.horizontalCenter: parent.horizontalCenter
                width: 92; height: 92
                kind: root.wx.kind || "clear"; day: root.wx.day === true; animated: !occ.covered
            }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 88
                Text { anchors.horizontalCenter: parent.horizontalCenter
                       text: root.wx.temp + "°"; color: mp.text; font.family: mp.fontDisplay; font.pixelSize: 30; font.weight: Font.Light }
                Text { anchors.horizontalCenter: parent.horizontalCenter
                       text: root.wx.desc + (root.wx.min !== undefined ? "  ·  " + root.wx.min + "°/" + root.wx.max + "°" : "")
                       color: mp.textDim; font.family: mp.font; font.pixelSize: 11 }
            }
        }

        // ---- details row ----
        Row {
            x: 8; y: 140
            spacing: 14
            opacity: card.appear
            Repeater {
                model: [
                    { i: "mark-location", t: root.wx.city || "—" },
                    { i: "temperature-normal", t: root.wx.feels !== undefined ? "ощущ. " + root.wx.feels + "°" : "" },
                    { i: "weather-windy", t: root.wx.wind !== undefined ? root.wx.wind + " км/ч" : "" },
                    { i: "raindrop", t: root.wx.humidity !== undefined ? root.wx.humidity + "%" : "" }
                ]
                Row {
                    required property var modelData
                    visible: modelData.t.length > 0
                    spacing: 5
                    Kirigami.Icon { width: 13; height: 13; source: parent.modelData.i; color: mp.accent; isMask: true; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: parent.modelData.t; color: mp.textDim; font.family: mp.font; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }

        // ---- hourly forecast ----
        Rectangle {
            id: hourly
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 84; radius: 16
            color: Qt.rgba(1, 1, 1, 0.035)
            border.color: mp.stroke
            Row {
                anchors.centerIn: parent
                Repeater {
                    model: root.wx.hours || []
                    Item {
                        id: hcell
                        required property var modelData
                        required property int index
                        width: (hourly.width - 12) / 6; height: 80
                        opacity: 0
                        Component.onCompleted: hAnim.start()
                        SequentialAnimation { id: hAnim
                            PauseAnimation { duration: 300 + hcell.index * 90 }
                            NumberAnimation { target: hcell; property: "opacity"; to: 1; duration: 400 } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 6; text: hcell.modelData.time
                               color: mp.textFaint; font.family: mp.font; font.pixelSize: 10 }
                        WeatherGlyph { anchors.horizontalCenter: parent.horizontalCenter; y: 20; width: 36; height: 36
                                       kind: hcell.modelData.kind; day: hcell.modelData.day; animated: !occ.covered }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; y: 58; text: hcell.modelData.temp + "°"
                               color: mp.text; font.family: mp.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                }
            }
        }

        MouseArea { anchors.fill: now; onClicked: root.refresh(); cursorShape: Qt.PointingHandCursor }
    }
}
