import Quickshell
import Quickshell.Wayland

import qs.config

Scope {
    id: root
    Variants {
        model: Quickshell.screens

        PanelWindow {
            property var modelData
            property bool barOnTop: Config.bar_on_top
            screen: modelData
            WlrLayershell.layer: WlrLayer.Top
            color: Config.color_transparent
            implicitHeight: barContent.implicitHeight

            anchors {
                top: barOnTop
                bottom: !barOnTop
                left: true
                right: true
            }

            BarContent {
                id: barContent
            }
        }
    }
}
