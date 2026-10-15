import QtQuick
import CaelestiaUI

// The explorer's tab strip: one chip per tab (folder name, close button), a "+" button.
// Middle-click closes a tab. Drag a chip sideways to reorder, or off the strip (down or up) to tear
// it out into its own window. Purely presentational: the host owns the tab list.
Item {
    id: root

    // [{ id, label }]
    property var tabs: []
    property string active

    signal activated(string id)
    signal closeRequested(string id)
    signal newRequested
    signal moveRequested(string id, int to)
    signal tearRequested(string id)

    implicitHeight: 44

    readonly property real gap: Theme.spacing.extraSmall
    readonly property real leftPad: Theme.padding.medium
    readonly property real chipWidth: Math.max(96, Math.min(220, (width - plusBtn.width - leftPad - Theme.spacing.small * 2) / Math.max(1, tabs.length) - gap))
    readonly property real step: chipWidth + gap
    // How far (px) a chip must leave the strip vertically to count as tearing it out.
    readonly property real tearDistance: 44

    // Scene-coordinate centre of chip `i` (for tests).
    function chipCenter(i: int): var {
        const c = chips.itemAt(i);
        return c ? c.mapToItem(null, c.width / 2, c.height / 2) : null;
    }

    // Where chip `i` sits while chip `from` is being dragged to slot `to`: the ones in between
    // shuffle by one to make room.
    function slotOf(i: int, from: int, to: int): int {
        if (from < 0 || i === from)
            return i;
        if (from < to && i > from && i <= to)
            return i - 1;
        if (from > to && i >= to && i < from)
            return i + 1;
        return i;
    }

    property int dragFrom: -1
    property int dragTo: -1
    property bool dragTear: false
    // For the host's miniature of the tab being torn out: which tab, and where the pointer is
    // (in this item's coordinates).
    readonly property bool tearing: dragFrom >= 0 && dragTear && tabs.length > 1
    property string dragTabId: ""
    property real dragX: 0
    property real dragY: 0

    Repeater {
        id: chips

        model: root.tabs

        delegate: StyledRect {
            id: chip

            required property var modelData
            required property int index
            readonly property bool isActive: modelData.id === root.active
            readonly property bool dragging: drag.active
            readonly property bool tearing: dragging && Math.abs(drag.translation.y) > root.tearDistance && root.tabs.length > 1

            x: dragging ? root.leftPad + index * root.step + drag.translation.x : root.leftPad + root.slotOf(index, root.dragFrom, root.dragTo) * root.step
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: dragging ? Math.max(-root.tearDistance * 1.5, Math.min(root.tearDistance * 1.5, drag.translation.y)) : 0
            z: dragging ? 10 : 0
            width: root.chipWidth
            height: 34
            radius: Theme.rounding.full
            color: isActive ? Theme.palette.m3secondaryContainer : "transparent"
            border.width: tearing ? 2 : 0
            border.color: Theme.palette.m3primary
            scale: dragging ? 1.04 : 1
            opacity: tearing ? 0 : 1

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            // Others glide into place; the dragged chip follows the pointer exactly.
            Behavior on x {
                enabled: !chip.dragging

                Anim {
                    type: Anim.FastSpatial
                }
            }
            Behavior on scale {
                Anim {
                    type: Anim.FastEffects
                }
            }

            StateLayer {
                onClicked: root.activated(chip.modelData.id)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton
                onClicked: root.closeRequested(chip.modelData.id)
            }

            DragHandler {
                id: drag

                target: null
                acceptedButtons: Qt.LeftButton
                onActiveChanged: {
                    if (active) {
                        root.dragFrom = chip.index;
                        root.dragTo = chip.index;
                        root.dragTabId = chip.modelData.id;
                        // Grabbing a tab shows it (the miniature is a picture of it).
                        root.activated(chip.modelData.id);
                    } else {
                        // (translation is already reset here, so the state is tracked while dragging)
                        const from = root.dragFrom, to = root.dragTo;
                        const tear = root.dragTear && root.tabs.length > 1;
                        root.dragFrom = -1;
                        root.dragTo = -1;
                        root.dragTear = false;
                        if (tear)
                            root.tearRequested(chip.modelData.id);
                        else if (to !== from && to >= 0)
                            root.moveRequested(chip.modelData.id, to);
                    }
                }
                onTranslationChanged: {
                    if (active) {
                        const p = chip.mapToItem(root, centroid.position.x, centroid.position.y);
                        root.dragX = p.x;
                        root.dragY = p.y;
                        root.dragTear = Math.abs(translation.y) > root.tearDistance;
                        root.dragTo = Math.max(0, Math.min(root.tabs.length - 1, Math.round((chip.index * root.step + translation.x) / root.step)));
                    }
                }
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
        id: plusBtn

        x: root.leftPad + root.tabs.length * root.step
        anchors.verticalCenter: parent.verticalCenter
        icon: "add"
        type: ButtonBase.Text
        implicitWidth: 34
        implicitHeight: 34
        iconSize: Theme.iconSize.medium
        onClicked: root.newRequested()
    }
}
