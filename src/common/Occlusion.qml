// Tells whether the desktop is hidden behind the *focused* fullscreen (or maximised) window on the
// current desktop/activity, so animations can sleep. Background games/windows that KWin still
// reports as fullscreen don't count — clicking the desktop or another window wakes everything up.
import QtQuick
import org.kde.taskmanager as TaskManager

Item {
    id: occ
    visible: false
    property bool fullscreenOnly: false
    property bool covered: false
    property bool debugLog: false

    TaskManager.VirtualDesktopInfo { id: vdi }
    TaskManager.ActivityInfo { id: act }
    TaskManager.TasksModel {
        id: tm
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: true
        filterByActivity: true
        filterMinimized: true
        virtualDesktop: vdi.currentDesktop
        activity: act.currentActivity
        onCountChanged: Qt.callLater(occ.recompute)
        onDataChanged: Qt.callLater(occ.recompute)
    }
    function recompute() {
        var c = false;
        for (var i = 0; i < tm.count && !c; i++) {
            var idx = tm.index(i, 0);
            if (tm.data(idx, TaskManager.AbstractTasksModel.IsActive) !== true) continue;
            if (tm.data(idx, TaskManager.AbstractTasksModel.IsFullScreen) === true) c = true;
            else if (!fullscreenOnly && tm.data(idx, TaskManager.AbstractTasksModel.IsMaximized) === true) c = true;
        }
        covered = c;
        if (debugLog) console.warn("MPOCC count=" + tm.count + " covered=" + c + " fsOnly=" + fullscreenOnly);
    }
    Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: occ.recompute() }
}
