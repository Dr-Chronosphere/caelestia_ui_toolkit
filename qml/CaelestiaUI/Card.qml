import QtQuick

// Rounded surface container; children go into the padded content area.
StyledRect {
    id: root

    default property alias content: holder.data
    property int padding: Theme.padding.large

    color: Theme.palette.m3surfaceContainer
    radius: Theme.rounding.large

    implicitWidth: holder.implicitWidth + padding * 2
    implicitHeight: holder.implicitHeight + padding * 2

    Item {
        id: holder

        anchors.fill: parent
        anchors.margins: root.padding
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }
}
