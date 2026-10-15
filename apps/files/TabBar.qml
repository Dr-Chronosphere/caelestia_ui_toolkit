import QtQuick
import CaelestiaUI

// The explorer's tab strip: one chip per tab (folder name, close button), a "+" button.
// Middle-click closes a tab. Purely presentational: the host owns the tab list.
Item {
    id: root

    // [{ id, label }]
    property var tabs: []
    property string active

    signal activated(string id)
    signal closeRequested(string id)
    signal newRequested

    implicitHeight: 44

    readonly property real chipWidth: Math.max(96, Math.min(220, (width - plus.width - Theme.spacing.small * 2) / Math.max(1, tabs.length) - Theme.spacing.extraSmall))

    Row {
        anchors.left: parent.left
        anchors.leftMargin: Theme.padding.medium
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.extraSmall

        Repeater {
            model: root.tabs

            delegate: StyledRect {
                id: chip

                required property var modelData
                readonly property bool isActive: modelData.id === root.active

                width: root.chipWidth
                height: 34
                radius: Theme.rounding.full
                color: isActive ? Theme.palette.m3secondaryContainer : "transparent"

                StateLayer {
                    onClicked: root.activated(chip.modelData.id)
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.MiddleButton
                    onClicked: root.closeRequested(chip.modelData.id)
                }

                MaterialIcon {
                    id: folderIcon

                    anchors.left: parent.left
                    anchors.leftMargin: Theme.padding.medium
                    anchors.verticalCenter: parent.verticalCenter
                    text: "folder"
                    iconSize: Theme.iconSize.medium
                    color: chip.isActive ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurfaceVariant
                }

                StyledText {
                    anchors.left: folderIcon.right
                    anchors.leftMargin: Theme.spacing.small
                    anchors.right: closeBtn.left
                    anchors.rightMargin: Theme.spacing.extraSmall
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: chip.modelData.label
                    color: chip.isActive ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurfaceVariant
                }

                // Tabs are closable unless it is the only one (closing the window is the window's job).
                IconButton {
                    id: closeBtn

                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 28
                    implicitHeight: 28
                    iconSize: Theme.iconSize.small
                    icon: "close"
                    type: ButtonBase.Text
                    visible: root.tabs.length > 1
                    onClicked: root.closeRequested(chip.modelData.id)
                }
            }
        }

        IconButton {
            id: plus

            icon: "add"
            type: ButtonBase.Text
            implicitWidth: 34
            implicitHeight: 34
            iconSize: Theme.iconSize.medium
            onClicked: root.newRequested()
        }
    }
}
