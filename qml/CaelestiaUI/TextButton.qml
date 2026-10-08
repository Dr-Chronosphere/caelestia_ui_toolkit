import QtQuick

ButtonBase {
    id: root

    property string text
    property string icon

    implicitHeight: 40
    implicitWidth: row.implicitWidth + Theme.padding.large * 2

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Theme.spacing.small

        MaterialIcon {
            visible: root.icon.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.contentColour
            fill: root.checked ? 1 : 0
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.contentColour
            font: Theme.label.large
        }
    }
}
