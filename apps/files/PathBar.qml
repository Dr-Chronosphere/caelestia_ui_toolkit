import QtQuick
import CaelestiaUI

// Clickable breadcrumb. Shows the tail of the path when it does not fit.
Item {
    id: root

    property var crumbs: []

    signal activated(string path)

    implicitHeight: 40
    clip: true

    Row {
        id: row

        x: Math.min(0, root.width - width)
        height: parent.height
        spacing: 0

        Repeater {
            model: root.crumbs

            Row {
                id: crumb

                required property var modelData
                required property int index

                readonly property bool last: index === root.crumbs.length - 1

                height: row.height

                MaterialIcon {
                    visible: crumb.index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "chevron_right"
                    iconSize: Theme.iconSize.small
                    color: Theme.palette.m3onSurfaceVariant
                }

                StyledRect {
                    anchors.verticalCenter: parent.verticalCenter
                    width: label.implicitWidth + Theme.padding.medium * 2
                    height: 32
                    radius: Theme.rounding.full
                    color: "transparent"

                    StateLayer {
                        onClicked: root.activated(crumb.modelData.path)
                    }
                    StyledText {
                        id: label

                        anchors.centerIn: parent
                        text: crumb.modelData.label
                        font: crumb.last ? Theme.title.small : Theme.body.medium
                        color: crumb.last ? Theme.palette.m3onSurface : Theme.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
