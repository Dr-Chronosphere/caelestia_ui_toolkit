import QtQuick
import CaelestiaUI

// Component showcase. Content only, so it can be loaded without Quickshell.
Rectangle {
    id: root

    implicitWidth: 460
    implicitHeight: col.implicitHeight + Theme.padding.extraLarge * 2
    color: Theme.palette.m3surface

    property int selectedOutput: 0
    property real volume: 0.65

    Column {
        id: col

        anchors.fill: parent
        anchors.margins: Theme.padding.extraLarge
        spacing: Theme.spacing.large

        StyledText {
            text: "Caelestia UI"
            font: Theme.headline.small
        }
        StyledText {
            text: `Scheme: ${Theme.schemeName} (${Theme.light ? "light" : "dark"})`
            color: Theme.palette.m3onSurfaceVariant
        }

        SectionHeader { text: "Output (mock data)" }
        Card {
            width: parent.width

            Column {
                width: parent.width
                spacing: Theme.spacing.extraSmall

                Repeater {
                    model: [
                        {"icon": "speaker", "title": "Speakers", "sub": "Built-in Audio Analog Stereo"},
                        {"icon": "headphones", "title": "Headphones", "sub": "USB DAC"},
                        {"icon": "bluetooth_audio", "title": "WH-1000XM5", "sub": "Bluetooth"}
                    ]

                    ListRow {
                        required property var modelData
                        required property int index

                        width: parent.width
                        icon: modelData.icon
                        title: modelData.title
                        subtitle: modelData.sub
                        selected: root.selectedOutput === index
                        onClicked: root.selectedOutput = index

                        StyledSwitch {
                            // placeholder for "also play here" (simultaneous output)
                            checked: index === 1
                        }
                    }
                }
            }
        }

        SectionHeader { text: "Volume" }
        Row {
            width: parent.width
            spacing: Theme.spacing.medium

            IconButton {
                icon: root.volume > 0 ? "volume_up" : "volume_off"
                type: ButtonBase.Tonal
                onClicked: root.volume = root.volume > 0 ? 0 : 0.65
            }
            StyledSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 40 - 48 - parent.spacing * 2
                value: root.volume
                onMoved: v => root.volume = v
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                text: `${Math.round(root.volume * 100)}%`
                horizontalAlignment: Text.AlignRight
            }
        }

        Row {
            spacing: Theme.spacing.small

            TextButton { text: "Filled" }
            TextButton { text: "Tonal"; type: ButtonBase.Tonal }
            TextButton { text: "Text"; type: ButtonBase.Text }
            TextButton { text: "Toggle"; icon: "check"; toggle: true; type: ButtonBase.Tonal }
        }
    }
}
