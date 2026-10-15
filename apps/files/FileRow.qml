import QtQuick
import CaelestiaUI
import "logic/Files.js" as Files

// List-view row. Required properties match FolderListModel roles.
StyledRect {
    id: root

    required property string fileName
    required property bool fileIsDir
    required property real fileSize
    required property date fileModified

    property bool selected

    signal clicked
    signal activated

    readonly property var kind: Files.kindOf(fileName, fileIsDir)

    implicitHeight: 44
    radius: Theme.rounding.medium
    color: selected ? Theme.palette.m3secondaryContainer : "transparent"

    StateLayer {
        color: root.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurface
        onClicked: root.clicked()
        onDoubleClicked: root.activated()
    }

    MaterialIcon {
        id: icon

        anchors.left: parent.left
        anchors.leftMargin: Theme.padding.medium
        anchors.verticalCenter: parent.verticalCenter
        text: root.kind.icon
        fill: root.fileIsDir ? 1 : 0
        color: root.fileIsDir ? Theme.palette.m3primary : Theme.palette.m3onSurfaceVariant
    }

    StyledText {
        anchors.left: icon.right
        anchors.leftMargin: Theme.spacing.medium
        anchors.right: kindText.left
        anchors.rightMargin: Theme.spacing.medium
        anchors.verticalCenter: parent.verticalCenter
        text: root.fileName
        elide: Text.ElideMiddle
        font: Theme.body.medium
        color: root.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurface
    }

    StyledText {
        id: kindText

        anchors.right: sizeText.left
        anchors.rightMargin: Theme.spacing.medium
        anchors.verticalCenter: parent.verticalCenter
        width: 90
        text: root.kind.label
        elide: Text.ElideRight
        color: Theme.palette.m3onSurfaceVariant
    }

    StyledText {
        id: sizeText

        anchors.right: dateText.left
        anchors.rightMargin: Theme.spacing.medium
        anchors.verticalCenter: parent.verticalCenter
        width: 64
        horizontalAlignment: Text.AlignRight
        text: root.fileIsDir ? "" : Files.humanSize(root.fileSize)
        color: Theme.palette.m3onSurfaceVariant
    }

    StyledText {
        id: dateText

        anchors.right: parent.right
        anchors.rightMargin: Theme.padding.medium
        anchors.verticalCenter: parent.verticalCenter
        width: 96
        horizontalAlignment: Text.AlignRight
        text: Qt.formatDateTime(root.fileModified, "d MMM yyyy")
        color: Theme.palette.m3onSurfaceVariant
    }
}
