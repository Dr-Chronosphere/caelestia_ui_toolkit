import QtQuick

// Shared behaviour for buttons: colour roles by type, optional toggle state.
StyledRect {
    id: root

    enum Type {
        Filled,
        Tonal,
        Text
    }

    property int type: ButtonBase.Filled
    property bool toggle
    property bool checked
    property bool disabled

    signal clicked

    readonly property bool _on: toggle && checked

    // Container/content colours for the current type and toggle state.
    readonly property color containerColour: {
        if (disabled)
            return type === ButtonBase.Text ? "transparent" : Qt.alpha(Theme.palette.m3onSurface, 0.12);
        switch (type) {
        case ButtonBase.Filled:
            return (!toggle || checked) ? Theme.palette.m3primary : Theme.palette.m3surfaceContainerHighest;
        case ButtonBase.Tonal:
            return _on ? Theme.palette.m3secondary : Theme.palette.m3secondaryContainer;
        }
        return "transparent";
    }
    readonly property color contentColour: {
        if (disabled)
            return Qt.alpha(Theme.palette.m3onSurface, 0.38);
        switch (type) {
        case ButtonBase.Filled:
            return (!toggle || checked) ? Theme.palette.m3onPrimary : Theme.palette.m3onSurfaceVariant;
        case ButtonBase.Tonal:
            return _on ? Theme.palette.m3onSecondary : Theme.palette.m3onSecondaryContainer;
        }
        return Theme.palette.m3primary;
    }

    color: containerColour
    radius: Theme.rounding.full

    StateLayer {
        color: root.contentColour
        disabled: root.disabled
        onClicked: {
            if (root.toggle)
                root.checked = !root.checked;
            root.clicked();
        }
    }
}
