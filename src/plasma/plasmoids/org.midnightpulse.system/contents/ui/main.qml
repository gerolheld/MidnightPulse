// Midnight Pulse · System — animated ring gauges, temperatures and a live network graph.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksysguard.sensors as Sensors
import "common" as Common

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground | PlasmaCore.Types.ConfigurableBackground
    preferredRepresentation: fullRepresentation
    Common.Palette { id: mp; paused: occ.covered }
    Common.Occlusion { id: occ }

    Sensors.Sensor { id: cpu; sensorId: "cpu/all/usage"; updateRateLimit: 1000 }
    Sensors.Sensor { id: cpuT; sensorId: "cpu/all/averageTemperature"; updateRateLimit: 2000 }
    Sensors.Sensor { id: cpuF; sensorId: "cpu/all/averageFrequency"; updateRateLimit: 2000 }
    Sensors.Sensor { id: gpu; sensorId: "gpu/all/usage"; updateRateLimit: 1000 }
    Sensors.Sensor { id: gpuT; sensorId: "gpu/gpu0/temperature"; updateRateLimit: 2000 }
    Sensors.Sensor { id: vram; sensorId: "gpu/all/usedVram"; updateRateLimit: 2000 }
    Sensors.Sensor { id: vramT; sensorId: "gpu/all/totalVram"; updateRateLimit: 10000 }
    Sensors.Sensor { id: ram; sensorId: "memory/physical/usedPercent"; updateRateLimit: 1000 }
    Sensors.Sensor { id: ramU; sensorId: "memory/physical/used"; updateRateLimit: 2000 }
    Sensors.Sensor { id: ramTot; sensorId: "memory/physical/total"; updateRateLimit: 10000 }
    Sensors.Sensor { id: down; sensorId: "network/all/download"; updateRateLimit: 1000 }
    Sensors.Sensor { id: up; sensorId: "network/all/upload"; updateRateLimit: 1000 }

    function gib(b) { return (Number(b) / 1073741824).toFixed(1); }
    function rate(b) { b = Number(b) || 0; return b > 1048576 ? (b / 1048576).toFixed(1) + " МБ/с" : (b / 1024).toFixed(0) + " КБ/с"; }

    component Ring: Item {
        id: ring
        property real value: 0          // 0..100
        property string label
        property string sub
        property color c1: mp.accent2
        property color c2: mp.accentHi
        width: 108; height: 136
        property real shown: 0
        Behavior on shown { enabled: !occ.covered; NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
        onValueChanged: shown = Math.max(0, Math.min(100, value))
        readonly property bool hot: shown > 85
        Item {
            id: dial
            width: 96; height: 96
            anchors.horizontalCenter: parent.horizontalCenter
            // rotating dashed outer track
            Shape {
                anchors.fill: parent
                RotationAnimation on rotation { from: 0; to: 360; duration: 30000 - ring.shown * 200; loops: Animation.Infinite; running: !occ.covered }
                ShapePath {
                    strokeColor: mp.tint(0.47, 0.75, 1, 0.20); strokeWidth: 1.5; fillColor: "transparent"
                    strokeStyle: ShapePath.DashLine; dashPattern: [2, 5]
                    PathAngleArc { centerX: 48; centerY: 48; radiusX: 46; radiusY: 46; startAngle: 0; sweepAngle: 360 }
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.rgba(1, 1, 1, 0.07); strokeWidth: 7; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 48; centerY: 48; radiusX: 38; radiusY: 38; startAngle: 135; sweepAngle: 270 }
                }
                ShapePath {
                    strokeWidth: 7; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    strokeColor: ring.hot ? "#FF6E96" : ring.c2
                    PathAngleArc { centerX: 48; centerY: 48; radiusX: 38; radiusY: 38; startAngle: 135; sweepAngle: Math.max(0.5, 270 * ring.shown / 100) }
                }
            }
            // glowing tip
            Rectangle {
                readonly property real a: (135 + 270 * ring.shown / 100) * Math.PI / 180
                x: 48 + Math.cos(a) * 38 - 5; y: 48 + Math.sin(a) * 38 - 5
                width: 10; height: 10; radius: 5; color: "white"
                opacity: 0.9
                Rectangle { anchors.centerIn: parent; width: 22; height: 22; radius: 11; color: ring.hot ? "#55FF6E96" : "#555FD0FF"
                    SequentialAnimation on scale { loops: Animation.Infinite; running: !occ.covered
                        NumberAnimation { to: 1.4; duration: 900; easing.type: Easing.InOutSine } NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine } } }
            }
            Column {
                anchors.centerIn: parent
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(ring.shown) + "%"
                       color: mp.text; font.family: mp.fontDisplay; font.pixelSize: 22; font.weight: Font.Light }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: ring.label
                       color: mp.accentHi; font.family: mp.font; font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 1.5 }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; y: 104
            text: ring.sub; color: mp.textDim; font.family: mp.font; font.pixelSize: 11
        }
    }

    fullRepresentation: Item {
        id: card
        Layout.minimumWidth: 360; Layout.minimumHeight: 250
        Layout.preferredWidth: 372; Layout.preferredHeight: 258

        Row {
            id: rings
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4; spacing: 12
            Ring { label: "CPU"; value: Number(cpu.value) || 0
                   sub: (cpuT.value ? Math.round(cpuT.value) + "°C" : "") + (cpuF.value ? "  ·  " + (cpuF.value / 1000).toFixed(1) + " ГГц" : "") }
            Ring { label: "GPU"; value: Number(gpu.value) || 0; c1: mp.violet; c2: mp.tx("#8FA0FF")
                   sub: (gpuT.value ? Math.round(gpuT.value) + "°C" : "") + (vram.value ? "  ·  " + root.gib(vram.value) + " ГБ" : "") }
            Ring { label: "RAM"; value: Number(ram.value) || 0; c2: mp.tx("#62E6C8")
                   sub: ramU.value ? root.gib(ramU.value) + " / " + root.gib(ramTot.value) + " ГБ" : "" }
        }

        // network graph
        Rectangle {
            id: net
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 92; radius: 16
            color: Qt.rgba(1, 1, 1, 0.035); border.color: mp.stroke
            property var downHist: []
            property var upHist: []
            Timer {
                interval: 1000; running: !occ.covered; repeat: true
                onTriggered: {
                    var d = net.downHist.concat([Number(down.value) || 0]), u = net.upHist.concat([Number(up.value) || 0]);
                    if (d.length > 60) d.shift();
                    if (u.length > 60) u.shift();
                    net.downHist = d; net.upHist = u; graph.requestPaint();
                }
            }
            Row {
                x: 14; y: 10; spacing: 16
                Text { text: "↓ " + root.rate(down.value); color: mp.accentHi; font.family: mp.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                Text { text: "↑ " + root.rate(up.value); color: mp.tx("#A99BFF"); font.family: mp.font; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
            Canvas {
                id: graph
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: parent.top; topMargin: 30; margins: 10 }
                onPaint: {
                    var c = getContext("2d"), w = width, h = height;
                    c.reset();
                    var all = net.downHist.concat(net.upHist), max = 65536;
                    for (var i = 0; i < all.length; i++) max = Math.max(max, all[i]);
                    function line(hist, col, fillTop) {
                        if (hist.length < 2) return;
                        var step = w / 59, x0 = w - (hist.length - 1) * step;
                        c.beginPath();
                        c.moveTo(x0, h - hist[0] / max * h);
                        for (var j = 1; j < hist.length; j++) {
                            var px = x0 + (j - 1) * step, py = h - hist[j - 1] / max * h;
                            var nx = x0 + j * step, ny = h - hist[j] / max * h;
                            c.bezierCurveTo(px + step / 2, py, nx - step / 2, ny, nx, ny);
                        }
                        c.strokeStyle = col; c.lineWidth = 1.8; c.stroke();
                        c.lineTo(w, h); c.lineTo(x0, h); c.closePath();
                        var g = c.createLinearGradient(0, 0, 0, h);
                        g.addColorStop(0, fillTop); g.addColorStop(1, "rgba(0,0,0,0)");
                        c.fillStyle = g; c.fill();
                    }
                    line(net.upHist, mp.css(mp.tint(169/255, 155/255, 1, 0.9)), mp.css(mp.tint(123/255, 107/255, 1, 0.25)));
                    line(net.downHist, mp.css(mp.tint(95/255, 208/255, 1, 1)), mp.css(mp.tint(30/255, 176/255, 234/255, 0.30)));
                }
            }
        }
    }
}
