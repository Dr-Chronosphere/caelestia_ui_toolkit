// Fractal Map view, ported to the Caelestia UI toolkit.
//
// Derived from Map.qml in cgranier/fractal-wm (MIT, Copyright (c) 2026 Carlos Granier; see
// LICENSE.fractal-wm). The interaction logic is upstream's; the Omarchy styling was replaced
// with CaelestiaUI.Theme, and everything that talks to Hyprland/Quickshell was moved out into
// shell.qml so this file is pure QtQuick and testable headlessly.
pragma ComponentBehavior: Bound

import QtQuick
import CaelestiaUI
import "Model.js" as Model

// Full-screen scrim plus a card that draws the window tree of a workspace as nested
// rectangles: click a window or container to make it the viewport, right-click for its
// parent, breadcrumb and saved framings on top.
Item {
    id: root

    // --- Inputs (set by the host) -------------------------------------------------
    property var status: null            // parsed ws-<id>.json (already pruned), or null
    property int workspaceId: -1
    property string workspaceLayout: ""
    property bool opened: false
    property bool thumbnails: true
    property bool thumbnailsSupported: false   // host has Quickshell.Wayland screencopy
    property bool closeOnPick: true
    property string notice: ""
    // function(address) -> toplevel handle for ScreencopyView, or null
    property var toplevelFor: function (address) { return null }

    // --- Outputs --------------------------------------------------------------------
    // A layout message for the fractal layout, e.g. "zoom w3" or "show-all".
    signal command(string msg)
    signal dismissRequested
    signal enableRequested
    signal refreshRequested

    // --- State ----------------------------------------------------------------------
    property var rects: []
    property string hoverId: ""          // what the pointer is over
    property string cursorId: ""         // keyboard cursor; follows the pointer, moves with arrows
    property var pickedIds: ({})         // window id -> true, the tiles picked for a "show"
    property int selectedCount: 0
    property bool dragging: false
    property rect marquee: Qt.rect(0, 0, 0, 0)
    property var press: null

    readonly property string layoutName: "lua:fractal"
    readonly property bool isFractal: workspaceLayout === layoutName

    readonly property color background: Theme.palette.m3surfaceContainer
    readonly property color foreground: Theme.palette.m3onSurface
    readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.45)
    readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)
    readonly property color accent: Theme.palette.m3primary
    readonly property color selected: Theme.palette.m3secondaryContainer
    readonly property color selectedText: Theme.palette.m3onSecondaryContainer
    readonly property color borderColour: Theme.palette.m3outlineVariant
    readonly property string fontFamily: Theme.sansFamily

    // --- Lifecycle ------------------------------------------------------------------

    // Reset transient state; the host calls this whenever the map opens.
    function reset() {
        hoverId = ""
        cursorId = ""             // start on the focused window every time the map opens
        clearSelection()
        press = null
        dragging = false
        marquee = Qt.rect(0, 0, 0, 0)
        relayout()                // re-pick the cursor if the data is already here
        Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    }

    function dismiss() { dismissRequested() }

    // --- Commands -------------------------------------------------------------------
    function zoomTo(id) {
        if (!id) return
        command("zoom " + id)
        if (closeOnPick) dismiss()
    }

    // --- Selection: pick several tiles, then show exactly those -------------------------
    function clearSelection() { pickedIds = ({}); selectedCount = 0 }

    function setSelected(ids, on) {
        var next = ({})
        for (var k in pickedIds) next[k] = true
        for (var i = 0; i < ids.length; i++) { if (on) next[ids[i]] = true; else delete next[ids[i]] }
        pickedIds = next
        selectedCount = Object.keys(next).length
    }

    function toggleSelected(id) {
        var ids = Model.windowsUnder(rects, id)
        if (ids.length === 0) return
        var allOn = ids.every(function (w) { return pickedIds[w] === true })
        setSelected(ids, !allOn)
    }

    function applySelection() {
        var ids = Object.keys(pickedIds)
        if (ids.length === 0) return
        command("show " + ids.join(" "))
        clearSelection()
        if (closeOnPick) dismiss()
    }

    // Pointer handling, shared by the mouse layer and tests.
    function pointerPress(x, y, button, shift) {
        press = { x: x, y: y, button: button, shift: shift, id: (Model.hit(rects, x, y) || {}).id || "" }
        dragging = false
    }

    function pointerMove(x, y) {
        if (!press) { hoverId = (Model.hit(rects, x, y) || {}).id || ""; if (hoverId) cursorId = hoverId; return }
        if (!dragging && (Math.abs(x - press.x) > 6 || Math.abs(y - press.y) > 6) && press.button === Qt.LeftButton) dragging = true
        if (dragging) marquee = Qt.rect(press.x, press.y, x - press.x, y - press.y)
        hoverId = (Model.hit(rects, x, y) || {}).id || ""
    }

    function pointerRelease(x, y) {
        if (!press) return
        var p = press
        press = null
        if (dragging) {
            dragging = false
            var ids = Model.windowsIn(rects, { x: p.x, y: p.y, w: x - p.x, h: y - p.y })
            if (!p.shift) clearSelection()
            setSelected(ids, true)
            marquee = Qt.rect(0, 0, 0, 0)
            return
        }
        var id = (Model.hit(rects, x, y) || {}).id || p.id
        if (!id) return
        if (p.button === Qt.RightButton) { zoomTo(Model.parentId(status, id) || id); return }
        if (p.shift) { toggleSelected(id); return }
        if (selectedCount > 0) { toggleSelected(id); return }   // a selection is in progress: plain clicks add to it
        zoomTo(id)
    }

    function relayout() {
        if (!status) { rects = []; return }
        rects = Model.flatten(status, { x: 0, y: 0, w: mapArea.width, h: mapArea.height }, { pad: 6, gap: 3 })
        var stillThere = rects.some(function (r) { return r.id === cursorId })
        if (!stillThere) {
            var focused = rects.filter(function (r) { return r.isWindow && r.focused })[0]
            var anyWin = rects.filter(function (r) { return r.isWindow })[0]
            cursorId = focused ? focused.id : (anyWin ? anyWin.id : "")
        }
    }

    onStatusChanged: relayout()

    function moveCursor(dir) {
        var next = Model.neighbor(rects, cursorId, dir)
        if (next) cursorId = next
    }

    function handleKey(event) { handleKeyCode(event.key, event.modifiers) }

    function handleKeyCode(key, modifiers) {
        var shift = (modifiers & Qt.ShiftModifier) !== 0
        var ctrl = (modifiers & Qt.ControlModifier) !== 0
        if (key === Qt.Key_Escape) { if (selectedCount > 0) clearSelection(); else dismiss(); return }
        if (key === Qt.Key_Return || key === Qt.Key_Enter) { if (selectedCount > 0) applySelection(); else if (cursorId) zoomTo(cursorId); return }
        if (key === Qt.Key_Space) { if (cursorId) toggleSelected(cursorId); return }
        if (key === Qt.Key_Delete || key === Qt.Key_Backspace) { if (cursorId) command("hide " + cursorId); return }
        if (key === Qt.Key_Home) { command("zoom-root"); return }
        if (key === Qt.Key_A && ctrl) { setSelected(rects.filter(function (r) { return r.isWindow }).map(function (r) { return r.id }), true); return }
        if (key >= Qt.Key_1 && key <= Qt.Key_9) { command("frame " + (key - Qt.Key_0)); return }
        if (key === Qt.Key_R) { refreshRequested(); return }
        if (key === Qt.Key_T) { thumbnails = !thumbnails; return }
        // Arrows move the cursor between tiles; with Shift they drive the live view.
        if (key === Qt.Key_Left)  { if (shift) command("back");     else moveCursor("left");  return }
        if (key === Qt.Key_Right) { if (shift) command("forward");  else moveCursor("right"); return }
        if (key === Qt.Key_Up)    { if (shift) command("zoom-out"); else moveCursor("up");    return }
        if (key === Qt.Key_Down)  { if (shift) command("zoom-in");  else moveCursor("down");  return }
        if (key === Qt.Key_Minus) { command("zoom-out"); return }
        if (key === Qt.Key_Equal || key === Qt.Key_Plus) { command("zoom-in"); return }
    }

    // --- Surface --------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.palette.m3scrim, 0.55)
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
    }

    StyledRect {
        id: card

        readonly property int pad: Theme.padding.large

        width: Math.min(Math.round(root.width * 0.78), root.width - 40)
        height: Math.min(header.implicitHeight + 12 + mapHolder.height + footer.implicitHeight + pad * 2 + 12, root.height - 40)
        radius: Theme.rounding.extraLarge
        anchors.centerIn: parent
        color: root.background
        border.width: 1
        border.color: root.borderColour

        MouseArea {
            anchors.fill: parent
            onClicked: keyCatcher.forceActiveFocus()
        }

        Item {
            id: keyCatcher

            anchors.fill: parent
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function (event) { root.handleKey(event); event.accepted = true }
        }

        Column {
            id: body

            anchors.fill: parent
            anchors.margins: card.pad
            spacing: 6

            // Breadcrumb + framings
            Flow {
                id: header

                width: parent.width
                spacing: 6

                Text {
                    text: root.workspaceId >= 0 ? ("workspace " + root.workspaceId) : "workspace"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    height: 26
                    verticalAlignment: Text.AlignVCenter
                }

                Repeater {
                    model: root.status ? root.status.path : []

                    delegate: Rectangle {
                        id: crumbRect

                        required property var modelData
                        required property int index
                        readonly property bool last: !!root.status && crumbRect.index === root.status.path.length - 1

                        height: 26
                        width: crumb.implicitWidth + 18
                        radius: Theme.rounding.small
                        color: crumbRect.last ? root.selected : (crumbArea.containsMouse ? root.faint : "transparent")
                        border.width: 1
                        border.color: crumbRect.last ? root.accent : root.borderColour

                        Text {
                            id: crumb

                            anchors.centerIn: parent
                            text: (crumbRect.index > 0 ? "› " : "") + crumbRect.modelData.name
                            color: crumbRect.last ? root.selectedText : root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: crumbArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.zoomTo(crumbRect.modelData.id)
                        }
                    }
                }

                Item { width: 10; height: 1 }

                Rectangle {
                    visible: root.selectedCount > 0
                    height: 26
                    width: showLabel.implicitWidth + 20
                    radius: Theme.rounding.small
                    color: showArea.containsMouse ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                    border.width: 1
                    border.color: root.accent

                    Text {
                        id: showLabel

                        anchors.centerIn: parent
                        text: "Show " + root.selectedCount + (root.selectedCount === 1 ? " tile" : " tiles") + "  ⏎"
                        color: showArea.containsMouse ? Theme.palette.m3onPrimary : root.accent
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        font.bold: true
                    }
                    MouseArea {
                        id: showArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applySelection()
                    }
                }

                Rectangle {
                    visible: !!(root.status && root.status.selection && root.status.selection.length > 0)
                    height: 26
                    width: allLabel.implicitWidth + 18
                    radius: Theme.rounding.small
                    color: allArea.containsMouse ? root.faint : "transparent"
                    border.width: 1
                    border.color: root.borderColour

                    Text {
                        id: allLabel

                        anchors.centerIn: parent
                        text: "show all"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: allArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.command("show-all"); if (root.closeOnPick) root.dismiss() }
                    }
                }

                Repeater {
                    model: root.status ? root.status.framings : []

                    delegate: Rectangle {
                        id: frameRect

                        required property var modelData

                        height: 26
                        width: frameLabel.implicitWidth + 18
                        radius: 13
                        color: frameArea.containsMouse ? root.faint : "transparent"
                        border.width: 1
                        border.color: root.accent

                        Text {
                            id: frameLabel

                            anchors.centerIn: parent
                            text: "⌖ " + frameRect.modelData.name
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: frameArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.command("frame " + frameRect.modelData.name); if (root.closeOnPick) root.dismiss() }
                        }
                    }
                }
            }

            // The map
            Item {
                id: mapHolder

                width: parent.width
                height: Math.round(width * (root.height / Math.max(1, root.width)) * 0.92)

                Item {
                    id: mapArea

                    anchors.fill: parent
                    onWidthChanged: root.relayout()
                    onHeightChanged: root.relayout()

                    Repeater {
                        model: root.rects

                        delegate: Rectangle {
                            id: tile

                            required property var modelData
                            readonly property bool hovered: root.cursorId === modelData.id
                            readonly property bool isWin: modelData.isWindow
                            readonly property bool picked: root.pickedIds[modelData.id] === true
                            readonly property bool shown: modelData.inViewport && modelData.visible
                            // Caption bar: name, title and state, like a title bar.
                            readonly property bool captioned: isWin && width > 70 && height > 48
                            readonly property int captionH: captioned ? 20 : 0

                            x: modelData.x; y: modelData.y; width: modelData.w; height: modelData.h
                            radius: isWin ? 4 : Theme.rounding.small
                            color: isWin
                                ? (picked ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                                   : modelData.focused ? root.selected
                                   : (hovered ? root.faint : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, shown ? 0.05 : 0.02)))
                                : (hovered ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08) : "transparent")
                            border.width: picked ? 2 : (modelData.viewport ? 2 : (hovered ? 2 : 1))
                            border.color: (picked || modelData.viewport || hovered) ? root.accent : (shown ? root.borderColour : root.faint)
                            opacity: shown ? 1.0 : 0.8

                            Rectangle {
                                id: caption

                                visible: tile.captioned
                                x: 1; y: 1
                                width: parent.width - 2
                                height: tile.captionH
                                radius: 3
                                color: tile.picked ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.30)
                                     : tile.modelData.focused ? root.selected
                                     : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, tile.modelData.visible ? 0.08 : 0.04)

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    Text {
                                        id: nameText

                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tile.modelData.isDesktop ? "desktop" : tile.modelData.name
                                        color: tile.modelData.visible ? root.foreground : root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: 11
                                        font.bold: true
                                        elide: Text.ElideRight
                                        width: Math.min(implicitWidth, caption.width * 0.45)
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tile.modelData.title !== tile.modelData.name ? tile.modelData.title : ""
                                        color: root.dim
                                        font.family: root.fontFamily
                                        font.pixelSize: 10
                                        elide: Text.ElideMiddle
                                        width: Math.max(0, caption.width - 12 - nameText.width - stateTag.width - 18)
                                    }
                                }
                                Text {
                                    id: stateTag

                                    anchors.right: parent.right
                                    anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: tile.picked ? "selected" : (!tile.modelData.visible ? "hidden" : (tile.modelData.focused ? "focused" : ""))
                                    color: tile.picked ? root.accent : (!tile.modelData.visible ? root.dim : root.selectedText)
                                    font.family: root.fontFamily
                                    font.pixelSize: 9
                                }
                            }

                            // Live thumbnail of the window, below the caption (needs screencopy).
                            Loader {
                                id: thumb

                                readonly property bool wanted: tile.captioned && root.thumbnails && root.thumbnailsSupported

                                active: wanted
                                source: "Thumbnail.qml"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: caption.bottom
                                anchors.bottom: parent.bottom
                                anchors.margins: 3
                                visible: item && item.captureSource !== null && item.hasContent
                                opacity: tile.modelData.visible ? 1.0 : 0.6
                            }
                            // Capture only while the thumbnail can actually show.
                            Binding {
                                target: thumb.item
                                property: "captureSource"
                                value: thumb.wanted ? root.toplevelFor(tile.modelData.address) : null
                                when: thumb.item !== null
                            }
                            Binding {
                                target: thumb.item
                                property: "live"
                                value: root.opened && thumb.wanted
                                when: thumb.item !== null
                            }

                            // Container tag, top-left inside the pad
                            Text {
                                visible: !tile.isWin && tile.width > 40 && tile.height > 16
                                x: 4; y: 0
                                text: tile.modelData.kind + (tile.modelData.framing ? "  ⌖ " + tile.modelData.framing : "")
                                color: tile.modelData.viewport ? root.accent : root.dim
                                font.family: root.fontFamily
                                font.pixelSize: 9
                            }

                            // Small tiles (no caption): centred name only
                            Text {
                                visible: tile.isWin && !tile.captioned && tile.width > 14 && tile.height > 10
                                anchors.centerIn: parent
                                width: parent.width - 6
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: tile.modelData.isDesktop ? "desktop" : Model.label(tile.modelData, Math.max(3, Math.floor(tile.width / Math.max(6, font.pixelSize * 0.6))))
                                color: tile.modelData.focused ? root.selectedText : (tile.modelData.visible ? root.foreground : root.dim)
                                font.family: root.fontFamily
                                font.pixelSize: Model.fontFor(tile.modelData, 9, 14)
                            }
                        }
                    }

                    // One pointer layer over the whole map: hover, click, shift-click, drag.
                    MouseArea {
                        anchors.fill: parent
                        z: 10
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: root.hoverId !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: function (mouse) { root.pointerPress(mouse.x, mouse.y, mouse.button, (mouse.modifiers & Qt.ShiftModifier) !== 0) }
                        onPositionChanged: function (mouse) { root.pointerMove(mouse.x, mouse.y) }
                        onReleased: function (mouse) { root.pointerRelease(mouse.x, mouse.y) }
                        onExited: root.hoverId = ""
                    }

                    Rectangle {
                        visible: root.dragging
                        z: 9
                        x: Math.min(root.marquee.x, root.marquee.x + root.marquee.width)
                        y: Math.min(root.marquee.y, root.marquee.y + root.marquee.height)
                        width: Math.abs(root.marquee.width)
                        height: Math.abs(root.marquee.height)
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
                        border.width: 1
                        border.color: root.accent
                    }

                    // Empty / not-fractal states
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        visible: !root.isFractal || !root.status || root.status.windows === 0
                        width: parent.width * 0.7

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: !root.isFractal
                                ? ("Workspace " + root.workspaceId + " uses " + (root.workspaceLayout || "another layout") + ", not the fractal layout.")
                                : "No tree yet for this workspace. Open a window and the map fills in."
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: 14
                        }
                        Rectangle {
                            visible: !root.isFractal && root.workspaceId >= 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: enableLabel.implicitWidth + 28
                            height: 32
                            radius: Theme.rounding.small
                            color: enableArea.containsMouse ? root.selected : "transparent"
                            border.width: 1
                            border.color: root.accent

                            Text {
                                id: enableLabel

                                anchors.centerIn: parent
                                text: "Use the fractal layout here"
                                color: root.accent
                                font.family: root.fontFamily
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: enableArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.enableRequested()
                            }
                        }
                    }
                }
            }

            Text {
                id: footer

                width: parent.width
                wrapMode: Text.WordWrap
                text: root.notice !== "" ? root.notice
                    : root.selectedCount > 0
                      ? (root.selectedCount + " selected  ·  click adds or removes tiles  ·  ⏎ or Show: view only these  ·  Esc: clear")
                      : "click / ⏎: zoom there  ·  arrows: move  ·  space, shift-click or drag: select tiles to show together  ·  right-click: parent  ·  ⌫: hide  ·  shift+↑↓: zoom out / in  ·  shift+←→: back / forward  ·  Home: overview  ·  1–9: framings  ·  T: thumbnails  ·  Esc"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: 11
            }
        }
    }
}
