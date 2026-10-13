import QtQuick
import Qt.labs.folderlistmodel
import CaelestiaUI
import "logic/Files.js" as Files

// Caelestia file manager UI. Pure QtQuick + Qt.labs.folderlistmodel, so it runs anywhere
// the toolkit does; opening a file is delegated to the host via `openRequested`.
Rectangle {
    id: root

    required property string home

    property string path: home
    property var backStack: []
    property var forwardStack: []
    property string viewMode: "grid"    // "grid" | "list"
    property bool showHidden: false
    property int sortField: FolderListModel.Name
    property bool sortReversed: false
    property int selectedIndex: -1

    readonly property alias model: folder
    readonly property alias searchField: search
    readonly property string query: search.text.trim()
    readonly property int count: folder.count
    readonly property string folderName: Files.baseName(path) === Files.baseName(home) && path === home ? "Home" : Files.baseName(path)
    readonly property string sortLabel: ["", "Name", "Modified", "Size", "Type"][sortField] ?? "Name"

    // Emitted when the user opens a (non-folder) file.
    signal openRequested(string path)

    // Navigate to `target`. History is recorded unless `fromHistory` (back/forward).
    // Note: QML coerces a missing `bool` argument to false, so the flag must default to false.
    function go(target: string, fromHistory: bool): void {
        if (target === path)
            return;
        if (!fromHistory) {
            backStack = [...backStack, path];
            forwardStack = [];
        }
        search.text = "";
        selectedIndex = -1;
        path = target;
    }

    function goBack(): void {
        if (backStack.length === 0)
            return;
        const prev = backStack[backStack.length - 1];
        backStack = backStack.slice(0, -1);
        forwardStack = [...forwardStack, path];
        go(prev, true);
    }

    function goForward(): void {
        if (forwardStack.length === 0)
            return;
        const next = forwardStack[forwardStack.length - 1];
        forwardStack = forwardStack.slice(0, -1);
        backStack = [...backStack, path];
        go(next, true);
    }

    function goUp(): void {
        go(Files.parentOf(path));
    }

    function activate(index: int): void {
        if (index < 0 || index >= folder.count)
            return;
        const p = folder.get(index, "filePath");
        if (folder.get(index, "fileIsDir"))
            go(p);
        else
            openRequested(p);
    }

    function cycleSort(): void {
        // Name -> Modified -> Size -> Type -> Name
        const order = [FolderListModel.Name, FolderListModel.Time, FolderListModel.Size, FolderListModel.Type];
        sortField = order[(order.indexOf(sortField) + 1) % order.length];
    }

    function selectedInfo(): var {
        if (selectedIndex < 0 || selectedIndex >= folder.count)
            return null;
        return {
            "name": folder.get(selectedIndex, "fileName"),
            "isDir": folder.get(selectedIndex, "fileIsDir"),
            "size": folder.get(selectedIndex, "fileSize")
        };
    }

    color: Theme.palette.m3surface
    implicitWidth: 960
    implicitHeight: 640
    focus: true

    FolderListModel {
        id: folder

        folder: Files.toUrl(root.path)
        // Qt's name filters only apply to files, so folders are hidden while searching.
        showDirs: root.query.length === 0
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: root.showHidden
        caseSensitive: false
        sortField: root.sortField
        sortReversed: root.sortReversed
        nameFilters: root.query.length > 0 ? [`*${root.query}*`] : []
    }

    // Which standard places exist in $HOME.
    property var places: [{
            "label": "Home",
            "icon": "home",
            "path": home
        }]

    FolderListModel {
        id: homeScan

        folder: Files.toUrl(root.home)
        showFiles: false
        showHidden: false
        onStatusChanged: root.updatePlaces()
        onCountChanged: root.updatePlaces()
    }

    function updatePlaces(): void {
        const names = [];
        for (let i = 0; i < homeScan.count; i++)
            names.push(homeScan.get(i, "fileName"));
        places = Files.places(home, names);
    }

    Shortcut {
        sequence: "Alt+Left"
        onActivated: root.goBack()
    }
    Shortcut {
        sequence: "Alt+Right"
        onActivated: root.goForward()
    }
    Shortcut {
        sequence: "Alt+Up"
        onActivated: root.goUp()
    }
    Shortcut {
        sequence: "Ctrl+F"
        onActivated: search.input.forceActiveFocus()
    }
    Shortcut {
        sequence: "Ctrl+H"
        onActivated: root.showHidden = !root.showHidden
    }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (search.text.length > 0)
                search.text = "";
            root.forceActiveFocus();
        }
    }

    // --- Top bar -----------------------------------------------------------------

    Item {
        id: topBar

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64

        Row {
            id: nav

            anchors.left: parent.left
            anchors.leftMargin: Theme.padding.medium
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacing.extraSmall

            IconButton {
                icon: "arrow_back"
                type: ButtonBase.Text
                disabled: root.backStack.length === 0
                onClicked: root.goBack()
            }
            IconButton {
                icon: "arrow_forward"
                type: ButtonBase.Text
                disabled: root.forwardStack.length === 0
                onClicked: root.goForward()
            }
            IconButton {
                icon: "arrow_upward"
                type: ButtonBase.Text
                disabled: root.path === "/"
                onClicked: root.goUp()
            }
        }

        PathBar {
            anchors.left: nav.right
            anchors.leftMargin: Theme.spacing.medium
            anchors.right: tools.left
            anchors.rightMargin: Theme.spacing.medium
            anchors.verticalCenter: parent.verticalCenter
            crumbs: Files.breadcrumb(root.path, root.home)
            onActivated: p => root.go(p)
        }

        Row {
            id: tools

            anchors.right: parent.right
            anchors.rightMargin: Theme.padding.medium
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacing.small

            StyledTextField {
                id: search

                width: 200
                height: 36
                icon: "search"
                placeholder: "Search folder"
            }
            IconButton {
                icon: root.viewMode === "grid" ? "view_list" : "grid_view"
                type: ButtonBase.Text
                onClicked: root.viewMode = root.viewMode === "grid" ? "list" : "grid"
            }
            IconButton {
                icon: "sort"
                type: ButtonBase.Text
                onClicked: root.cycleSort()
            }
            IconButton {
                icon: root.showHidden ? "visibility" : "visibility_off"
                type: ButtonBase.Text
                onClicked: root.showHidden = !root.showHidden
            }
        }
    }

    // --- Body -------------------------------------------------------------------

    PlacesSidebar {
        id: sidebar

        anchors.top: topBar.bottom
        anchors.bottom: statusBar.top
        anchors.left: parent.left
        places: root.places
        current: root.path
        onActivated: p => root.go(p)
    }

    StyledRect {
        id: content

        anchors.top: topBar.bottom
        anchors.bottom: statusBar.top
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.rightMargin: Theme.padding.medium
        radius: Theme.rounding.large
        color: Theme.palette.m3surfaceContainerLow
        clip: true

        GridView {
            id: grid

            readonly property int perRow: Math.max(1, Math.floor(width / 128))

            visible: root.viewMode === "grid"
            anchors.fill: parent
            anchors.margins: Theme.padding.medium
            model: folder
            cellWidth: Math.floor(width / perRow)
            cellHeight: 132
            clip: true
            keyNavigationEnabled: true
            focus: visible
            currentIndex: root.selectedIndex
            onCurrentIndexChanged: root.selectedIndex = currentIndex
            boundsBehavior: Flickable.StopAtBounds

            Keys.onReturnPressed: root.activate(currentIndex)
            Keys.onEnterPressed: root.activate(currentIndex)
            Keys.onBackPressed: root.goUp()

            delegate: FileTile {
                required property int index

                width: grid.cellWidth
                height: grid.cellHeight
                selected: root.selectedIndex === index
                onClicked: {
                    root.selectedIndex = index;
                    grid.forceActiveFocus();
                }
                onActivated: root.activate(index)
            }
        }

        ListView {
            id: list

            visible: root.viewMode === "list"
            anchors.fill: parent
            anchors.margins: Theme.padding.medium
            model: folder
            spacing: 2
            clip: true
            keyNavigationEnabled: true
            focus: visible
            currentIndex: root.selectedIndex
            onCurrentIndexChanged: root.selectedIndex = currentIndex
            boundsBehavior: Flickable.StopAtBounds

            Keys.onReturnPressed: root.activate(currentIndex)
            Keys.onEnterPressed: root.activate(currentIndex)
            Keys.onBackPressed: root.goUp()

            delegate: FileRow {
                required property int index

                width: list.width
                selected: root.selectedIndex === index
                onClicked: {
                    root.selectedIndex = index;
                    list.forceActiveFocus();
                }
                onActivated: root.activate(index)
            }
        }

        StyledText {
            visible: folder.count === 0
            anchors.centerIn: parent
            text: root.query.length > 0 ? `No files match "${root.query}"` : "This folder is empty"
            color: Theme.palette.m3onSurfaceVariant
            font: Theme.body.large
        }
    }

    // --- Status bar ---------------------------------------------------------------

    Item {
        id: statusBar

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 36

        StyledText {
            anchors.left: parent.left
            anchors.leftMargin: Theme.padding.large
            anchors.verticalCenter: parent.verticalCenter
            text: root.query.length > 0 ? Files.plural(folder.count, "file", "files") + " found (folders hidden)" : Files.plural(folder.count, "item", "items")
            color: Theme.palette.m3onSurfaceVariant
        }

        StyledText {
            anchors.right: parent.right
            anchors.rightMargin: Theme.padding.large
            anchors.verticalCenter: parent.verticalCenter
            readonly property var sel: root.selectedInfo()
            text: sel ? `${sel.name} · ${sel.isDir ? "Folder" : Files.humanSize(sel.size)}` : `${root.folderName} · sorted by ${root.sortLabel.toLowerCase()}`
            color: Theme.palette.m3onSurfaceVariant
        }
    }
}
