import QtQuick
import CaelestiaUI

Rectangle {
    id: root

    width: 420
    height: 520
    color: Theme.palette.m3surface

    property alias swatch: swatch
    function apply(text: string): bool {
        return Theme.applyScheme(text);
    }

    Column {
        spacing: 8
        padding: 8

        Rectangle {
            id: swatch

            width: 40
            height: 40
            color: Theme.palette.m3primary
        }
        SectionHeader { text: "Outputs" }
        Card {
            width: 380
            Column {
                width: parent.width
                ListRow { width: parent.width; icon: "speaker"; title: "Speakers"; subtitle: "Built-in Audio"; selected: true }
                ListRow {
                    width: parent.width
                    icon: "headphones"
                    title: "Headphones"
                    StyledSwitch { checked: true }
                }
            }
        }
        Row {
            spacing: 8
            TextButton { text: "Filled"; icon: "check" }
            TextButton { text: "Tonal"; type: ButtonBase.Tonal }
            TextButton { text: "Text"; type: ButtonBase.Text }
            IconButton { icon: "volume_up"; toggle: true }
        }
        StyledSlider { width: 300; value: 0.4 }
        StyledText { text: "animated"; animate: true }
        MaterialIcon { text: "mic"; fill: 1 }
        StyledRect { width: 10; height: 10; color: "red" }
    }
}
