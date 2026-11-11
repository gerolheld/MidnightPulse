// Midnight Pulse palette — one place for every colour, size and timing.
//
// Colours are *live*: the theme is a hue transform of the original Midnight blue
// (accent #1EB0EA, hue 197°). midnight-pulse-audiod broadcasts the active theme on
// ws://127.0.0.1:47800/theme as { mode, preset, custom, speed, h, o, s }:
//   h — hue (°) the accent maps to, o — hue offset of the partner colour (#3D6BFF, +29° originally),
//   s — saturation multiplier.  mode "rgb" cycles h from the wall clock, so every widget stays in sync.
// Use tx("#hex") / tint(r, g, b, a) for any colour that should follow the theme.
import QtQuick
import QtWebSockets

Item {
    id: pal
    visible: false
    property bool paused: false          // owners pass occ.covered so RGB mode sleeps under games

    // ---- theme state (from the daemon) ----
    property string mode: "preset"       // preset | rgb | cover | custom
    property string preset: "midnight"
    property color custom: "#1EB0EA"
    property real speed: 1.0             // RGB: full cycles per minute
    property real targetH: 197
    property real targetO: 29
    property real targetS: 1.0

    // live transform parameters. They change together as ONE object so every colour binding
    // re-evaluates once per step (not three times), and transitions step at 25 fps instead of every
    // vsync — the whole desktop recolours without stutter.
    property var cur: ({ h: 197, o: 29, s: 1.0 })
    readonly property real h: cur.h
    readonly property real o: cur.o
    readonly property real s: cur.s

    property var _from: cur
    property var _to: cur
    property double _t0: 0
    readonly property int glideMs: 1400
    function glideTo(th, to, ts) {
        var d = ((th - cur.h) % 360 + 540) % 360 - 180;      // shortest way round the wheel
        _to = { h: cur.h + d, o: to, s: ts };
        if (paused) { step.stop(); cur = _to; return; }       // nobody is looking: jump
        _from = cur; _t0 = Date.now(); step.restart();
    }
    Timer {
        id: step
        interval: 40; repeat: true          // 25 fps is plenty for a colour glide
        onTriggered: {
            var k = Math.min(1, (Date.now() - pal._t0) / pal.glideMs);
            var e = k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2;   // easeInOutCubic
            var f = pal._from, t = pal._to;
            pal.cur = { h: f.h + (t.h - f.h) * e, o: f.o + (t.o - f.o) * e, s: f.s + (t.s - f.s) * e };
            if (k >= 1) stop();
        }
    }
    property bool _first: true
    function applyTargets() {
        if (mode === "rgb") return;
        if (_first) { _first = false; cur = { h: targetH, o: targetO, s: targetS }; return; }   // startup: no fade
        glideTo(targetH, targetO, targetS);
    }

    Timer {
        interval: 80; repeat: true
        running: pal.mode === "rgb" && !pal.paused
        onTriggered: pal.cur = { h: (Date.now() / 60000 * 360 * pal.speed) % 360, o: pal.targetO, s: pal.targetS }
    }

    readonly property var presets: [
        { id: "midnight", name: "Midnight", h: 197, o: 29, s: 1.0 },
        { id: "neon",     name: "Neon",     h: 278, o: 42, s: 1.0 },
        { id: "emerald",  name: "Emerald",  h: 158, o: 26, s: 0.92 },
        { id: "sunset",   name: "Sunset",   h: 24,  o: -36, s: 1.0 },
        { id: "crimson",  name: "Crimson",  h: 352, o: -26, s: 1.0 },
        { id: "arctic",   name: "Arctic",   h: 195, o: 14, s: 0.38 },
        { id: "synthwave", name: "Synthwave", h: 318, o: -62, s: 1.0 },
        { id: "ocean", name: "Ocean", h: 182, o: 38, s: 0.95 },
        { id: "aurora", name: "Aurora", h: 145, o: 115, s: 0.95 },
        { id: "sakura", name: "Sakura", h: 338, o: 18, s: 0.55 },
        { id: "amber", name: "Amber", h: 40, o: -16, s: 1.0 },
        { id: "lime", name: "Lime", h: 92, o: 38, s: 0.95 },
        { id: "lavender", name: "Lavender", h: 262, o: 22, s: 0.5 },
        { id: "cyber", name: "Cyber", h: 52, o: 110, s: 1.0 },
        { id: "graphite", name: "Graphite", h: 215, o: 10, s: 0.12 },
        { id: "mint", name: "Mint", h: 165, o: 30, s: 0.55 },
        { id: "inferno", name: "Inferno", h: 8, o: 34, s: 1.0 },
        { id: "peach", name: "Peach", h: 18, o: 22, s: 0.5 }
    ]

    WebSocket {
        id: ws
        url: "ws://127.0.0.1:47800/theme"
        active: true
        onTextMessageReceived: function (message) {
            var m; try { m = JSON.parse(message); } catch (e) { return; }
            if (m.t !== "theme") return;
            pal.mode = m.mode; pal.preset = m.preset || ""; pal.speed = m.speed || 1;
            if (m.custom) pal.custom = m.custom;
            pal.targetO = m.o; pal.targetS = m.s; pal.targetH = m.h;
            pal.applyTargets();
        }
        onStatusChanged: if (ws.status === WebSocket.Error || ws.status === WebSocket.Closed) retry.start()
    }
    Timer { id: retry; interval: 3000; onTriggered: { ws.active = false; ws.active = true; } }

    // Ask the daemon to change the theme; e.g. set({ mode: "preset", preset: "neon" }).
    function set(obj) {
        obj.t = "set";
        if (ws.status === WebSocket.Open) ws.sendTextMessage(JSON.stringify(obj));
    }

    // ---- the transform ----
    // HSV of each literal colour is computed once and cached; per step only Qt.hsva() runs.
    property var _cache: ({})
    function _base(key, col) {
        var e = _cache[key];
        if (e) return e;
        var hh = col.hsvHue;
        e = { r: col.r, g: col.g, b: col.b, a: col.a, h: hh, sat: col.hsvSaturation, v: col.hsvValue,
              rel: hh < 0 ? 999 : ((hh * 360 - 197) % 360 + 540) % 360 - 180 };
        _cache[key] = e;
        return e;
    }
    function _apply(e, a) {
        var c = pal.cur;
        if (Math.abs(e.rel) > 75) return Qt.rgba(e.r, e.g, e.b, a);        // reds/greens/yellows/greys stay
        var nh = (((c.h + e.rel * c.o / 29) % 360) + 360) % 360 / 360;
        return Qt.hsva(nh, Math.min(1, e.sat * c.s), e.v, a);
    }
    function tx(c, alpha) {
        var key = "" + c;
        var e = _cache[key] || _base(key, Qt.lighter(c, 1.0));
        return _apply(e, alpha === undefined ? e.a : alpha);
    }
    function tint(r, g, b, a) {
        var key = r + "," + g + "," + b;
        var e = _cache[key] || _base(key, Qt.rgba(r, g, b, 1));
        return _apply(e, a === undefined ? 1 : a);
    }
    function css(c) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + c.a.toFixed(3) + ")"; }
    // swatch colour of a preset (for pickers)
    function presetColor(p) {
        var nh = ((p.h % 360) + 360) % 360 / 360;
        return Qt.hsva(nh, Math.min(1, 0.87 * p.s), 0.92, 1);
    }

    readonly property color bg: tx("#070B18")
    readonly property color panel: tx("#0D1630")
    readonly property color surface: tx("#111D3D")
    readonly property color surfaceHi: tx("#1A2A55")
    readonly property color accent: tx("#1EB0EA")
    readonly property color accentHi: tx("#5FD0FF")
    readonly property color accent2: tx("#3D6BFF")
    readonly property color violet: tx("#7B6BFF")
    readonly property color text: tx("#DCE8FF")
    readonly property color textDim: tx("#8FA3C8")
    readonly property color textFaint: tx("#5B6E94")
    readonly property color glass: tint(13/255, 22/255, 48/255, 0.62)
    readonly property color glassHi: tint(26/255, 42/255, 85/255, 0.55)
    readonly property color stroke: tint(120/255, 190/255, 255/255, 0.18)
    readonly property color strokeHi: tint(95/255, 208/255, 255/255, 0.55)
    readonly property string font: "Inter"
    readonly property string fontDisplay: "Inter Display"
    readonly property int fast: 160
    readonly property int normal: 280
    readonly property int slow: 520
}
