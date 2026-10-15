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

    signal newTabRequested
    signal closeTabRequested(string id)
    signal activateTabRequested(string id)
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

    function viewFor(id: string): var {
        for (let i = 0; i < views.count; i++) {
            const v = views.itemAt(i);
            if (v && v.tabId === id)
                return v;
        }
        return null;
    }

    color: Theme.palette.m3surface
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
        sequence: "Ctrl+Tab"
        onActivated: root.activateTabRequested(Tabs.cycle(Tabs.make(root.tabs, root.active), 1).active)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        onActivated: root.activateTabRequested(Tabs.cycle(Tabs.make(root.tabs, root.active), -1).active)
    }

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

    // --- drop preview: another explorer window is being carried over this one -----------------

    Item {
        id: preview

        anchors.fill: parent
        opacity: root.dropPreview ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        // A blurred copy of the contents (GPU renderers); the plain scrim below covers the rest.
        ShaderEffectSource {
            id: snap

            anchors.fill: parent
            sourceItem: body
            live: root.dropPreview
            hideSource: false
            visible: GraphicsInfo.api !== GraphicsInfo.Software
            layer.enabled: visible
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 48
                blur: 1.0
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Theme.palette.m3surface, 0.55)
        }

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacing.small

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
}
