import QtQuick

// Single-line text field: pill container, optional leading icon and placeholder.
StyledRect {
    id: root

    property alias text: input.text
    property alias input: input
    property string placeholder
    property string icon

    signal accepted

    implicitWidth: 240
    implicitHeight: 40
    radius: Theme.rounding.full
    color: Theme.palette.m3surfaceContainerHigh
    border.width: input.activeFocus ? 2 : 0
    border.color: Theme.palette.m3primary

    MaterialIcon {
        id: lead

        visible: root.icon.length > 0
        anchors.left: parent.left
        anchors.leftMargin: Theme.padding.medium
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: Theme.palette.m3onSurfaceVariant
    }

    TextInput {
        id: input

        anchors.left: lead.visible ? lead.right : parent.left
        anchors.leftMargin: lead.visible ? Theme.spacing.small : Theme.padding.large
        anchors.right: parent.right
        anchors.rightMargin: Theme.padding.large
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        color: Theme.palette.m3onSurface
        selectionColor: Theme.palette.m3primary
        selectedTextColor: Theme.palette.m3onPrimary
        font: Theme.body.medium
        selectByMouse: true
        onAccepted: root.accepted()

        StyledText {
            visible: input.text.length === 0 && !input.inputMethodComposing
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholder
            color: Theme.palette.m3onSurfaceVariant
            font: input.font
        }
    }
}
