import QtQuick

// Selectable list row: leading icon, title/subtitle, optional trailing content.
// Suited to device pickers, settings lists, etc.
StyledRect {
    id: root

    property string icon
    property string title
    property string subtitle
    property bool selected
    property bool disabled

    // Items placed inside the row appear at its right edge (switch, slider, button...).
    default property alias trailing: trailingHolder.data

    signal clicked

    implicitHeight: Math.max(56, textCol.implicitHeight + Theme.padding.medium * 2)
    implicitWidth: 320
    radius: Theme.rounding.medium
    color: selected ? Theme.palette.m3secondaryContainer : "transparent"

    StateLayer {
        disabled: root.disabled
        color: root.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurface
        onClicked: root.clicked()
    }

    MaterialIcon {
        id: leading

        visible: root.icon.length > 0
        anchors.left: parent.left
        anchors.leftMargin: Theme.padding.large
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        iconSize: Theme.iconSize.large
        fill: root.selected ? 1 : 0
        color: root.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurfaceVariant
    }

    Column {
        id: textCol

        anchors.left: leading.visible ? leading.right : parent.left
        anchors.leftMargin: leading.visible ? Theme.spacing.medium : Theme.padding.large
        anchors.right: trailingHolder.left
        anchors.rightMargin: Theme.spacing.medium
        anchors.verticalCenter: parent.verticalCenter

        StyledText {
            width: parent.width
            text: root.title
            elide: Text.ElideRight
            font: Theme.body.large
            color: root.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurface
        }
        StyledText {
            visible: root.subtitle.length > 0
            width: parent.width
            text: root.subtitle
            elide: Text.ElideRight
            font: Theme.body.small
            color: root.selected ? Theme.palette.m3onSecondaryContainer : Theme.palette.m3onSurfaceVariant
        }
    }

    Item {
        id: trailingHolder

        anchors.right: parent.right
        anchors.rightMargin: Theme.padding.large
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
