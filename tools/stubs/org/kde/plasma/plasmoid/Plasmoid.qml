pragma Singleton
import QtQuick
QtObject { property var configuration: ({}); property int formFactor: 0; property int location: 0; property int backgroundHints: 0; property int containmentDisplayHints: 0; readonly property int fullRepresentation: 1; readonly property int compactRepresentation: 0; property string pluginName: "stub"; property string title: ""; property string icon: ""
  property int constraintHints: 0; function internalAction(){return null} }
