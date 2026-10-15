import QtQuick
import CaelestiaUI
import "logic/Files.js" as Files

// Icon-view cell. Required properties match FolderListModel roles.
Item {
    id: root

    required property string fileName
    required property url fileUrl
    required property bool fileIsDir
    required property real fileSize

    property bool selected

    signal clicked
    signal activated

    readonly property var kind: Files.kindOf(fileName, fileIsDir)

    implicitWidth: 120
    implicitHeight: 132

    StyledRect {
        anchors.fill: parent
        anchors.margins: 2
        radius: Theme.rounding.medium
        color: root.selected ? Theme.palette.m3secondaryContainer : "transparent"
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.padding.small
        width: parent.width - Theme.padding.small * 2
        spacing: Theme.spacing.extraSmall

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72
            height: 72

            // Folder
            MaterialIcon {
                visible: root.fileIsDir
                anchors.centerIn: parent
                text: "folder"
                fill: 1
                iconSize: 52
                color: Theme.palette.m3primary
            }

            // Image thumbnail
            RoundedImage {
                visible: !root.fileIsDir && Files.isImage(root.fileName)
                anchors.fill: parent
                source: visible ? root.fileUrl : ""
                sourceSize: Qt.size(160, 160)
                radius: Theme.rounding.small
            }

            // Generic file
            StyledRect {
                visible: !root.fileIsDir && !Files.isImage(root.fileName)
                anchors.centerIn: parent
                width: 56
                height: 68
                radius: Theme.rounding.small
                color: Theme.palette.m3surfaceContainerHighest

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Theme.padding.small
                    text: root.kind.icon
                    iconSize: Theme.iconSize.large
                    color: Theme.palette.m3onSurfaceVariant
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.padding.small
                    text: Files.extOf(root.fileName).toUpperCase().slice(0, 4)
                    font: Theme.label.small
                    color: Theme.palette.m3onSurfaceVariant
                }
            }
        }

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.fileName
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideMiddle
            font: Theme.label.medium
            color: root.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurface
        }
        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.fileIsDir ? "Folder" : Files.humanSize(root.fileSize)
            elide: Text.ElideRight
            font: Theme.label.small
            color: root.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurfaceVariant
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onDoubleClicked: root.activated()
    }
}
