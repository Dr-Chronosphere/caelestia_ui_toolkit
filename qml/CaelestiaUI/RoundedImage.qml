import QtQuick
import QtQuick.Effects

// Image with rounded corners. Uses a mask effect on GPU renderers; with the software
// renderer (no effects) corners stay square.
Item {
    id: root

    property alias source: img.source
    property alias sourceSize: img.sourceSize
    property alias fillMode: img.fillMode
    property alias status: img.status
    property real radius: Theme.rounding.small

    readonly property bool _masked: GraphicsInfo.api !== GraphicsInfo.Software

    Image {
        id: img

        anchors.fill: parent
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        layer.enabled: root._masked
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
        }
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: root._masked
    }
}
