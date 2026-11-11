// Fully animated weather glyph drawn in QML: sun / moon / clouds / rain / snow / storm / fog.
import QtQuick

Item {
    id: g
    property string kind: "clear"     // clear | partly | cloudy | fog | rain | snow | storm
    property bool day: true
    property bool animated: true
    width: 96; height: 96
    readonly property real u: width / 96
    readonly property bool hasCloud: kind !== "clear"
    readonly property bool hasSky: kind === "clear" || kind === "partly"

    // ---- sun ----
    Item {
        id: sun
        visible: g.hasSky && g.day
        width: 56 * g.u; height: width
        x: g.kind === "partly" ? 8 * g.u : (g.width - width) / 2
        y: g.kind === "partly" ? 6 * g.u : (g.height - height) / 2
        Item {
            anchors.fill: parent
            RotationAnimation on rotation { from: 0; to: 360; duration: 24000; loops: Animation.Infinite; running: g.animated && sun.visible }
            Repeater {
                model: 10
                Rectangle {
                    width: 3.5 * g.u; height: 9 * g.u; radius: width / 2
                    color: "#FFD27A"
                    x: sun.width / 2 - width / 2
                    y: 0
                    transformOrigin: Item.Center
                    transform: Rotation { origin.x: 1.75 * g.u; origin.y: sun.height / 2; angle: index * 36 }
                    SequentialAnimation on opacity { loops: Animation.Infinite; running: g.animated
                        PauseAnimation { duration: index * 120 }
                        NumberAnimation { to: 0.45; duration: 900 } NumberAnimation { to: 1; duration: 900 } }
                }
            }
        }
        Rectangle {
            anchors.centerIn: parent; width: parent.width * 0.52; height: width; radius: width / 2
            gradient: Gradient { GradientStop { position: 0; color: "#FFE9A8" } GradientStop { position: 1; color: "#FFB547" } }
            SequentialAnimation on scale { loops: Animation.Infinite; running: g.animated
                NumberAnimation { to: 1.06; duration: 1600; easing.type: Easing.InOutSine } NumberAnimation { to: 1; duration: 1600; easing.type: Easing.InOutSine } }
        }
    }

    // ---- moon + stars ----
    Item {
        id: moon
        visible: g.hasSky && !g.day
        width: 50 * g.u; height: width
        x: g.kind === "partly" ? 10 * g.u : (g.width - width) / 2
        y: g.kind === "partly" ? 6 * g.u : (g.height - height) / 2
        Rectangle { anchors.centerIn: parent; width: parent.width * 1.5; height: width; radius: width / 2
            gradient: Gradient { GradientStop { position: 0; color: "#225FD0FF" } GradientStop { position: 1; color: "#00000000" } }
            SequentialAnimation on opacity { loops: Animation.Infinite; running: g.animated
                NumberAnimation { to: 0.4; duration: 2200; easing.type: Easing.InOutSine } NumberAnimation { to: 1; duration: 2200; easing.type: Easing.InOutSine } } }
        Canvas {
            anchors.fill: parent
            onPaint: {
                var c = getContext("2d"), r = width / 2;
                c.reset();
                var gr = c.createLinearGradient(0, 0, width, height);
                gr.addColorStop(0, "#F4FAFF"); gr.addColorStop(1, "#9FD6FF");
                c.fillStyle = gr;
                c.beginPath(); c.arc(r, r, r * 0.86, 0, Math.PI * 2, false); c.fill();
                c.globalCompositeOperation = "destination-out";
                c.beginPath(); c.arc(r + r * 0.46, r - r * 0.30, r * 0.70, 0, Math.PI * 2, false); c.fill();
                c.globalCompositeOperation = "source-over";
            }
        }
        RotationAnimation on rotation { from: -8; to: 8; duration: 5000; loops: Animation.Infinite; running: g.animated; easing.type: Easing.InOutSine
            direction: RotationAnimation.Shortest }
    }
    Repeater {
        model: g.hasSky && !g.day ? 5 : 0
        Text {
            text: "✦"; color: "#CFEFFF"
            font.pixelSize: (6 + (index % 3) * 3) * g.u
            x: [64, 78, 70, 12, 84][index] * g.u
            y: [10, 30, 52, 70, 64][index] * g.u
            SequentialAnimation on opacity { loops: Animation.Infinite; running: g.animated
                PauseAnimation { duration: index * 430 }
                NumberAnimation { to: 0.15; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine } }
        }
    }

    // ---- cloud ----
    component Cloud: Item {
        id: cl
        property color tint: "#D7E6FF"
        property color shade: "#8EA7D6"
        width: 70 * g.u; height: 40 * g.u
        Rectangle { x: 6 * g.u; y: 18 * g.u; width: 58 * g.u; height: 20 * g.u; radius: height / 2
            gradient: Gradient { GradientStop { position: 0; color: cl.tint } GradientStop { position: 1; color: cl.shade } } }
        Rectangle { x: 12 * g.u; y: 8 * g.u; width: 26 * g.u; height: width; radius: width / 2
            gradient: Gradient { GradientStop { position: 0; color: cl.tint } GradientStop { position: 1; color: cl.shade } } }
        Rectangle { x: 28 * g.u; y: 0; width: 34 * g.u; height: width; radius: width / 2
            gradient: Gradient { GradientStop { position: 0; color: cl.tint } GradientStop { position: 1; color: cl.shade } } }
    }
    Cloud {
        id: backCloud
        visible: g.kind === "cloudy" || g.kind === "storm" || g.kind === "rain"
        tint: "#7F93C0"; shade: "#4A5D8C"
        opacity: 0.8
        scale: 0.8
        y: 12 * g.u
        SequentialAnimation on x { loops: Animation.Infinite; running: g.animated && backCloud.visible
            NumberAnimation { from: 30 * g.u; to: 18 * g.u; duration: 5200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 18 * g.u; to: 30 * g.u; duration: 5200; easing.type: Easing.InOutSine } }
    }
    Cloud {
        id: frontCloud
        visible: g.hasCloud
        tint: g.kind === "storm" ? "#9AA9CC" : "#E3EEFF"
        shade: g.kind === "storm" ? "#55648F" : "#93ACD9"
        y: (g.kind === "partly" ? 42 : 26) * g.u
        SequentialAnimation on x { loops: Animation.Infinite; running: g.animated && frontCloud.visible
            NumberAnimation { from: 14 * g.u; to: 24 * g.u; duration: 3800; easing.type: Easing.InOutSine }
            NumberAnimation { from: 24 * g.u; to: 14 * g.u; duration: 3800; easing.type: Easing.InOutSine } }
    }

    // ---- precipitation ----
    Repeater {
        model: g.kind === "rain" || g.kind === "storm" ? 7 : 0
        Rectangle {
            id: drop
            width: 2.2 * g.u; height: 10 * g.u; radius: 1
            color: "#7FD3FF"
            rotation: 15
            x: (26 + index * 7) * g.u
            property real p: 0
            y: (62 + p * 28) * g.u
            opacity: 1 - p
            NumberAnimation on p { from: 0; to: 1; duration: 700 + (index % 3) * 120; loops: Animation.Infinite; running: g.animated }
        }
    }
    Repeater {
        model: g.kind === "snow" ? 8 : 0
        Text {
            text: "❄"; color: "white"
            font.pixelSize: (7 + index % 3 * 2) * g.u
            property real p: (index * 0.13) % 1
            x: (24 + index * 7 + Math.sin(p * Math.PI * 2 + index) * 4) * g.u
            y: (60 + p * 32) * g.u
            opacity: 1 - p * 0.8
            rotation: p * 180
            NumberAnimation on p { from: 0; to: 1; duration: 2200 + index * 140; loops: Animation.Infinite; running: g.animated }
        }
    }
    // lightning
    Canvas {
        visible: g.kind === "storm"
        x: 40 * g.u; y: 58 * g.u; width: 20 * g.u; height: 32 * g.u
        onPaint: { var c = getContext("2d"); c.reset(); c.fillStyle = "#FFE27A"; c.beginPath();
            c.moveTo(width * 0.6, 0); c.lineTo(0, height * 0.58); c.lineTo(width * 0.45, height * 0.58);
            c.lineTo(width * 0.25, height); c.lineTo(width, height * 0.36); c.lineTo(width * 0.55, height * 0.36); c.closePath(); c.fill(); }
        opacity: 0
        SequentialAnimation on opacity { loops: Animation.Infinite; running: g.animated
            PauseAnimation { duration: 1800 } NumberAnimation { to: 1; duration: 60 } NumberAnimation { to: 0.2; duration: 80 }
            NumberAnimation { to: 1; duration: 60 } NumberAnimation { to: 0; duration: 400 } }
    }
    // fog
    Repeater {
        model: g.kind === "fog" ? 4 : 0
        Rectangle {
            height: 5 * g.u; radius: height / 2; color: "#B9CCEE"; opacity: 0.75
            width: (50 + (index % 2) * 14) * g.u
            y: (40 + index * 11) * g.u
            SequentialAnimation on x { loops: Animation.Infinite; running: g.animated
                NumberAnimation { from: (10 + index * 4) * g.u; to: (30 - index * 3) * g.u; duration: 2600 + index * 300; easing.type: Easing.InOutSine }
                NumberAnimation { from: (30 - index * 3) * g.u; to: (10 + index * 4) * g.u; duration: 2600 + index * 300; easing.type: Easing.InOutSine } }
        }
    }
}
