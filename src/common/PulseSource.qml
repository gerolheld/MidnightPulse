// Midnight Pulse: shared client for midnight-pulse-audiod (ws://127.0.0.1:47800).
// Exposes smoothed spectrum levels (0..1), bass/energy envelopes and a beat() signal.
import QtQuick
import QtWebSockets

Item {
    id: src
    visible: false
    property bool active: true
    property int bars: 64
    property var levels: []          // smoothed, 0..1
    property real bass: 0            // smoothed low-end energy, 0..1
    property real energy: 0          // smoothed overall loudness, 0..1
    property real beatPulse: 0       // 1 on beat, decays to 0
    property string source: "none"   // "spotify" | "monitor" | "none"
    readonly property bool connected: ws.status === WebSocket.Open
    readonly property bool hasSignal: energy > 0.015
    signal beat()

    property var _raw: []

    WebSocket {
        id: ws
        url: "ws://127.0.0.1:47800"
        active: false          // driven imperatively by sync(); a binding here gets clobbered by reconnects
        onTextMessageReceived: function (message) {
            var m;
            try { m = JSON.parse(message); } catch (e) { return; }
            if (m.t === "status") { src.source = m.source; src.bars = m.bars; return; }
            if (m.t !== "f") return;
            var raw = m.l, out = src._raw.length === raw.length ? src._raw : new Array(raw.length).fill(0);
            for (var i = 0; i < raw.length; i++) {
                var v = raw[i] / 255, o = out[i];
                out[i] = o + (v - o) * (v > o ? 0.6 : 0.16);
            }
            src._raw = out;
            src.levels = out.slice();
            src.bass += (m.b - src.bass) * (m.b > src.bass ? 0.55 : 0.12);
            src.energy += (m.e - src.energy) * (m.e > src.energy ? 0.4 : 0.08);
            if (m.k === 1) { decay.restart(); src.beat(); }
        }
        onStatusChanged: if ((ws.status === WebSocket.Error || ws.status === WebSocket.Closed) && src.active) reconnect.start()
    }
    // (re)open the socket whenever we should be listening — e.g. right after leaving a fullscreen game
    function sync() {
        if (src.active) { if (ws.status !== WebSocket.Open && ws.status !== WebSocket.Connecting) { ws.active = false; ws.active = true; } }
        else { reconnect.stop(); ws.active = false; }
    }
    Component.onCompleted: sync()
    Timer { id: reconnect; interval: 2500; onTriggered: src.sync() }
    // safety net: if we should be live but the socket is down, retry
    Timer { interval: 5000; repeat: true; running: src.active; onTriggered: if (ws.status !== WebSocket.Open) src.sync() }
    NumberAnimation { id: decay; target: src; property: "beatPulse"; from: 1; to: 0; duration: 480; easing.type: Easing.OutCubic }
    onActiveChanged: { if (!active) { levels = []; _raw = []; bass = 0; energy = 0; } sync(); }

    // Sample the spectrum at fractional position t (0 = bass, 1 = treble).
    function at(t) {
        var l = levels, n = l.length;
        if (!n) return 0;
        var f = Math.max(0, Math.min(1, t)) * (n - 1), a = Math.floor(f), b = Math.min(a + 1, n - 1), u = f - a;
        return l[a] * (1 - u) + l[b] * u;
    }
}
