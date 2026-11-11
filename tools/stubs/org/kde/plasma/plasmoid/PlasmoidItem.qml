import QtQuick
Item { property Component compactRepresentation; property Component fullRepresentation; property int preferredRepresentation; property string toolTipMainText; property string toolTipSubText; property bool expanded; property var switchWidth; property var switchHeight
  Loader { anchors.fill: parent; sourceComponent: parent.fullRepresentation || parent.compactRepresentation } }
