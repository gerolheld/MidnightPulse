// Midnight Pulse panel + desktop layout (Plasma scripting API).
var screenW = screenGeometry(0).width, screenH = screenGeometry(0).height;

// remove existing panels
var ps = panels();
for (var i = 0; i < ps.length; i++) ps[i].remove();

// --- top bar: nav | spacer | island | spacer | tray | clock
var top = new Panel("org.kde.panel");
top.location = "top";
top.height = 38;
top.floating = true;
top.lengthMode = "fill";
top.hiding = "none";
top.addWidget("org.midnightpulse.nav");
top.addWidget("org.kde.plasma.panelspacer");
top.addWidget("org.midnightpulse.island");
top.addWidget("org.kde.plasma.panelspacer");
var tray = top.addWidget("org.kde.plasma.systemtray");
tray.currentConfigGroup = ['General'];
tray.writeConfig('showAllItems', false); tray.writeConfig('scaleIconsToFit', false); tray.writeConfig('iconSpacing', 2);
tray.writeConfig('shownItems', 'org.kde.plasma.volume,org.kde.plasma.networkmanagement,org.kde.plasma.notifications');
tray.writeConfig('hiddenItems', 'org.kde.plasma.mediacontroller,org.kde.plasma.weather,org.kde.plasma.keyboardindicator,org.kde.plasma.manage-inputmethod,org.kde.kscreen,org.kde.plasma.devicenotifier,org.kde.kdeconnect,spotify-client,steam,Easy Effects,Cachy-Update,kded6,vesktop,vesktop_status_icon_1,org.kde.plasma.clipboard,org.kde.plasma.keyboardlayout,org.kde.plasma.brightness,org.kde.plasma.battery,org.kde.plasma.cameraindicator');
top.addWidget("org.midnightpulse.clock");

// --- dock
var dock = new Panel("org.kde.panel");
dock.location = "bottom";
dock.height = 72;
dock.floating = false;
dock.lengthMode = "fit";
dock.alignment = "center";
dock.hiding = "dodgewindows";   // maximised windows reach the bottom; dock slides back on hover
dock.addWidget("org.midnightpulse.dock");

// --- desktop widgets
var ds = desktops();
for (var d = 0; d < ds.length; d++) {
    var desk = ds[d];
    var ws = desk.widgets();
    for (var w = 0; w < ws.length; w++) {
        if (/lunarglass|azure|midnightpulse/.test(ws[w].type)) ws[w].remove();
    }
    desk.wallpaperPlugin = "org.midnightpulse.sky";
    desk.addWidget("org.midnightpulse.weather").geometry = new QRectF(24, 62, 440, 270);
    desk.addWidget("org.midnightpulse.system").geometry = new QRectF(screenW - 24 - 388, 62, 388, 274);
    desk.addWidget("org.midnightpulse.player").geometry = new QRectF(screenW - 24 - 448, screenH - 100 - 262, 448, 262);
}
print("Midnight Pulse layout applied");
