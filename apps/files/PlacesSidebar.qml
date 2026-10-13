import QtQuick
import CaelestiaUI

Rectangle {
    id: root

    property var places: []
    property string current

    signal activated(string path)

    implicitWidth: 200
    color: Theme.palette.m3surfaceContainerLow

    Column {
        anchors.fill: parent
        anchors.margins: Theme.padding.medium
        spacing: Theme.spacing.extraSmall

        StyledText {
            leftPadding: Theme.padding.medium
            bottomPadding: Theme.padding.small
            text: "Places"
            font: Theme.label.medium
            color: Theme.palette.m3onSurfaceVariant
        }

        Repeater {
            model: root.places

            StyledRect {
                id: item

                required property var modelData

                readonly property bool selected: root.current === modelData.path

                width: parent.width
                height: 40
                radius: Theme.rounding.full
                color: selected ? Theme.palette.m3secondaryContainer : "transparent"

                StateLayer {
                    color: item.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurface
                    onClicked: root.activated(item.modelData.path)
                }

                MaterialIcon {
                    id: icon

                    anchors.left: parent.left
                    anchors.leftMargin: Theme.padding.medium
                    anchors.verticalCenter: parent.verticalCenter
                    text: item.modelData.icon
                    fill: item.selected ? 1 : 0
                    color: item.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurfaceVariant
                }
                StyledText {
                    anchors.left: icon.right
                    anchors.leftMargin: Theme.spacing.medium
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.padding.medium
                    anchors.verticalCenter: parent.verticalCenter
                    text: item.modelData.label
                    elide: Text.ElideRight
                    font: Theme.label.large
                    color: item.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurface
                }
            }
        }
    }
}
