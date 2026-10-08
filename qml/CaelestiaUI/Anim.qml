import QtQuick

// NumberAnimation using the shell's Material 3 expressive timing.
NumberAnimation {
    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial,
        FastEffects,
        DefaultEffects,
        SlowEffects
    }

    // Spatial: movement/size (overshoots). Effects: colour/opacity (no overshoot).
    property int type: Anim.DefaultSpatial

    duration: {
        switch (type) {
        case Anim.FastSpatial:
            return Theme.durations.expressiveFastSpatial;
        case Anim.DefaultSpatial:
            return Theme.durations.expressiveDefaultSpatial;
        case Anim.SlowSpatial:
            return Theme.durations.expressiveSlowSpatial;
        case Anim.FastEffects:
            return Theme.durations.expressiveFastEffects;
        case Anim.DefaultEffects:
            return Theme.durations.expressiveDefaultEffects;
        case Anim.SlowEffects:
            return Theme.durations.expressiveSlowEffects;
        }
        const sizes = [Theme.durations.small, Theme.durations.normal, Theme.durations.large, Theme.durations.extraLarge];
        return sizes[type % 4] ?? Theme.durations.normal;
    }

    easing.type: Easing.BezierSpline
    easing.bezierCurve: {
        switch (type) {
        case Anim.FastSpatial:
            return Theme.curves.expressiveFastSpatial;
        case Anim.DefaultSpatial:
            return Theme.curves.expressiveDefaultSpatial;
        case Anim.SlowSpatial:
            return Theme.curves.expressiveSlowSpatial;
        case Anim.FastEffects:
            return Theme.curves.expressiveFastEffects;
        case Anim.DefaultEffects:
            return Theme.curves.expressiveDefaultEffects;
        case Anim.SlowEffects:
            return Theme.curves.expressiveSlowEffects;
        }
        if (type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge)
            return Theme.curves.emphasized;
        return Theme.curves.standard;
    }
}
