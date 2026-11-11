// Midnight Pulse · Dock — compact glass capsule hugging the icons, macOS-style magnification,
// pinned | running separator, glowing window indicators and a launch bounce.
// The panel's own background is switched off; the capsule is drawn here.
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import "common" as Common

PlasmoidItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation
    Common.Palette { id: mp; paused: occ.covered }
    Common.Occlusion { id: occ }

    readonly property real base: 36          // icon size
    readonly property real slot: base + 10   // cell width
    readonly property real sepW: 14          // width of the pinned | running divider
    readonly property real maxScale: 1.5
    readonly property real reach: 130        // px over which magnification falls off
    readonly property real capH: 48          // capsule height
    readonly property real capPad: 8        // capsule inner side padding

    // make the hosting panel transparent so only our capsule shows
    function clearPanel() {
        var c = Plasmoid.containment;
        if (c && c.backgroundHints !== PlasmaCore.Types.NoBackground) c.backgroundHints = PlasmaCore.Types.NoBackground;
    }
    Component.onCompleted: Qt.callLater(clearPanel)
    Timer { interval: 1500; running: true; onTriggered: root.clearPanel() }

    TaskManager.VirtualDesktopInfo { id: vdi }
    TaskManager.ActivityInfo { id: activityInfo }
    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupApplications
        sortMode: TaskManager.TasksModel.SortManual
        separateLaunchers: false
        launchInPlace: true
        filterByVirtualDesktop: false
        filterByActivity: true
        filterNotMinimized: false
        virtualDesktop: vdi.currentDesktop
        activity: activityInfo.currentActivity
        launcherList: Plasmoid.configuration.launchers
        onLauncherListChanged: Plasmoid.configuration.launchers = launcherList
        onCountChanged: Qt.callLater(root.findSplit)
        onDataChanged: Qt.callLater(root.findSplit)
    }

    // index of the first running app that isn't pinned (-1 = none) → divider goes before it
    property int split: -1
    function findSplit() {
        var s = -1;
        for (var i = 0; i < tasks.count; i++) {
            if (tasks.data(tasks.makeModelIndex(i), TaskManager.AbstractTasksModel.HasLauncher) !== true) { s = i; break; }
        }
        split = (s > 0) ? s : -1;
    }

    fullRepresentation: Item {
        id: dock
        readonly property real contentW: tasks.count * root.slot + (root.split > 0 ? root.sepW : 0)
        Layout.minimumWidth: contentW + 2 * root.capPad + 120   // room for the magnified edges
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true
        property real mouseX: -1000
        readonly property bool hovering: hoverArea.containsMouse
        readonly property real gridLeft: (width - contentW) / 2
        function slotCenter(i) { return gridLeft + i * root.slot + root.slot / 2 + (root.split > 0 && i >= root.split ? root.sepW : 0); }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: m => dock.mouseX = m.x
            onExited: dock.mouseX = -1000
        }

        // ---------- capsule ----------
        Item {
            id: capsule
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 6
            height: root.capH
            width: row.width + 2 * root.capPad
            Behavior on width { enabled: !dock.hovering; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            Rectangle {
                id: glass
                anchors.fill: parent
                radius: 16
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowBlur: 1.0; shadowOpacity: 0.6; shadowVerticalOffset: 4 }
                gradient: Gradient {
                    GradientStop { position: 0; color: mp.tint(0.09, 0.14, 0.30, 0.86) }
                    GradientStop { position: 1; color: mp.tint(0.03, 0.05, 0.12, 0.92) }
                }
                border.width: 1
                border.color: dock.hovering ? mp.tint(0.37, 0.82, 1, 0.45) : mp.tint(0.47, 0.75, 1, 0.20)
                Behavior on border.color { ColorAnimation { duration: mp.fast } }
                // top highlight line
                Rectangle {
                    x: parent.radius; width: parent.width - 2 * parent.radius; y: 1; height: 1
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: mp.tint(0.6, 0.88, 1, 0.35) }
                        GradientStop { position: 1; color: "transparent" } }
                }
                // slow shimmer sweeping across the glass
                Item {
                    anchors.fill: parent; clip: true
                    Rectangle {
                        width: 120; height: parent.height * 2; rotation: 22; y: -parent.height / 2
                        gradient: Gradient { orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 0.5; color: mp.tint(0.37, 0.82, 1, 0.06) }
                            GradientStop { position: 1; color: "transparent" } }
                        NumberAnimation on x { from: -200; to: glass.width + 80; duration: 7000; loops: Animation.Infinite; running: !occ.covered }
                    }
                }
            }
        }

        // ---------- icons ----------
        Row {
            id: row
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            height: parent.height
            Repeater {
                model: tasks
                delegate: Item {
                    id: cell
                    required property int index
                    required property var model
                    readonly property var modelIndex: tasks.makeModelIndex(index)
                    readonly property bool sepBefore: root.split > 0 && index === root.split
                    // magnification uses the *unmagnified* grid, so widths can't feed back into it
                    readonly property real dist: Math.abs(dock.mouseX - dock.slotCenter(index))
                    readonly property real mag: dock.mouseX < -500 ? 0 : Math.max(0, Math.cos(Math.min(1, dist / root.reach) * Math.PI / 2))
                    readonly property real zoom: 1 + (root.maxScale - 1) * mag
                    width: root.slot + (sepBefore ? root.sepW : 0) + (root.maxScale - 1) * root.base * mag * 0.6
                    height: row.height
                    Behavior on width { enabled: !dock.hovering; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    // pinned | running divider
                    Rectangle {
                        visible: cell.sepBefore
                        x: root.sepW / 2 - 0.5; width: 1
                        height: root.capH - 20
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 6 + 10
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 0.5; color: mp.tint(0.47, 0.75, 1, 0.45) }
                            GradientStop { position: 1; color: "transparent" }
                        }
                    }

                    Item {
                        id: slotBox
                        anchors.right: parent.right
                        width: parent.width - (cell.sepBefore ? root.sepW : 0)
                        height: parent.height

                        // appear animation for new windows
                        property real born: 0
                        Component.onCompleted: bornAnim.start()
                        NumberAnimation { id: bornAnim; target: slotBox; property: "born"; from: 0; to: 1; duration: 420; easing.type: Easing.OutBack }

                        // glow pool under the active app
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                            width: root.base + 6; height: root.base + 6; radius: 12
                            visible: cell.model.IsActive === true
                            color: mp.tint(0.12, 0.69, 0.92, 0.10)
                            border.color: mp.tint(0.37, 0.82, 1, 0.22)
                        }

                        Item {
                            id: iconBox
                            width: root.base; height: root.base
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6 + (root.capH - root.base) / 2 + 1 + bounce.offset
                            transformOrigin: Item.Bottom
                            scale: cell.zoom * slotBox.born * (press.pressed ? 0.9 : 1)
                            Behavior on scale { enabled: !dock.hovering; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                            Kirigami.Icon {
                                anchors.fill: parent
                                source: cell.model.decoration
                                active: press.containsMouse
                                roundToIconSize: false
                                layer.enabled: cell.mag > 0.3 || cell.model.IsActive === true
                                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: mp.accent; shadowBlur: 0.8
                                                            shadowOpacity: 0.35 + cell.mag * 0.35; shadowVerticalOffset: 0 }
                            }
                            // attention shake
                            SequentialAnimation on rotation {
                                running: cell.model.IsDemandingAttention === true && !occ.covered
                                loops: Animation.Infinite
                                NumberAnimation { to: 8; duration: 70 } NumberAnimation { to: -8; duration: 140 } NumberAnimation { to: 0; duration: 70 }
                                PauseAnimation { duration: 900 }
                            }
                        }

                        PlasmaCore.ToolTipArea {
                            anchors.fill: parent
                            mainText: cell.model.display || ""
                            subText: cell.model.IsLauncher ? "Запустить" : (cell.model.ChildCount > 1 ? cell.model.ChildCount + " окна" : "")
                            location: PlasmaCore.Types.BottomEdge
                        }

                        // launch bounce
                        QtObject { id: bounce; property real offset: 0 }
                        SequentialAnimation {
                            id: bounceAnim
                            running: cell.model.IsStartup === true
                            loops: 3
                            NumberAnimation { target: bounce; property: "offset"; to: 14; duration: 260; easing.type: Easing.OutQuad }
                            NumberAnimation { target: bounce; property: "offset"; to: 0; duration: 300; easing.type: Easing.OutBounce }
                        }

                        // running / active indicator inside the capsule
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 6 + 2
                            visible: cell.model.IsLauncher !== true
                            height: 3; radius: 1.5
                            width: cell.model.IsActive ? 18 : (cell.model.ChildCount > 1 ? 12 : 6)
                            color: cell.model.IsActive ? mp.accentHi : (cell.model.IsMinimized ? mp.textFaint : mp.accent)
                            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                            layer.enabled: true
                            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: mp.accent; shadowBlur: 0.6; shadowOpacity: 1; shadowVerticalOffset: 0 }
                        }

                        MouseArea {
                            id: press
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onPositionChanged: m => dock.mouseX = slotBox.mapToItem(dock, m.x, 0).x
                            onExited: if (!hoverArea.containsMouse) dock.mouseX = -1000
                            onClicked: m => {
                                if (m.button === Qt.MiddleButton || cell.model.IsLauncher) {
                                    tasks.requestNewInstance(cell.modelIndex);
                                    bounceAnim.restart();
                                } else if (cell.model.ChildCount > 1 && !cell.model.IsActive) {
                                    tasks.requestActivate(cell.modelIndex);
                                } else if (cell.model.IsActive) {
                                    tasks.requestToggleMinimized(cell.modelIndex);
                                } else {
                                    tasks.requestActivate(cell.modelIndex);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
