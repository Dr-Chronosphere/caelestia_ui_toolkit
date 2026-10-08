import QtQuick

// ColorAnimation used for theme/state colour transitions.
ColorAnimation {
    duration: Theme.durations.expressiveSlowEffects
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.curves.expressiveSlowEffects
}
