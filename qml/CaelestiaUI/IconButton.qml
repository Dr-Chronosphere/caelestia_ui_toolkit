import QtQuick

ButtonBase {
    id: root

    property string icon
    property int iconSize: Theme.iconSize.large

    implicitWidth: 40
    implicitHeight: 40

    MaterialIcon {
        anchors.centerIn: parent
        text: root.icon
        iconSize: root.iconSize
        color: root.contentColour
        fill: root.toggle && root.checked ? 1 : 0

        Behavior on fill {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
