pragma Singleton

import QtQuick

// Central theme for Caelestia-styled apps.
//
// Colours come from the same `scheme.json` that caelestia-shell watches, so apps
// follow wallpaper/scheme changes live. Without the file (or without Quickshell,
// e.g. in tests) the shell's default dark palette is used.
//
// Sizing/animation tokens mirror the shell's defaults. They are plain constants
// here because the shell's own token system lives in its compiled plugin.
QtObject {
    id: root

    // --- Scheme source ------------------------------------------------------

    // Watch scheme.json via Quickshell. Set before first use to disable.
    property bool watch: true
    // Override the scheme file location. Empty = $XDG_STATE_HOME/caelestia/scheme.json
    property string schemePath: ""

    property string schemeName: "default"
    property string flavour: ""
    property bool light: false

    // Emitted after a scheme was applied (from file or applyScheme()).
    signal schemeApplied

    // Apply the contents of a caelestia scheme.json:
    //   { "name": "...", "flavour": "...", "mode": "dark"|"light",
    //     "colours": { "primary": "ffb0ca", ... } }   (hex without '#')
    // Returns true on success.
    function applyScheme(data: string): bool {
        let scheme;
        try {
            scheme = JSON.parse(data);
        } catch (e) {
            console.warn("CaelestiaUI: invalid scheme JSON:", e);
            return false;
        }
        if (!scheme || typeof scheme.colours !== "object")
            return false;

        root.schemeName = scheme.name ?? "";
        root.flavour = scheme.flavour ?? "";
        root.light = scheme.mode === "light";

        for (const [name, hex] of Object.entries(scheme.colours)) {
            if (name.startsWith("term"))
                continue;
            const prop = `m3${name}`;
            if (palette.hasOwnProperty(prop))
                palette[prop] = `#${hex}`;
        }
        root.schemeApplied();
        return true;
    }

    // Pick a readable foreground for an arbitrary background.
    function on(c: color): color {
        return c.hslLightness < 0.5 ? Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1) : Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    Component.onCompleted: {
        if (!watch)
            return;
        const comp = Qt.createComponent("SchemeFile.qml");
        if (comp.status !== Component.Ready) {
            console.warn("CaelestiaUI: scheme watching unavailable (Quickshell not loaded?), using default palette:", comp.errorString());
            return;
        }
        comp.createObject(root, {
            "theme": root
        });
    }

    // --- Token groups (typed so tooling can check member access) ----------

    component PaletteGroup: QtObject {
        property color m3primary_paletteKeyColor: "#a8627b"
        property color m3secondary_paletteKeyColor: "#8e6f78"
        property color m3tertiary_paletteKeyColor: "#986e4c"
        property color m3neutral_paletteKeyColor: "#807477"
        property color m3neutral_variant_paletteKeyColor: "#837377"
        property color m3background: "#191114"
        property color m3onBackground: "#efdfe2"
        property color m3surface: "#191114"
        property color m3surfaceDim: "#191114"
        property color m3surfaceBright: "#403739"
        property color m3surfaceContainerLowest: "#130c0e"
        property color m3surfaceContainerLow: "#22191c"
        property color m3surfaceContainer: "#261d20"
        property color m3surfaceContainerHigh: "#31282a"
        property color m3surfaceContainerHighest: "#3c3235"
        property color m3onSurface: "#efdfe2"
        property color m3surfaceVariant: "#514347"
        property color m3onSurfaceVariant: "#d5c2c6"
        property color m3inverseSurface: "#efdfe2"
        property color m3inverseOnSurface: "#372e30"
        property color m3outline: "#9e8c91"
        property color m3outlineVariant: "#514347"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#ffb0ca"
        property color m3primary: "#ffb0ca"
        property color m3onPrimary: "#541d34"
        property color m3primaryContainer: "#6f334a"
        property color m3onPrimaryContainer: "#ffd9e3"
        property color m3inversePrimary: "#8b4a62"
        property color m3secondary: "#e2bdc7"
        property color m3onSecondary: "#422932"
        property color m3secondaryContainer: "#5a3f48"
        property color m3onSecondaryContainer: "#ffd9e3"
        property color m3tertiary: "#f0bc95"
        property color m3onTertiary: "#48290c"
        property color m3tertiaryContainer: "#b58763"
        property color m3onTertiaryContainer: "#000000"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color m3primaryFixed: "#ffd9e3"
        property color m3primaryFixedDim: "#ffb0ca"
        property color m3onPrimaryFixed: "#39071f"
        property color m3onPrimaryFixedVariant: "#6f334a"
        property color m3secondaryFixed: "#ffd9e3"
        property color m3secondaryFixedDim: "#e2bdc7"
        property color m3onSecondaryFixed: "#2b151d"
        property color m3onSecondaryFixedVariant: "#5a3f48"
        property color m3tertiaryFixed: "#ffdcc3"
        property color m3tertiaryFixedDim: "#f0bc95"
        property color m3onTertiaryFixed: "#2f1500"
        property color m3onTertiaryFixedVariant: "#623f21"
    }

    component RoundingGroup: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
        readonly property int full: 9999
    }

    component SpacingGroup: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
    }

    component PaddingGroup: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
    }

    component HeadlineGroup: QtObject {
        readonly property font large: Theme._f(Theme.sansFamily, 32, Font.Medium)
        readonly property font medium: Theme._f(Theme.sansFamily, 28, Font.Medium)
        readonly property font small: Theme._f(Theme.sansFamily, 24, Font.Medium)
    }

    component TitleGroup: QtObject {
        readonly property font large: Theme._f(Theme.sansFamily, 22, Font.Medium)
        readonly property font medium: Theme._f(Theme.sansFamily, 16, Font.Medium)
        readonly property font small: Theme._f(Theme.sansFamily, 14, Font.Medium)
    }

    component BodyGroup: QtObject {
        readonly property font large: Theme._f(Theme.sansFamily, 16, Font.Normal)
        readonly property font medium: Theme._f(Theme.sansFamily, 14, Font.Normal)
        readonly property font small: Theme._f(Theme.sansFamily, 12, Font.Normal)
    }

    component LabelGroup: QtObject {
        readonly property font large: Theme._f(Theme.sansFamily, 14, Font.Medium)
        readonly property font medium: Theme._f(Theme.sansFamily, 12, Font.Medium)
        readonly property font small: Theme._f(Theme.sansFamily, 11, Font.Normal)
    }

    component MonoGroup: QtObject {
        readonly property font large: Theme._f(Theme.monoFamily, 16, Font.Normal)
        readonly property font medium: Theme._f(Theme.monoFamily, 14, Font.Normal)
        readonly property font small: Theme._f(Theme.monoFamily, 12, Font.Normal)
    }

    component IconSizeGroup: QtObject {
        readonly property int small: 15
        readonly property int medium: 18
        readonly property int large: 24
        readonly property int extraLarge: 36
    }

    component CurvesGroup: QtObject {
        readonly property var emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property var emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        readonly property var emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property var standard: [0.2, 0, 0, 1, 1, 1]
        readonly property var standardAccel: [0.3, 0, 1, 1, 1, 1]
        readonly property var standardDecel: [0, 0, 0, 1, 1, 1]
        readonly property var expressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1, 1]
        readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
        readonly property var expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]
        readonly property var expressiveFastEffects: [0.31, 0.94, 0.34, 1, 1, 1]
        readonly property var expressiveDefaultEffects: [0.34, 0.8, 0.34, 1, 1, 1]
        readonly property var expressiveSlowEffects: [0.34, 0.88, 0.34, 1, 1, 1]
    }

    component DurationsGroup: QtObject {
        readonly property int small: 200
        readonly property int normal: 400
        readonly property int large: 600
        readonly property int extraLarge: 1000
        readonly property int expressiveFastSpatial: 350
        readonly property int expressiveDefaultSpatial: 500
        readonly property int expressiveSlowSpatial: 650
        readonly property int expressiveFastEffects: 150
        readonly property int expressiveDefaultEffects: 200
        readonly property int expressiveSlowEffects: 300
    }

    // --- Palette (Material 3, defaults = caelestia dark) ---------------------

    readonly property PaletteGroup palette: PaletteGroup {}

    // --- Tokens (shell defaults) --------------------------------------------

    readonly property RoundingGroup rounding: RoundingGroup {}

    readonly property SpacingGroup spacing: SpacingGroup {}

    // Same scale as spacing in the shell; separate object so apps can diverge.
    readonly property PaddingGroup padding: PaddingGroup {}

    // --- Typography ----------------------------------------------------------

    readonly property string sansFamily: "GoogleSansFlex"
    readonly property string monoFamily: "CaskaydiaCove NF"
    readonly property string iconFamily: "Material Symbols Rounded"

    function _f(family: string, size: int, weight: int): font {
        return Qt.font({
            "family": family,
            "pointSize": size,
            "weight": weight
        });
    }

    readonly property HeadlineGroup headline: HeadlineGroup {}
    readonly property TitleGroup title: TitleGroup {}
    readonly property BodyGroup body: BodyGroup {}
    readonly property LabelGroup label: LabelGroup {}
    readonly property MonoGroup mono: MonoGroup {}

    // Icon sizes in points (24/1.33 etc., as in the shell).
    readonly property IconSizeGroup iconSize: IconSizeGroup {}

    // --- Animation -----------------------------------------------------------

    readonly property CurvesGroup curves: CurvesGroup {}

    readonly property DurationsGroup durations: DurationsGroup {}
}
