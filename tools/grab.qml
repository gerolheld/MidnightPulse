// usage: qml6 grab.qml -- <component.qml> <out.png> <w> <h> <delayMs>
import QtQuick
import QtQuick.Window
Window {
  id: win
  property var a: Qt.application.arguments
  property int argi: a.indexOf("--") + 1
  width: Number(a[argi+2]); height: Number(a[argi+3]); visible: true; color: "#070B18"
  Loader { id: l; anchors.fill: parent; source: "file://" + win.a[win.argi] }
  Timer { interval: Number(win.a[win.argi+4]); running: true
    onTriggered: l.item ? l.parent.grabToImage(function(r){ r.saveToFile(win.a[win.argi+1]); console.warn("saved"); Qt.quit() }) : (console.warn("load failed", l.status), Qt.quit()) }
}
