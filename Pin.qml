import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import qs.Services.UI

Variants {
    id: pinVariants

    property var pins: []
    readonly property bool hasPins: pins.length > 0

    function addPin(imgPath, pw, ph) {
        var p = pins.slice()
        p.push({ imgPath: imgPath, w: Math.min(pw, 900), h: Math.min(ph, 700) })
        pins = p
    }

    function removePin(i) {
        var p = pins.slice()
        p.splice(i, 1)
        pins = p
    }

    function pinField(i, field) {
        if (i < 0 || i >= pins.length) return null
        return pins[i][field]
    }

    model: Quickshell.screens

    delegate: PanelWindow {
        required property ShellScreen modelData
        screen: modelData

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        visible: pinVariants.hasPins

        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "noctalia-pin"

        Repeater {
            model: pinVariants.pins.length

            delegate: Item {
                id: pinDelegate

                readonly property int myIdx: index
                readonly property string pinImgPath: pinVariants.pinField(myIdx, "imgPath") || ""
                readonly property real pinW: pinVariants.pinField(myIdx, "w") || 400
                readonly property real pinH: pinVariants.pinField(myIdx, "h") || 300

                x: (parent.width  - pinW)  / 2 + myIdx * 24
                y: (parent.height - pinH - 34) / 2 + myIdx * 24
                width:  pinW
                height: pinH + 34

                Rectangle {
                    id: pinCard
                    anchors.fill: parent

                    property real imgOpacity: 1.0

                    radius: Style.radiusM
                    color:  Color.mSurface
                    border.color: Color.mOutline
                    border.width: 1

                    // ── Toolbar ───────────────────────────────
                    Rectangle {
                        id: toolbar
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: 34
                        color: Color.mSurfaceVariant
                        radius: Style.radiusM

                        Rectangle {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                            height: Style.radiusM
                            color: parent.color
                        }

                        MouseArea {
                            anchors.fill: parent
                            drag.target: pinDelegate
                            drag.minimumX: -pinDelegate.width + 40
                            drag.maximumX: pinDelegate.parent ? pinDelegate.parent.width - 40 : 9999
                            drag.minimumY: 0
                            drag.maximumY: pinDelegate.parent ? pinDelegate.parent.height - 40 : 9999
                            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            propagateComposedEvents: true
                        }

                        NIcon {
                            anchors { left: parent.left; leftMargin: Style.marginS; verticalCenter: parent.verticalCenter }
                            icon: "grip-vertical"
                            color: Color.mOnSurfaceVariant
                            scale: 0.85
                        }

                        Row {
                            anchors { right: parent.right; rightMargin: Style.marginS; verticalCenter: parent.verticalCenter }
                            spacing: 4

                            // Opacity toggle
                            Rectangle {
                                width: 26; height: 26; radius: Style.radiusS
                                color: opBtn.containsMouse ? Color.mPrimary : Color.mSurface
                                NText {
                                    anchors.centerIn: parent
                                    text: pinCard.imgOpacity < 1.0 ? "100" : "50"
                                    pointSize: Style.fontSizeXS
                                    color: opBtn.containsMouse ? Color.mOnPrimary : Color.mOnSurface
                                }
                                MouseArea {
                                    id: opBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: pinCard.imgOpacity = (pinCard.imgOpacity < 1.0) ? 1.0 : 0.4
                                    onEntered: TooltipService.show(opBtn, pinCard.imgOpacity < 1.0 ? "Restore opacity" : "Reduce opacity")
                                    onExited: TooltipService.hide()
                                }
                            }

                            // Close
                            Rectangle {
                                width: 26; height: 26; radius: Style.radiusS
                                color: closeBtn.containsMouse ? Color.mSurfaceVariant : Color.mSurface
                                NIcon {
                                    anchors.centerIn: parent; icon: "x"; scale: 0.8
                                    color: closeBtn.containsMouse ? Color.mError : Color.mOnSurface
                                }
                                MouseArea {
                                    id: closeBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: pinVariants.removePin(pinDelegate.myIdx)
                                    onEntered: TooltipService.show(closeBtn, "Close")
                                    onExited: TooltipService.hide()
                                }
                            }
                        }
                    }

                    // ── Image ─────────────────────────────────
                    Image {
                        anchors { top: toolbar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                        source: pinDelegate.pinImgPath !== "" ? "file://" + pinDelegate.pinImgPath : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        opacity: pinCard.imgOpacity
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }
        }
    }
}
