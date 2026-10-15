import QtQuick
import QtQuick.Effects
import CaelestiaUI
import "logic/Tabs.js" as Tabs

// One explorer window's contents: a tab strip and one FilesView per tab. The host owns the tab
// list and each tab's saved state (so tabs can move between windows); this component shows them.
//
//   tabs    ordered tab ids          active   the shown tab's id
//   states  { tabId: snapshot }      home     $HOME
//
// While another explorer window is carried over this one, `dropPreview` blurs the contents and
// offers to open that window's tabs here.
Rectangle {
    id: root

    required property string home
    property var tabs: []
    property string active
    property var states: ({})
    property bool dropPreview: false
    // Window translucency: 1 = opaque. The compositor's blur (a Hyprland window rule) shows through.
    property real surfaceAlpha: 1

    signal newTabRequested
    signal closeTabRequested(string id)
    signal activateTabRequested(string id)
    signal moveTabRequested(string id, int to)
    signal tearTabRequested(string id)
    // While a tab is being torn out: where the pointer is (window coordinates) and a picture of the
    // tab, so the host can draw the miniature in a surface that may leave this window.
    signal tearUpdated(var info)
    // Draw the miniature inside this window too (a host with its own overlay turns this off).
    property bool localGhost: true
    property url tearPicture
    signal stateUpdated(string id, var snapshot)
    signal openRequested(string path)

    // Active tab's current snapshot-derived title pieces, for the window title.
    readonly property var labels: Tabs.labels(tabs.map(id => ({
                    "id": id,
                    "path": (states[id] && states[id].path) ? states[id].path : home
                })), home)
    readonly property string activeLabel: {
        for (const l of labels) {
            if (l.id === active)
                return l.label;
        }
        return "";
    }

    readonly property alias tabBar: bar

    function publishTear(): void {
        tearUpdated({
            "on": bar.tearing,
            "x": bar.dragX,
            "y": bar.dragY,
            "label": activeLabel,
            "picture": String(tearPicture),
            "w": ghost.miniW,
            "h": ghost.miniH
        });
    }

    Connections {
        target: bar

        function onTearingChanged(): void {
            if (bar.tearing) {
                const v = root.viewFor(bar.dragTabId);
                if (v)
                    v.grabToImage(r => {
                        root.tearPicture = r.url;
                        root.publishTear();
                    }, Qt.size(Math.round(ghost.miniW * 2), Math.round(ghost.miniH * 2)));
            } else {
                root.tearPicture = "";
            }
            root.publishTear();
        }
        function onDragXChanged(): void {
            if (bar.tearing)
                root.publishTear();
        }
        function onDragYChanged(): void {
            if (bar.tearing)
                root.publishTear();
        }
    }

    function viewFor(id: string): var {
        for (let i = 0; i < views.count; i++) {
            const v = views.itemAt(i);
            if (v && v.tabId === id)
                return v;
        }
        return null;
    }

    color: Qt.alpha(Theme.palette.m3surface, surfaceAlpha)
    implicitWidth: 960
    implicitHeight: 680

    Shortcut {
        sequence: "Ctrl+T"
        onActivated: root.newTabRequested()
    }
    Shortcut {
        sequence: "Ctrl+W"
        onActivated: root.closeTabRequested(root.active)
    }
    Shortcut {
        sequence: "Ctrl+Shift+PgUp"
        onActivated: root.moveTabRequested(root.active, Math.max(0, root.tabs.indexOf(root.active) - 1))
    }
    Shortcut {
        sequence: "Ctrl+Shift+PgDown"
        onActivated: root.moveTabRequested(root.active, Math.min(root.tabs.length - 1, root.tabs.indexOf(root.active) + 1))
    }
    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: root.activateTabRequested(Tabs.cycle(Tabs.make(root.tabs, root.active), 1).active)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        onActivated: root.activateTabRequested(Tabs.cycle(Tabs.make(root.tabs, root.active), -1).active)
    }

    // Everything the preview blurs: the tab strip and the views, in one item so the blurred copy
    // lines up with the real thing exactly.
    Item {
        id: content

        anchors.fill: parent

        TabBar {
            id: bar

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            tabs: root.labels
            active: root.active
            onActivated: id => root.activateTabRequested(id)
            onCloseRequested: id => root.closeTabRequested(id)
            onNewRequested: root.newTabRequested()
            onMoveRequested: (id, to) => root.moveTabRequested(id, to)
            onTearRequested: id => root.tearTabRequested(id)
        }

        Item {
            id: body

            anchors.top: bar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right

            Repeater {
                id: views

                model: root.tabs

                delegate: FilesView {
                    id: view

                    required property string modelData
                    readonly property string tabId: modelData
                    property bool restoring: true

                    anchors.fill: parent
                    home: root.home
                    surfaceAlpha: root.surfaceAlpha
                    visible: modelData === root.active
                    focus: visible
                    onOpenRequested: p => root.openRequested(p)
                    // Skip the churn while the saved state is being applied.
                    onViewStateChanged: {
                        if (!restoring)
                            root.stateUpdated(modelData, snapshot());
                    }
                    Component.onCompleted: {
                        restore(root.states[modelData]);
                        restoring = false;
                    }
                }
            }
        }

    }

    // --- drop preview: another explorer window is being carried over this one -----------------

    Item {
        id: preview

        // 0..1, eased with the shell's curve: the blur, the scrim and then the label come up in turn.
        property real level: root.dropPreview ? 1 : 0

        Behavior on level {
            Anim {
                type: Anim.SlowEffects
                duration: root.dropPreview ? 520 : 320
            }
        }

        anchors.fill: parent
        visible: level > 0.001

        // A blurred copy of the whole window content (GPU renderers); the scrim covers the rest.
        ShaderEffectSource {
            id: snap

            anchors.fill: parent
            sourceItem: content
            live: root.dropPreview
            hideSource: false
            visible: GraphicsInfo.api !== GraphicsInfo.Software
            opacity: Math.min(1, preview.level * 1.6)
            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 48
                blur: preview.level
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.palette.m3surface, 0.5 * preview.level)
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacing.small
            opacity: Math.max(0, (preview.level - 0.4) / 0.6)
            scale: 0.9 + 0.1 * Math.max(0, (preview.level - 0.4) / 0.6)

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "tab"
                iconSize: Theme.iconSize.extraLarge
                color: Theme.palette.m3primary
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Drop to open as tabs here"
                color: Theme.palette.m3onSurface
                font: Theme.body.large
            }
        }
    }

    // --- miniature of a tab being torn out ---------------------------------------------------
    // Dragging a tab off the strip turns it into a small copy of its window that follows the pointer,
    // so you can see what you are carrying. It grows out of the chip's size.

    Item {
        id: ghost

        readonly property real miniW: Math.min(320, root.width * 0.4)
        readonly property real miniH: miniW * body.height / Math.max(1, body.width)
        // 0..1: the chip becoming the window.
        property real grow: bar.tearing ? 1 : 0

        Behavior on grow {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        z: 100
        visible: root.localGhost && grow > 0.001
        width: bar.chipWidth + (miniW - bar.chipWidth) * grow
        height: 34 + (miniH - 34) * grow
        x: bar.dragX - width / 2
        y: bar.dragY - 17 * (1 - grow) - 14 * grow
        opacity: Math.min(1, grow * 2)

        Item {
            anchors.fill: parent

            // A picture of the tab's contents on GPU renderers.
            ShaderEffectSource {
                id: tabShot

                anchors.fill: parent
                sourceItem: root.viewFor(bar.dragTabId)
                live: ghost.visible
                visible: GraphicsInfo.api !== GraphicsInfo.Software && sourceItem !== null
                layer.enabled: visible
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: ghostMask
                }
            }

            // Without that: the tab's name and icon on a card.
            Rectangle {
                anchors.fill: parent
                visible: !tabShot.visible
                radius: Theme.rounding.medium
                color: Theme.palette.m3surfaceContainerHigh

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spacing.small

                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "folder"
                        iconSize: Theme.iconSize.extraLarge
                        color: Theme.palette.m3primary
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.activeLabel
                        color: Theme.palette.m3onSurface
                    }
                }
            }

            Rectangle {
                id: ghostMask

                anchors.fill: parent
                radius: Theme.rounding.medium
                visible: false
                layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            }

            // Window-ish frame.
            Rectangle {
                anchors.fill: parent
                radius: Theme.rounding.medium
                color: "transparent"
                border.width: 2
                border.color: Theme.palette.m3primary
            }
        }
    }
}
