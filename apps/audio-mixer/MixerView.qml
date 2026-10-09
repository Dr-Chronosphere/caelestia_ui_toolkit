import QtQuick
import CaelestiaUI
import "services/Logic.js" as Logic

// The mixer UI. `mixer` is the service (Mixer singleton); kept as a property so the view
// can be tested with a mock.
Rectangle {
    id: root

    required property var mixer

    implicitWidth: 480
    implicitHeight: 720
    color: Theme.palette.m3surface

    readonly property var routeTargets: [...mixer.sinks, ...(mixer.combinedSink ? [mixer.combinedSink] : [])]

    function volumeOf(node): real {
        return node?.audio?.volume ?? 0;
    }
    function sameNode(a, b): bool {
        return !!a && !!b && a.name === b.name;
    }
    function mutedOf(node): bool {
        return !!node?.audio?.muted;
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + Theme.padding.extraLarge * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col

            x: Theme.padding.extraLarge
            y: Theme.padding.extraLarge
            width: flick.width - Theme.padding.extraLarge * 2
            spacing: Theme.spacing.large

            StyledText {
                text: "Audio"
                font: Theme.headline.small
            }

            // --- Combined output -------------------------------------------------
            SectionHeader { text: "Simultaneous output" }
            Card {
                width: parent.width

                Column {
                    width: parent.width
                    spacing: Theme.spacing.medium

                    StyledText {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.palette.m3onSurfaceVariant
                        text: root.mixer.combinedActive ? `Playing on ${root.mixer.members.length} outputs. Use the switches below to change which.` : "Tick two or more outputs below, then start. Audio plays on all of them at once."
                    }

                    Row {
                        spacing: Theme.spacing.small

                        TextButton {
                            visible: !root.mixer.combinedActive
                            icon: "surround_sound"
                            text: `Play on ${root.mixer.members.length} selected`
                            disabled: root.mixer.members.length < 2 || root.mixer.busy
                            onClicked: root.mixer.applyCombine()
                        }
                        TextButton {
                            visible: root.mixer.combinedActive
                            icon: "stop"
                            type: ButtonBase.Tonal
                            text: "Stop combining"
                            disabled: root.mixer.busy
                            onClicked: root.mixer.stopCombine()
                        }
                    }

                    StyledText {
                        visible: root.mixer.error.length > 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: Theme.palette.m3error
                        text: root.mixer.error
                    }
                }
            }

            // --- Outputs ---------------------------------------------------------
            SectionHeader { text: "Outputs" }
            Card {
                width: parent.width

                Column {
                    width: parent.width
                    spacing: Theme.spacing.small

                    Repeater {
                        model: root.mixer.sinks

                        Column {
                            id: sinkItem

                            required property var modelData

                            width: parent.width

                            ListRow {
                                width: parent.width
                                icon: Logic.sinkIcon(sinkItem.modelData.properties, sinkItem.modelData.description)
                                title: sinkItem.modelData.description || sinkItem.modelData.name
                                subtitle: root.sameNode(root.mixer.defaultSink, sinkItem.modelData) ? "Default output" : ""
                                selected: root.sameNode(root.mixer.defaultSink, sinkItem.modelData)
                                onClicked: root.mixer.setDefault(sinkItem.modelData)

                                StyledSwitch {
                                    checked: root.mixer.isMember(sinkItem.modelData)
                                    onToggled: root.mixer.setMember(sinkItem.modelData, checked)
                                }
                            }

                            Row {
                                x: Theme.padding.large
                                width: parent.width - x * 2
                                height: 36
                                spacing: Theme.spacing.small

                                IconButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: root.mutedOf(sinkItem.modelData) ? "volume_off" : "volume_up"
                                    iconSize: Theme.iconSize.medium
                                    type: ButtonBase.Text
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    onClicked: root.mixer.toggleMute(sinkItem.modelData)
                                }
                                StyledSlider {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 32 - 44 - parent.spacing * 2
                                    value: root.volumeOf(sinkItem.modelData)
                                    onMoved: v => root.mixer.setVolume(sinkItem.modelData, v)
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 44
                                    horizontalAlignment: Text.AlignRight
                                    color: Theme.palette.m3onSurfaceVariant
                                    text: `${Math.round(root.volumeOf(sinkItem.modelData) * 100)}%`
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: root.mixer.sinks.length === 0
                        color: Theme.palette.m3onSurfaceVariant
                        text: "No output devices found."
                    }
                }
            }

            // --- Apps ------------------------------------------------------------
            SectionHeader { text: "Apps" }
            Card {
                width: parent.width

                Column {
                    width: parent.width
                    spacing: Theme.spacing.large

                    Repeater {
                        model: root.mixer.streams

                        Column {
                            id: app

                            required property var modelData
                            readonly property var current: root.mixer.sinkOf(modelData, root.mixer.linksRevision)

                            width: parent.width
                            spacing: Theme.spacing.small

                            Row {
                                width: parent.width
                                height: 36
                                spacing: Theme.spacing.small

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 120
                                    elide: Text.ElideRight
                                    font: Theme.body.large
                                    text: root.mixer.streamName(app.modelData)
                                }
                                StyledSlider {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 120 - 32 - parent.spacing * 2
                                    value: root.volumeOf(app.modelData)
                                    onMoved: v => root.mixer.setVolume(app.modelData, v)
                                }
                                IconButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: root.mutedOf(app.modelData) ? "volume_off" : "volume_up"
                                    iconSize: Theme.iconSize.medium
                                    type: ButtonBase.Text
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    onClicked: root.mixer.toggleMute(app.modelData)
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: Theme.spacing.small

                                Repeater {
                                    model: root.routeTargets

                                    TextButton {
                                        required property var modelData

                                        implicitHeight: 32
                                        text: modelData.description || modelData.name
                                        type: root.sameNode(app.current, modelData) ? ButtonBase.Filled : ButtonBase.Tonal
                                        onClicked: root.mixer.routeStream(app.modelData, modelData)
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: root.mixer.streams.length === 0
                        color: Theme.palette.m3onSurfaceVariant
                        text: "Nothing is playing."
                    }
                }
            }
        }
    }
}
