// Midnight Pulse · Navigation — pulsing star launcher + animated workspace switcher.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.plasma5support as P5
import org.kde.coreaddons as KCoreAddons
import "common" as Common

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: compactRepresentation
    toolTipMainText: "Приложения"
    toolTipSubText: ""

    Common.Palette { id: mp; paused: occ.covered }
    Common.MediaSource { id: media }
    Common.Occlusion { id: occ; fullscreenOnly: true }
    Common.PulseSource { id: pulse; active: media.playing && !occ.covered }
    TaskManager.VirtualDesktopInfo { id: desktops }
    KCoreAddons.KUser { id: kuser }
    P5.DataSource { id: exec; engine: "executable"; onNewData: (s, d) => disconnectSource(s) }
    function run(cmd) { exec.connectSource(cmd); }

    // ---------------- app models ----------------
    Kicker.RootModel {
        id: allApps; appletInterface: root; flat: true; sorted: true
        showAllApps: true; showAllAppsCategorized: false; showRecentApps: false; showRecentDocs: false
        showRecentFolders: false; showPowerSession: false; showFavoritesPlaceholder: false
    }
    Kicker.RootModel {
        id: groups; appletInterface: root; flat: false; sorted: true
        showAllApps: false; showAllAppsCategorized: false; showRecentApps: false; showRecentDocs: false
        showRecentFolders: false; showPowerSession: false; showFavoritesPlaceholder: false
    }
    property string query: ""
    property int category: -2          // -2 favourites, -1 all, >=0 group row
    property var activeModel: null
    property int generation: 0         // bumps to replay the cascade animation
    ListModel { id: results; dynamicRoles: true }
    ListModel { id: categories; dynamicRoles: true }
    readonly property var favourites: [/zen browser|firefox/i, /vesktop|discord/i, /^spotify/i, /^steam$/i, /^dolphin$/i, /^konsole$/i,
        /visual studio|^code|antigravity/i, /^blender/i, /telegram/i, /^obs/i, /lm studio/i, /^kate$/i,
        /параметры системы|system settings/i, /^krita/i, /^gwenview$/i, /easy ?effects/i]

    function refreshCategories() {
        categories.clear();
        for (var i = 0; i < groups.count; i++) {
            var idx = groups.index(i, 0), label = String(groups.data(idx, Qt.DisplayRole) || "");
            if (label) categories.append({ label: label, row: i });
        }
    }
    function refresh() {
        activeModel = (query.length || category < 0) ? allApps.modelForRow(0) : groups.modelForRow(category);
        results.clear();
        if (!activeModel) return;
        var q = query.toLocaleLowerCase(), list = [];
        for (var i = 0; i < activeModel.count; i++) {
            var idx = activeModel.index(i, 0), label = String(activeModel.data(idx, Qt.DisplayRole) || "");
            if (q.length && label.toLocaleLowerCase().indexOf(q) < 0) continue;
            list.push({ label: label, appIcon: activeModel.data(idx, Qt.DecorationRole), sourceRow: i });
        }
        if (!q.length && category === -2) {
            var chosen = [];
            for (var k = 0; k < favourites.length; k++)
                for (var j = 0; j < list.length; j++)
                    if (favourites[k].test(list[j].label) && chosen.indexOf(list[j]) < 0) { chosen.push(list[j]); break; }
            list = chosen;
        }
        for (var n = 0; n < list.length; n++) results.append(list[n]);
        generation++;
    }
    function launch(row) { if (activeModel) activeModel.trigger(row, "", null); root.expanded = false; }
    onQueryChanged: refresh()
    onCategoryChanged: refresh()
    onExpandedChanged: if (root.expanded) { query = ""; category = -2; refreshCategories(); refresh(); focusTimer.restart(); }
    Timer { id: focusTimer; interval: 90; onTriggered: if (root.fullRepresentationItem) root.fullRepresentationItem.focusSearch() }

    // ---------------- panel part ----------------
    compactRepresentation: Item {
        id: bar
        readonly property int deskW: 28
        Layout.minimumWidth: implicitWidth; Layout.preferredWidth: implicitWidth; Layout.maximumWidth: implicitWidth
        Layout.fillHeight: true
        implicitWidth: 40 + 8 + pager.width + 2

        // launcher star
        Item {
            id: star
            width: 36; height: 30
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.fill: parent; radius: 15
                color: starArea.containsMouse || root.expanded ? mp.tint(0.12, 0.69, 0.92, 0.18) : "transparent"
                border.color: root.expanded ? mp.strokeHi : "transparent"
                Behavior on color { ColorAnimation { duration: mp.fast } }
            }
            Image {
                id: logoImg
                anchors.centerIn: parent
                width: 20; height: 20
                source: Qt.resolvedUrl("../images/logo.svg")
                sourceSize: Qt.size(64, 64)
                rotation: root.expanded ? 45 : 0
                scale: (starArea.pressed ? 0.85 : 1) * (1 + pulse.beatPulse * 0.18)
                Behavior on rotation { NumberAnimation { duration: mp.slow; easing.type: Easing.OutBack } }
                Behavior on scale { NumberAnimation { duration: 90 } }
                layer.enabled: true
                layer.effect: MultiEffect {
                    // recolour the blue logo for any other theme
                    colorization: Math.abs(((mp.h - 197) % 360 + 540) % 360 - 180) < 2 && Math.abs(mp.s - 1) < 0.02 ? 0 : 0.85
                    colorizationColor: mp.accentHi
                    shadowEnabled: true; shadowColor: mp.accent; shadowBlur: 0.8
                    shadowOpacity: 0.45 + pulse.beatPulse * 0.5 + glow.v * 0.3
                    shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                }
                QtObject { id: glow; property real v: 0
                    SequentialAnimation on v { loops: Animation.Infinite; running: !occ.covered
                        NumberAnimation { to: 1; duration: 1800; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0; duration: 1800; easing.type: Easing.InOutSine } } }
            }
            MouseArea { id: starArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.expanded = !root.expanded }
        }

        // workspace switcher with sliding indicator
        Rectangle {
            id: pager
            x: star.width + 8
            anchors.verticalCenter: parent.verticalCenter
            height: 26; radius: 13
            width: desktops.numberOfDesktops * bar.deskW + 6
            color: Qt.rgba(1, 1, 1, 0.04)
            border.color: mp.stroke
            readonly property int current: Math.max(0, desktops.desktopIds.indexOf(desktops.currentDesktop))
            Rectangle {
                id: indicator
                y: 3; height: parent.height - 6; radius: height / 2
                width: bar.deskW
                x: 3 + pager.current * bar.deskW
                Behavior on x { SpringAnimation { spring: 4; damping: 0.38 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: mp.accent2 }
                    GradientStop { position: 1; color: mp.accent }
                }
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: mp.accent; shadowBlur: 0.6; shadowOpacity: 0.7; shadowVerticalOffset: 0 }
            }
            Row {
                x: 3
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: desktops.numberOfDesktops
                    Item {
                        id: desk
                        required property int index
                        readonly property bool active: index === pager.current
                        width: bar.deskW; height: 20
                        Text {
                            anchors.centerIn: parent
                            text: desk.index + 1
                            color: desk.active ? "white" : (da.containsMouse ? mp.text : mp.textDim)
                            font.family: mp.font; font.pixelSize: 11; font.weight: desk.active ? Font.Bold : Font.Medium
                            scale: da.containsMouse && !desk.active ? 1.2 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Behavior on color { ColorAnimation { duration: 160 } }
                        }
                        MouseArea { id: da; anchors.fill: parent; hoverEnabled: true
                            onClicked: root.run("qdbus6 org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop " + (desk.index + 1)) }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.NoButton
                onWheel: w => root.run("qdbus6 org.kde.KWin /KWin org.kde.KWin." + (w.angleDelta.y > 0 ? "previousDesktop" : "nextDesktop"))
            }
        }
    }

    // ---------------- launcher popup ----------------
    fullRepresentation: Item {
        id: menu
        Layout.minimumWidth: 640; Layout.maximumWidth: 640
        Layout.minimumHeight: 520; Layout.maximumHeight: 520
        function focusSearch() { search.forceActiveFocus(Qt.PopupFocusReason); }
        Keys.onEscapePressed: { if (colorsOpen) colorsOpen = false; else root.expanded = false; }
        property bool colorsOpen: false
        Connections { target: root; function onExpandedChanged() { if (!root.expanded) menu.colorsOpen = false; } }

        // header: avatar + greeting
        RowLayout {
            id: header
            x: 6; y: 4; width: parent.width - 12; height: 52; spacing: 12
            Item {
                width: 42; height: 42
                Rectangle { anchors.fill: parent; radius: 21; gradient: Gradient {
                    GradientStop { position: 0; color: mp.accent } GradientStop { position: 1; color: mp.accent2 } } }
                Image { id: face; anchors.fill: parent; anchors.margins: 2; source: kuser.faceIconUrl; visible: false; fillMode: Image.PreserveAspectCrop }
                MultiEffect { anchors.fill: face; source: face; maskEnabled: true; maskSource: faceMask; visible: face.status === Image.Ready }
                Item { id: faceMask; anchors.fill: face; visible: false; layer.enabled: true; Rectangle { anchors.fill: parent; radius: width / 2 } }
                Text { anchors.centerIn: parent; visible: face.status !== Image.Ready; text: (kuser.loginName || "?").charAt(0).toUpperCase()
                       color: "white"; font.family: mp.font; font.pixelSize: 18; font.weight: Font.Bold }
            }
            ColumnLayout {
                spacing: 0
                Text {
                    readonly property int h: new Date().getHours()
                    text: (h < 5 ? "Доброй ночи" : h < 12 ? "Доброе утро" : h < 18 ? "Добрый день" : "Добрый вечер") + ", " + (kuser.fullName || kuser.loginName)
                    color: mp.text; font.family: mp.fontDisplay; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                Text {
                    text: media.playing ? "♪ " + media.title + " — " + media.artist : Qt.formatDate(new Date(), "dddd, d MMMM")
                    color: media.playing ? mp.accentHi : mp.textDim; font.family: mp.font; font.pixelSize: 11
                    Layout.maximumWidth: 300; elide: Text.ElideRight
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 34; height: 34; radius: 17
                color: menu.colorsOpen ? mp.accent : (cb.containsMouse ? mp.tint(0.12, 0.69, 0.92, 0.22) : Qt.rgba(1, 1, 1, 0.05))
                border.color: cb.containsMouse || menu.colorsOpen ? mp.strokeHi : mp.stroke
                scale: cb.pressed ? 0.88 : 1
                Behavior on color { ColorAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 100 } }
                // tiny rainbow ring hints "colours"
                Rectangle {
                    anchors.centerIn: parent; width: 18; height: 18; radius: 9
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#FF6E96" } GradientStop { position: 0.33; color: "#FFD27A" }
                        GradientStop { position: 0.66; color: "#62E6C8" } GradientStop { position: 1; color: "#7B6BFF" } }
                    rotation: menu.colorsOpen ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                    Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: menu.colorsOpen ? mp.accent : mp.panel }
                }
                QQC2.ToolTip.visible: cb.containsMouse; QQC2.ToolTip.text: "Цвет темы"; QQC2.ToolTip.delay: 500
                MouseArea { id: cb; anchors.fill: parent; hoverEnabled: true; onClicked: menu.colorsOpen = !menu.colorsOpen }
            }
            Repeater {
                model: [
                    { icon: "system-lock-screen", tip: "Заблокировать", cmd: "loginctl lock-session" },
                    { icon: "system-log-out", tip: "Выйти", cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt promptLogout" },
                    { icon: "system-reboot", tip: "Перезагрузить", cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt promptReboot" },
                    { icon: "system-shutdown", tip: "Выключить", cmd: "qdbus6 org.kde.LogoutPrompt /LogoutPrompt promptShutDown" }
                ]
                Rectangle {
                    required property var modelData
                    width: 34; height: 34; radius: 17
                    color: pa.containsMouse ? (modelData.icon === "system-shutdown" ? Qt.rgba(1, 0.35, 0.5, 0.25) : mp.tint(0.12, 0.69, 0.92, 0.22)) : Qt.rgba(1, 1, 1, 0.05)
                    border.color: pa.containsMouse ? mp.strokeHi : mp.stroke
                    scale: pa.pressed ? 0.88 : 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    Kirigami.Icon { anchors.centerIn: parent; width: 16; height: 16; source: parent.modelData.icon; color: mp.text; isMask: true }
                    QQC2.ToolTip.visible: pa.containsMouse; QQC2.ToolTip.text: modelData.tip; QQC2.ToolTip.delay: 500
                    MouseArea { id: pa; anchors.fill: parent; hoverEnabled: true; onClicked: { root.expanded = false; root.run(parent.modelData.cmd); } }
                }
            }
        }

        // ---------------- theme colour panel ----------------
        Rectangle {
            id: colors
            z: 20
            anchors { left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6 }
            y: header.y + header.height + 10 + (menu.colorsOpen ? 0 : 24)
            height: menu.height - (header.y + header.height + 10)
            opacity: menu.colorsOpen ? 1 : 0
            visible: opacity > 0
            Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 220 } }
            radius: 18
            color: mp.tint(0.04, 0.07, 0.16, 0.97)
            border.color: mp.stroke
            MouseArea { anchors.fill: parent; onWheel: w => w.accepted = true }   // swallow clicks/scroll

            readonly property var modes: [
                { id: "preset", label: "Палитры", icon: "color-management" },
                { id: "rgb", label: "RGB", icon: "games-highscores" },
                { id: "cover", label: "Обложка", icon: "media-album-cover" },
                { id: "custom", label: "Свой", icon: "color-picker" }
            ]

            Column {
                anchors { fill: parent; margins: 18 }
                spacing: 16

                Text { text: "Цвет темы"; color: mp.text; font.family: mp.fontDisplay; font.pixelSize: 16; font.weight: Font.DemiBold }

                // mode switcher with a sliding pill
                Rectangle {
                    id: seg
                    width: parent.width; height: 38; radius: 19
                    color: Qt.rgba(1, 1, 1, 0.04); border.color: mp.stroke
                    readonly property int cur: Math.max(0, colors.modes.findIndex(m => m.id === mp.mode))
                    Rectangle {
                        y: 3; height: parent.height - 6; radius: height / 2
                        width: (seg.width - 6) / 4
                        x: 3 + seg.cur * width
                        Behavior on x { SpringAnimation { spring: 4; damping: 0.4 } }
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: mp.accent2 } GradientStop { position: 1; color: mp.accent } }
                    }
                    Row {
                        x: 3; y: 3
                        Repeater {
                            model: colors.modes
                            Item {
                                required property var modelData
                                required property int index
                                width: (seg.width - 6) / 4; height: seg.height - 6
                                Row {
                                    anchors.centerIn: parent; spacing: 6
                                    Kirigami.Icon { width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter
                                                    source: parent.parent.modelData.icon; isMask: true
                                                    color: seg.cur === parent.parent.index ? "white" : mp.textDim }
                                    Text { text: parent.parent.modelData.label; anchors.verticalCenter: parent.verticalCenter
                                           color: seg.cur === parent.parent.index ? "white" : mp.text
                                           font.family: mp.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: mp.set({ mode: parent.modelData.id }) }
                            }
                        }
                    }
                }

                // ---- presets ----
                Flickable {
                  visible: mp.mode === "preset"
                  width: parent.width
                  height: colors.height - 36 - 20 - 38 - 32       // what is left under the title + mode switch
                  contentHeight: presetGrid.height; clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  QQC2.ScrollBar.vertical: QQC2.ScrollBar { policy: QQC2.ScrollBar.AsNeeded }
                  Grid {
                    id: presetGrid
                    columns: 4; columnSpacing: 8; rowSpacing: 8
                    width: parent.width
                    Repeater {
                        model: mp.presets
                        Rectangle {
                            id: pc
                            required property var modelData
                            readonly property bool on: mp.mode === "preset" && mp.preset === modelData.id
                            width: (colors.width - 36 - 24) / 4; height: 50; radius: 14
                            color: pa2.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.035)
                            border.width: on ? 1.5 : 1
                            // a strip of the palette's real colours along the bottom
                            Row {
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 6; anchors.right: parent.right; anchors.rightMargin: 10
                                spacing: 3
                                Repeater {
                                    model: [-60, -29, 0, 29, 49]          // background-ish, accent, partner, violet …
                                    Rectangle {
                                        required property int modelData
                                        width: 5; height: 5; radius: 2.5
                                        readonly property real k: pc.modelData.o / 29
                                        color: Qt.hsva((((pc.modelData.h + modelData * k) % 360 + 360) % 360) / 360, Math.min(1, 0.75 * pc.modelData.s), 0.95, 1)
                                    }
                                }
                            }
                            border.color: on ? mp.presetColor(modelData) : mp.stroke
                            scale: pa2.pressed ? 0.95 : 1
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Row {
                                anchors.verticalCenter: parent.verticalCenter; x: 10; spacing: 9
                                // two-tone orb: accent → partner colour
                                Rectangle {
                                    width: 28; height: 28; radius: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: Qt.hsva(((pc.modelData.h % 360 + 360) % 360) / 360, Math.min(1, 0.6 * pc.modelData.s), 1, 1) }
                                        GradientStop { position: 1; color: Qt.hsva((((pc.modelData.h + pc.modelData.o) % 360 + 360) % 360) / 360, Math.min(1, 0.76 * pc.modelData.s), 1, 1) }
                                    }
                                    layer.enabled: pc.on
                                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: mp.presetColor(pc.modelData); shadowBlur: 0.9; shadowOpacity: 0.9; shadowVerticalOffset: 0 }
                                    Text { anchors.centerIn: parent; text: "✓"; visible: pc.on; color: "white"; font.pixelSize: 15; font.weight: Font.Bold }
                                }
                                Text { text: pc.modelData.name; anchors.verticalCenter: parent.verticalCenter
                                       width: pc.width - 10 - 28 - 9 - 6; elide: Text.ElideRight
                                       color: mp.text; font.family: mp.font; font.pixelSize: 12; font.weight: pc.on ? Font.DemiBold : Font.Normal }
                            }
                            MouseArea { id: pa2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: mp.set({ mode: "preset", preset: pc.modelData.id }) }
                        }
                    }
                  }
                }

                // ---- RGB ----
                Column {
                    visible: mp.mode === "rgb"
                    width: parent.width; spacing: 12
                    Rectangle {   // live rainbow preview with the current hue marker
                        width: parent.width; height: 14; radius: 7
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0.00; color: "#FF4D6D" } GradientStop { position: 0.17; color: "#FFB547" }
                            GradientStop { position: 0.33; color: "#C6F25A" } GradientStop { position: 0.50; color: "#3EE6C8" }
                            GradientStop { position: 0.67; color: "#3D8BFF" } GradientStop { position: 0.83; color: "#A35BFF" }
                            GradientStop { position: 1.00; color: "#FF4D6D" } }
                        Rectangle { width: 6; height: 22; radius: 3; y: -4; color: "white"
                                    x: (((mp.h % 360) + 360) % 360) / 360 * (parent.width - width) }
                    }
                    Row {
                        spacing: 12
                        Text { text: "Скорость"; color: mp.textDim; font.family: mp.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        QQC2.Slider {
                            id: speed
                            width: colors.width - 36 - 140
                            from: 0.1; to: 4; value: mp.speed
                            onMoved: mp.set({ speed: Math.round(value * 10) / 10 })
                        }
                        Text { text: (60 / Math.max(0.1, mp.speed)).toFixed(0) + " с/круг"; color: mp.text; font.family: mp.font; font.pixelSize: 12
                               anchors.verticalCenter: parent.verticalCenter }
                    }
                    Text { width: parent.width; wrapMode: Text.WordWrap; color: mp.textFaint; font.family: mp.font; font.pixelSize: 11
                           text: "Переливаются обои, сияние, визуализаторы, остров, док и виджеты. Рамки окон и панели остаются на последней палитре." }
                }

                // ---- cover ----
                Row {
                    visible: mp.mode === "cover"
                    spacing: 14
                    Rectangle {
                        width: 64; height: 64; radius: 14; color: mp.surface; clip: true
                        Image { anchors.fill: parent; source: media.art; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(128, 128) }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Text { text: media.title ? media.title : "Ничего не играет"; color: mp.text; font.family: mp.font; font.pixelSize: 13; font.weight: Font.DemiBold
                               width: colors.width - 36 - 80; elide: Text.ElideRight }
                        Row { spacing: 8
                            Rectangle { width: 16; height: 16; radius: 8; color: mp.accent; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "цвет берётся из обложки и меняется с каждым треком"; color: mp.textDim; font.family: mp.font; font.pixelSize: 11 } }
                    }
                }

                // ---- custom ----
                Column {
                    id: custom
                    visible: mp.mode === "custom"
                    width: parent.width; spacing: 14
                    property real hue: mp.custom.hsvHue < 0 ? 0.55 : mp.custom.hsvHue
                    property real sat: mp.custom.hsvSaturation
                    readonly property color pick: Qt.hsva(hue, sat, 0.92, 1)
                    function commit() { mp.set({ mode: "custom", custom: "" + custom.pick }); }
                    Row {
                        spacing: 14
                        Rectangle { width: 44; height: 44; radius: 22; color: custom.pick; border.color: Qt.rgba(1, 1, 1, 0.4)
                                    layer.enabled: true
                                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: custom.pick; shadowBlur: 0.9; shadowOpacity: 0.8; shadowVerticalOffset: 0 } }
                        Column { anchors.verticalCenter: parent.verticalCenter; spacing: 2
                            Text { text: ("" + custom.pick).toUpperCase(); color: mp.text; font.family: mp.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text { text: "оттенки, свечение и тёмные тона подберутся сами"; color: mp.textDim; font.family: mp.font; font.pixelSize: 11 } }
                    }
                    // hue strip
                    Item {
                        width: parent.width; height: 22
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 14; radius: 7
                            gradient: Gradient { orientation: Gradient.Horizontal
                                GradientStop { position: 0.00; color: "#FF0000" } GradientStop { position: 0.17; color: "#FFFF00" }
                                GradientStop { position: 0.33; color: "#00FF00" } GradientStop { position: 0.50; color: "#00FFFF" }
                                GradientStop { position: 0.67; color: "#0000FF" } GradientStop { position: 0.83; color: "#FF00FF" }
                                GradientStop { position: 1.00; color: "#FF0000" } }
                        }
                        Rectangle { width: 22; height: 22; radius: 11; color: Qt.hsva(custom.hue, 1, 1, 1); border.color: "white"; border.width: 2
                                    x: custom.hue * (parent.width - width) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            function at(mx) { custom.hue = Math.max(0, Math.min(0.999, mx / width)); }
                            onPressed: m => at(m.x); onPositionChanged: m => { if (pressed) at(m.x); }
                            onReleased: custom.commit() }
                    }
                    // saturation strip
                    Item {
                        width: parent.width; height: 22
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 14; radius: 7
                            gradient: Gradient { orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Qt.hsva(custom.hue, 0.05, 0.92, 1) }
                                GradientStop { position: 1; color: Qt.hsva(custom.hue, 1, 0.92, 1) } }
                        }
                        Rectangle { width: 22; height: 22; radius: 11; color: custom.pick; border.color: "white"; border.width: 2
                                    x: custom.sat * (parent.width - width) }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            function at(mx) { custom.sat = Math.max(0.05, Math.min(1, mx / width)); }
                            onPressed: m => at(m.x); onPositionChanged: m => { if (pressed) at(m.x); }
                            onReleased: custom.commit() }
                    }
                }
            }
        }

        // search field
        Rectangle {
            id: searchBox
            anchors { left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6 }
            y: header.y + header.height + 10
            height: 40; radius: 20
            color: Qt.rgba(1, 1, 1, 0.05)
            border.width: search.activeFocus ? 1.5 : 1
            border.color: search.activeFocus ? mp.accent : mp.stroke
            Behavior on border.color { ColorAnimation { duration: mp.fast } }
            Kirigami.Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; source: "search"; color: mp.accentHi; isMask: true }
            TextInput {
                id: search
                anchors { left: parent.left; right: parent.right; leftMargin: 40; rightMargin: 16; verticalCenter: parent.verticalCenter }
                color: mp.text; selectionColor: mp.accent; font.family: mp.font; font.pixelSize: 14
                text: root.query
                onTextEdited: root.query = text
                Keys.onDownPressed: { grid.currentIndex = 0; grid.forceActiveFocus(); }
                onAccepted: if (results.count) root.launch(results.get(Math.max(0, grid.currentIndex)).sourceRow)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Найти приложение…"; color: mp.textFaint
                       font: search.font; visible: !search.text.length }
            }
        }

        // category chips
        ListView {
            id: chips
            anchors { left: parent.left; right: parent.right; leftMargin: 6; rightMargin: 6 }
            y: searchBox.y + searchBox.height + 12
            height: 30
            orientation: ListView.Horizontal
            spacing: 6
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: ListModel { id: chipModel }
            Component.onCompleted: rebuild()
            Connections { target: categories; function onCountChanged() { chips.rebuild(); } }
            function rebuild() {
                chipModel.clear();
                chipModel.append({ label: "★ Избранное", row: -2 });
                chipModel.append({ label: "Все", row: -1 });
                for (var i = 0; i < categories.count; i++) chipModel.append({ label: categories.get(i).label, row: categories.get(i).row });
            }
            delegate: Rectangle {
                required property string label
                required property int row
                readonly property bool active: root.category === row && !root.query.length
                height: 28; radius: 14
                width: chipText.implicitWidth + 24
                color: active ? mp.accent : (ca.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.04))
                border.color: active ? "transparent" : mp.stroke
                Behavior on color { ColorAnimation { duration: 140 } }
                Text { id: chipText; anchors.centerIn: parent; text: parent.label; color: parent.active ? mp.bg : mp.text
                       font.family: mp.font; font.pixelSize: 11; font.weight: parent.active ? Font.DemiBold : Font.Normal }
                MouseArea { id: ca; anchors.fill: parent; hoverEnabled: true; onClicked: { root.query = ""; root.category = parent.row; } }
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton
                onWheel: w => chips.contentX = Math.max(0, Math.min(chips.contentWidth - chips.width, chips.contentX - w.angleDelta.y)) }
        }

        // app grid with cascade animation
        GridView {
            id: grid
            anchors { left: parent.left; right: parent.right; top: chips.bottom; bottom: parent.bottom
                      topMargin: 12; leftMargin: 2; rightMargin: 2 }
            clip: true
            cellWidth: Math.floor(width / 5); cellHeight: 104
            model: results
            currentIndex: -1
            keyNavigationEnabled: true
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar { width: 4 }
            Keys.onReturnPressed: if (currentIndex >= 0) root.launch(results.get(currentIndex).sourceRow)
            highlightFollowsCurrentItem: true
            delegate: Item {
                id: cell
                required property string label
                required property var appIcon
                required property int sourceRow
                required property int index
                width: grid.cellWidth; height: grid.cellHeight
                property real appear: 0
                opacity: appear
                transform: Translate { y: (1 - cell.appear) * 18 }
                Component.onCompleted: cascade.start()
                Connections { target: root; function onGenerationChanged() { cell.appear = 0; cascade.restart(); } }
                SequentialAnimation {
                    id: cascade
                    PauseAnimation { duration: Math.max(0, Math.min(cell.index, 20)) * 22 }
                    NumberAnimation { target: cell; property: "appear"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 4; radius: 14
                    color: aa.containsMouse || grid.currentIndex === cell.index ? mp.tint(0.12, 0.69, 0.92, 0.14) : "transparent"
                    border.color: aa.containsMouse || grid.currentIndex === cell.index ? mp.tint(0.37, 0.82, 1, 0.35) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                Kirigami.Icon {
                    id: ico
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 12; width: 48; height: 48
                    source: cell.appIcon
                    scale: aa.pressed ? 0.9 : (aa.containsMouse ? 1.14 : 1)
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                }
                Text {
                    x: 4; y: 66; width: parent.width - 8
                    text: cell.label; color: mp.text
                    font.family: mp.font; font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                }
                MouseArea { id: aa; anchors.fill: parent; hoverEnabled: true; onClicked: root.launch(cell.sourceRow) }
            }
            Text {
                anchors.centerIn: parent; visible: results.count === 0
                text: "Ничего не нашлось ✦"; color: mp.textDim; font.family: mp.font; font.pixelSize: 13
            }
        }
    }
}
