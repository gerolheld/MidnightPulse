// Midnight Pulse Sky — live wallpaper reacting to Spotify.
import QtQuick
import QtQuick.Particles
import QtQuick.Effects
import org.kde.plasma.plasmoid
import "common" as Common

WallpaperItem {
    id: root
    readonly property real intensity: root.configuration.Intensity === undefined ? 1.0 : root.configuration.Intensity
    readonly property bool spectrumOn: root.configuration.ShowSpectrum !== false
    readonly property bool particlesOn: root.configuration.ShowParticles !== false
    readonly property bool shootingOn: root.configuration.ShootingStars !== false
    readonly property bool lyricsOn: root.configuration.ShowLyrics !== false

    Common.Occlusion { id: occ }
    Common.Palette { id: mp; paused: occ.covered }
    readonly property bool live: !occ.covered
    Common.PulseSource { id: pulse; active: root.live }

    Rectangle { anchors.fill: parent; color: mp.tx("#070B18") }

    // --- Sky shader -------------------------------------------------------
    ShaderEffect {
        id: sky
        anchors.fill: parent
        property real time: 0
        property real bass: pulse.bass
        property real energy: pulse.energy
        property real beat: pulse.beatPulse
        property real aspect: width / Math.max(1, height)
        property real intensity: root.intensity
        property real themeH: mp.h
        property real themeO: mp.o
        property real themeS: mp.s
        fragmentShader: Qt.resolvedUrl("../shaders/sky.frag.qsb")
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity { NumberAnimation { duration: 1600; easing.type: Easing.OutCubic } }
    }
    // 40 fps is plenty for slow aurora/stars and halves the work compared to vsync
    Timer {
        interval: 25; repeat: true; running: root.live
        property double last: 0
        onTriggered: { var n = Date.now(); if (last) sky.time += Math.min(0.1, (n - last) / 1000); last = n; }
        onRunningChanged: last = 0
    }

    // --- Fireflies rising with the music ---------------------------------
    ParticleSystem { id: ps; running: root.particlesOn && root.live }
    ImageParticle {
        system: ps
        source: "../images/glow.svg"
        color: mp.tx("#5fd0ff")
        colorVariation: 0.15
        alpha: 0.75
        alphaVariation: 0.3
        entryEffect: ImageParticle.Fade
    }
    Emitter {
        system: ps
        enabled: root.particlesOn
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * 0.25
        emitRate: 6 + pulse.energy * 40 * root.intensity
        lifeSpan: 7000; lifeSpanVariation: 2500
        size: 6; sizeVariation: 6; endSize: 2
        velocity: AngleDirection { angle: 270; angleVariation: 25; magnitude: 22 + pulse.bass * 60; magnitudeVariation: 12 }
        acceleration: PointDirection { xVariation: 6; y: -2 }
    }
    Wander { system: ps; xVariance: 40; pace: 30 }

    // --- Shooting stars -----------------------------------------------------
    Component {
        id: shootingStar
        Item {
            id: s
            property real len: 180 + Math.random() * 160
            x: root.width * (0.15 + Math.random() * 0.8)
            y: root.height * (0.03 + Math.random() * 0.3)
            rotation: 155 + Math.random() * 20
            opacity: 0
            Rectangle {
                width: s.len; height: 2; radius: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#00ffffff" }
                    GradientStop { position: 0.85; color: mp.tx("#9fdcff") }
                    GradientStop { position: 1; color: "#ffffff" }
                }
            }
            Rectangle { x: s.len - 3; y: -2; width: 6; height: 6; radius: 3; color: "white" }
            ParallelAnimation {
                running: true
                NumberAnimation { target: s; property: "opacity"; from: 0; to: 1; duration: 140 }
                NumberAnimation {
                    target: s; property: "x"; duration: 900; easing.type: Easing.InQuad
                    to: s.x + Math.cos(s.rotation * Math.PI / 180) * 520
                }
                NumberAnimation {
                    target: s; property: "y"; duration: 900; easing.type: Easing.InQuad
                    to: s.y + Math.sin(s.rotation * Math.PI / 180) * 520
                }
                SequentialAnimation {
                    PauseAnimation { duration: 520 }
                    NumberAnimation { target: s; property: "opacity"; to: 0; duration: 380 }
                }
                onFinished: s.destroy()
            }
        }
    }
    property real lastShot: 0
    function shoot() {
        if (!shootingOn) return;
        var now = Date.now();
        if (now - lastShot < 1800) return;
        lastShot = now;
        shootingStar.createObject(root);
    }
    Connections {
        target: pulse
        function onBeat() { if (pulse.bass > 0.62 && Math.random() < 0.45) root.shoot(); }
    }
    Timer { interval: 9000; running: root.live; repeat: true; onTriggered: if (Math.random() < 0.6) root.shoot() }

    // --- Synced lyrics (LRCLIB) floating in the middle of the sky ------------
    Loader {
        active: root.lyricsOn
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.47
        width: Math.min(1100, parent.width * 0.56); height: 200
        sourceComponent: Lyrics { pal: mp; live: root.live }
    }

    // --- Glowing spectrum on the horizon (behind the dock), drawn by the GPU ----
    Item {
        id: horizon
        visible: root.spectrumOn && root.live
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: parent.height * 0.22
        opacity: pulse.hasSignal ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 900 } }
        readonly property int n: 110
        Item {
            id: barsSrc
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 40; brightness: 0.08 }
            Row {
                anchors.fill: parent
                Repeater {
                    model: horizon.n
                    Rectangle {
                        readonly property real t: Math.abs(index / (horizon.n - 1) * 2 - 1)
                        readonly property real env: 0.35 + 0.65 * Math.cos((index / (horizon.n - 1) - 0.5) * Math.PI)
                        width: horizon.width / horizon.n
                        height: Math.min(1, 0.06 + pulse.at(Math.pow(t, 0.55)) * root.intensity * 1.7) * horizon.height * 0.9 * env + 2
                        anchors.bottom: parent.bottom
                        gradient: Gradient {
                            GradientStop { position: 0; color: mp.tx("#9FE4FF") }
                            GradientStop { position: 0.25; color: mp.tx("#5FD0FF") }
                            GradientStop { position: 1; color: "#001E3A8A" }
                        }
                        opacity: 0.7
                    }
                }
            }
        }
    }
}
