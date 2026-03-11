import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    property real contentPreferredWidth: 340 * Style.uiScaleRatio
    property real contentPreferredHeight: mainCol.implicitHeight + Style.marginL * 2

    anchors.fill: parent

    property var main: null

    onPluginApiChanged: {
        if (pluginApi) {
            Logger.i("ScreenToolkit", "pluginApi set, mainInstance=" + pluginApi.mainInstance)
            root.main = pluginApi.mainInstance
            var saved = pluginApi.pluginSettings.selectedOcrLang
            if (saved && saved !== "") root.selectedOcrLang = saved
            if (!root.main) mainRetryTimer.start()
        }
    }

    // FIX: added attempt counter — timer no longer retries indefinitely if
    // mainInstance never becomes available (was an infinite loop risk)
    Timer {
        id: mainRetryTimer
        interval: 100
        repeat: true
        property int _attempts: 0
        onTriggered: {
            _attempts++
            if (_attempts > 50) {
                Logger.e("ScreenToolkit", "mainInstance never became available after 5s — giving up")
                stop()
                return
            }
            if (pluginApi && pluginApi.mainInstance) {
                root.main = pluginApi.mainInstance
                _attempts = 0
                stop()
            }
        }
    }

    Connections {
        target: pluginApi
        ignoreUnknownSignals: true
        function onMainInstanceChanged() {
            Logger.i("ScreenToolkit", "mainInstance changed: " + pluginApi.mainInstance)
            root.main = pluginApi.mainInstance
            if (root.main) mainRetryTimer.stop()
        }
    }

    readonly property bool isRunning: main?.isRunning ?? false
    readonly property string activeTool: main?.activeTool ?? ""
    readonly property bool hasResult: activeTool !== "" && !isRunning
    onActiveToolChanged: {
        if (activeTool === "ocr" || activeTool === "qr" || activeTool === "colorpicker" || activeTool === "palette")
            root.viewedTool = activeTool
    }

    readonly property var installedLangs: pluginApi?.pluginSettings?.installedLangs || ["eng"]
    readonly property bool transAvailable: pluginApi?.pluginSettings?.transAvailable || false

    property string selectedOcrLang: "eng"
    onSelectedOcrLangChanged: {
        if (pluginApi) { pluginApi.pluginSettings.selectedOcrLang = selectedOcrLang; pluginApi.saveSettings() }
    }
    property string selectedTransLang: "en"

    readonly property var transLangs: [
        { code: "en", name: "English"    }, { code: "ar", name: "Arabic"     },
        { code: "fr", name: "French"     }, { code: "es", name: "Spanish"    },
        { code: "de", name: "German"     }, { code: "it", name: "Italian"    },
        { code: "pt", name: "Portuguese" }, { code: "ru", name: "Russian"    },
        { code: "zh", name: "Chinese"    }, { code: "ja", name: "Japanese"   },
        { code: "ko", name: "Korean"     }, { code: "tr", name: "Turkish"    },
        { code: "hi", name: "Hindi"      }, { code: "nl", name: "Dutch"      },
        { code: "pl", name: "Polish"     }, { code: "sv", name: "Swedish"    },
        { code: "fa", name: "Persian"    }, { code: "id", name: "Indonesian" },
        { code: "uk", name: "Ukrainian"  }, { code: "vi", name: "Vietnamese" }
    ]

    readonly property string pickedHex: {
        if (!pluginApi?.pluginSettings) return ""
        var v = pluginApi.pluginSettings.resultHex
        return (typeof v === "string" && v.length === 7 && v.charAt(0) === "#") ? v : ""
    }
    readonly property string pickedRgb: {
        if (!pluginApi?.pluginSettings) return ""
        var v = pluginApi.pluginSettings.resultRgb
        return (typeof v === "string" && v !== "") ? v : ""
    }
    readonly property string pickedHsv: {
        if (!pluginApi?.pluginSettings) return ""
        var v = pluginApi.pluginSettings.resultHsv
        return (typeof v === "string" && v !== "") ? v : ""
    }
    readonly property string pickedHsl: {
        if (!pluginApi?.pluginSettings) return ""
        var v = pluginApi.pluginSettings.resultHsl
        return (typeof v === "string" && v !== "") ? v : ""
    }
    readonly property string colorCapturePath: {
        if (!pluginApi?.pluginSettings) return ""
        var v = pluginApi.pluginSettings.colorCapturePath
        return (typeof v === "string" && v !== "") ? v : ""
    }
    readonly property var colorHistory: pluginApi?.pluginSettings?.colorHistory || []
    readonly property var paletteColors: pluginApi?.pluginSettings?.paletteColors || []

    readonly property string ocrResult: {
        if (!pluginApi?.pluginSettings) return ""
        var v = pluginApi.pluginSettings.ocrResult
        return (typeof v === "string") ? v : ""
    }
    readonly property string ocrCapturePath: pluginApi?.pluginSettings?.ocrCapturePath || ""
    readonly property string translateResult: {
        if (!pluginApi?.pluginSettings) return ""
        var v = pluginApi.pluginSettings.translateResult
        return (typeof v === "string") ? v : ""
    }
    readonly property string qrResult: {
        if (!pluginApi?.pluginSettings) return ""
        var v = pluginApi.pluginSettings.qrResult
        return (typeof v === "string") ? v : ""
    }
    readonly property string qrCapturePath: pluginApi?.pluginSettings?.qrCapturePath || ""

    // ── OCR smart type detection ──────────────────────
    readonly property string ocrUrl: {
        var m = root.ocrResult.match(/https?:\/\/[^\s]+/)
        if (m) return m[0]
        var m2 = root.ocrResult.match(/www\.[a-zA-Z0-9\-]+\.[a-zA-Z]{2,}[^\s]*/)
        if (m2) return "https://" + m2[0]
        return ""
    }
    readonly property string ocrEmail: {
        var m = root.ocrResult.match(/[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/)
        return m ? m[0] : ""
    }
    readonly property string ocrType: {
        if (root.ocrUrl   !== "") return "url"
        if (root.ocrEmail !== "") return "email"
        return "text"
    }

    // ── QR type detection ─────────────────────────────
    readonly property string qrType: {
        var r = root.qrResult
        if (r.startsWith("http://") || r.startsWith("https://")) return "url"
        if (r.startsWith("WIFI:"))       return "wifi"
        if (r.startsWith("BEGIN:VCARD")) return "contact"
        if (r.startsWith("mailto:"))     return "email"
        if (r.startsWith("otpauth://"))  return "otp"
        return "text"
    }
    readonly property string qrWifiName: {
        if (root.qrType !== "wifi") return ""
        var m = root.qrResult.match(/S:([^;]+)/)
        return m ? m[1] : ""
    }
    readonly property string qrWifiPass: {
        if (root.qrType !== "wifi") return ""
        var m = root.qrResult.match(/P:([^;]+)/)
        return m ? m[1] : ""
    }

    // ── Keyboard nav state ───────────────────────────
    property int focusedTool: 0
    property string viewedTool: ""

    readonly property var toolDefs: [
        { icon: "color-picker",  label: "Color",    tool: "colorpicker", tooltip: "Pick a color from screen"              },
        { icon: "palette",       label: "Palette",  tool: "palette",     tooltip: "Extract dominant colors from a region" },
        { icon: "scan",          label: "OCR",      tool: "ocr",         tooltip: "Extract text from screen"              },
        { icon: "world-search",  label: "Lens",     tool: "lens",        tooltip: "Search image with Google Lens"         },
        { icon: "qrcode",        label: "QR",       tool: "qr",          tooltip: "Scan a QR or barcode"                  },
        { icon: "brush",         label: "Annotate", tool: "annotate",    tooltip: "Draw and annotate a region"            },
        { icon: "video",         label: "Record",   tool: "record",      tooltip: "Record a screen region as GIF or MP4"  },
        { icon: "pin",           label: "Pin",      tool: "pin",         tooltip: "Pin a screen region as floating overlay"},
        { icon: "ruler",         label: "Measure",  tool: "measure",     tooltip: "Measure distance in pixels"            },
        { icon: "camera",        label: "Mirror",   tool: "mirror",      tooltip: "Floating webcam mirror"                }
    ]

    property string selectedRecordFormat: "gif"
    property bool recordAudioOutput: false
    property bool recordAudioInput: false

    function triggerFocused() {
        var t = root.toolDefs[root.focusedTool].tool
        Logger.i("ScreenToolkit", "triggerFocused: tool=" + t + " isRunning=" + root.isRunning + " main=" + root.main)
        if (root.isRunning) { Logger.w("ScreenToolkit", "blocked: isRunning"); return }
        if (!root.main)     { Logger.e("ScreenToolkit", "FATAL: main is null! pluginApi=" + pluginApi); return }
        root.viewedTool = t
        if (t === "ocr" || t === "record") return
        if      (t === "colorpicker") root.main.runColorPicker()
        else if (t === "qr")          root.main.runQr()
        else if (t === "lens")        root.main.runLens()
        else if (t === "annotate")    root.main.runAnnotate()
        else if (t === "measure")     root.main.runMeasure()
        else if (t === "pin")         root.main.runPin()
        else if (t === "palette")     root.main.runPalette()
        else if (t === "mirror")      root.main.runMirror()
        else Logger.e("ScreenToolkit", "unknown tool: " + t)
    }

    onActiveFocusChanged: if (activeFocus) toolBar.forceActiveFocus()

    Component.onCompleted: {
        Logger.i("ScreenToolkit", "Panel loaded — pluginApi=" + pluginApi + " main=" + main)
    }

    onInstalledLangsChanged: {
        if (installedLangs.length > 0 && !installedLangs.includes(root.selectedOcrLang))
            root.selectedOcrLang = installedLangs[0]
    }

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        Column {
            id: mainCol
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: Style.marginL
            spacing: Style.marginM

            // ── Header ────────────────────────────────────
            Row {
                width: parent.width; spacing: Style.marginS
                NIcon { icon: "crosshair"; color: Color.mPrimary; anchors.verticalCenter: parent.verticalCenter }
                NText { text: "Screen Toolkit"; pointSize: Style.fontSizeL; font.weight: Font.Bold; color: Color.mOnSurface; anchors.verticalCenter: parent.verticalCenter }
            }

            // ── Tool Buttons ──────────────────────────────
            Rectangle {
                id: toolBar
                width: parent.width
                height: toolsCol.implicitHeight + Style.marginM * 2
                color: Color.mSurfaceVariant
                radius: Style.radiusL
                focus: true
                Component.onCompleted: forceActiveFocus()

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Left) {
                        root.focusedTool = (root.focusedTool + 9) % 10
                        event.accepted = true
                    } else if (event.key === Qt.Key_Right) {
                        root.focusedTool = (root.focusedTool + 1) % 10
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        // FIX: Up moves from row 2 → row 1; clamp if already on row 1
                        root.focusedTool = root.focusedTool >= 5 ? root.focusedTool - 5 : root.focusedTool
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        // FIX: Down moves from row 1 → row 2; clamp if already on row 2
                        root.focusedTool = root.focusedTool < 5 ? root.focusedTool + 5 : root.focusedTool
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.triggerFocused()
                        event.accepted = true
                    }
                }

                Column {
                    id: toolsCol
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: Style.marginM
                    }
                    spacing: 6

                    readonly property int btnSize: Math.floor((width - 6 * 4) / 5)

                    Row {
                        spacing: 6
                        Repeater {
                            model: root.toolDefs.slice(0, 5)
                            delegate: ToolBtn {
                                readonly property int myIdx: index
                                icon: modelData.icon; label: modelData.label; tooltip: modelData.tooltip
                                active: root.activeTool === modelData.tool
                                focused: root.focusedTool === myIdx
                                running: root.isRunning
                                width: toolsCol.btnSize; height: toolsCol.btnSize + 18
                                onTriggered: { root.focusedTool = myIdx; root.viewedTool = modelData.tool; root.triggerFocused() }
                            }
                        }
                    }

                    Row {
                        spacing: 6
                        Repeater {
                            model: root.toolDefs.slice(5, 10)
                            delegate: ToolBtn {
                                readonly property int myIdx: index + 5
                                icon: modelData.icon; label: modelData.label; tooltip: modelData.tooltip
                                active: root.activeTool === modelData.tool
                                focused: root.focusedTool === myIdx
                                running: root.isRunning
                                width: toolsCol.btnSize; height: toolsCol.btnSize + 18
                                onTriggered: { root.focusedTool = myIdx; root.viewedTool = modelData.tool; root.triggerFocused() }
                            }
                        }
                    }
                }
            }

            // ── Loading ───────────────────────────────────
            Rectangle {
                width: parent.width; height: 56
                color: Color.mSurfaceVariant; radius: Style.radiusL
                visible: root.isRunning
                Row {
                    anchors.centerIn: parent; spacing: Style.marginM
                    NIcon {
                        icon: "loader"; color: Color.mPrimary
                        RotationAnimation on rotation { running: root.isRunning; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
                    }
                    NText { text: "Running..."; color: Color.mOnSurfaceVariant }
                }
            }

            // ── OCR Lang pre-select ───────────────────────
            Column {
                width: parent.width; spacing: Style.marginS
                visible: root.viewedTool === "ocr" && !root.isRunning

                Flow {
                    width: parent.width; spacing: Style.marginS
                    NText { text: "Lang:"; color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS; height: 26; verticalAlignment: Text.AlignVCenter }
                    Repeater {
                        model: root.installedLangs
                        delegate: Rectangle {
                            height: 26; width: ct.implicitWidth + Style.marginM * 2; radius: Style.radiusS
                            color: root.selectedOcrLang === modelData ? Color.mPrimary : (ch.containsMouse ? Color.mHover : Color.mSurfaceVariant)
                            NText { id: ct; anchors.centerIn: parent; text: modelData.toUpperCase(); color: root.selectedOcrLang === modelData ? Color.mOnPrimary : Color.mOnSurface; pointSize: Style.fontSizeXS; font.weight: root.selectedOcrLang === modelData ? Font.Bold : Font.Normal }
                            MouseArea { id: ch; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedOcrLang = modelData }
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: 38; radius: Style.radiusM
                    color: scanBtn.containsMouse ? Color.mPrimary : Color.mSurface
                    border.color: Color.mPrimary; border.width: Style.capsuleBorderWidth || 1
                    Row {
                        anchors.centerIn: parent; spacing: Style.marginS
                        NIcon { icon: "scan"; color: scanBtn.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                        NText { text: "Scan"; color: scanBtn.containsMouse ? Color.mOnPrimary : Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS }
                    }
                    MouseArea { id: scanBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.main.runOcr(root.selectedOcrLang) }
                }
            }

            // ── Record Format pre-select ──────────────────
            Column {
                width: parent.width; spacing: Style.marginS
                visible: root.viewedTool === "record" && !root.isRunning

                // ── Format ────────────────────────────────
                Flow {
                    width: parent.width; spacing: Style.marginS
                    NText { text: "Format:"; color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS; height: 26; verticalAlignment: Text.AlignVCenter }
                    Repeater {
                        // GIF gets a · 30s hint, MP4 gets nothing
                        model: [{ id: "gif", label: "GIF", hint: "· 30s" }, { id: "mp4", label: "MP4", hint: "" }]
                        delegate: Rectangle {
                            height: 26
                            width: fmtLabel.implicitWidth + (modelData.hint !== "" ? fmtHint.implicitWidth + 4 : 0) + Style.marginM * 2 + 8
                            radius: Style.radiusS
                            color: root.selectedRecordFormat === modelData.id ? Color.mPrimary : (fmtArea.containsMouse ? Color.mHover : Color.mSurfaceVariant)
                            Row {
                                anchors.centerIn: parent; spacing: 4
                                NText {
                                    id: fmtLabel
                                    text: modelData.label
                                    color: root.selectedRecordFormat === modelData.id ? Color.mOnPrimary : Color.mOnSurface
                                    pointSize: Style.fontSizeXS
                                    font.weight: root.selectedRecordFormat === modelData.id ? Font.Bold : Font.Normal
                                }
                                NText {
                                    id: fmtHint
                                    visible: modelData.hint !== ""
                                    text: modelData.hint
                                    color: root.selectedRecordFormat === modelData.id ? Qt.rgba(1,1,1,0.65) : Color.mOnSurfaceVariant
                                    pointSize: Style.fontSizeXS
                                }
                            }
                            MouseArea { id: fmtArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedRecordFormat = modelData.id }
                        }
                    }
                }

                // ── Audio ─────────────────────────────────
                Flow {
                    width: parent.width; spacing: Style.marginS
                    NText { text: "Audio:"; color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS; height: 26; verticalAlignment: Text.AlignVCenter }
                    Rectangle {
                        height: 26; width: audioOutIcon.implicitWidth + audioOutLabel.implicitWidth + Style.marginM * 2 + Style.marginS + 4; radius: Style.radiusS
                        color: root.recordAudioOutput ? Color.mPrimary : (audioOutArea.containsMouse ? Color.mHover : Color.mSurfaceVariant)
                        Row { anchors.centerIn: parent; spacing: 4
                            NIcon { id: audioOutIcon; icon: root.recordAudioOutput ? "volume" : "volume-off"; color: root.recordAudioOutput ? Color.mOnPrimary : Color.mOnSurface; scale: 0.8 }
                            NText { id: audioOutLabel; text: "System"; color: root.recordAudioOutput ? Color.mOnPrimary : Color.mOnSurface; pointSize: Style.fontSizeXS; font.weight: root.recordAudioOutput ? Font.Bold : Font.Normal }
                        }
                        MouseArea { id: audioOutArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.recordAudioOutput = !root.recordAudioOutput
                            onEntered: TooltipService.show(audioOutArea, "Record system audio (desktop output)")
                            onExited: TooltipService.hide() }
                    }
                    Rectangle {
                        height: 26; width: micIcon.implicitWidth + micLabel.implicitWidth + Style.marginM * 2 + Style.marginS + 4; radius: Style.radiusS
                        color: root.recordAudioInput ? Color.mPrimary : (micArea.containsMouse ? Color.mHover : Color.mSurfaceVariant)
                        Row { anchors.centerIn: parent; spacing: 4
                            NIcon { id: micIcon;  icon: root.recordAudioInput ? "microphone" : "microphone-off"; color: root.recordAudioInput ? Color.mOnPrimary : Color.mOnSurface; scale: 0.8 }
                            NText { id: micLabel; text: "Mic"; color: root.recordAudioInput ? Color.mOnPrimary : Color.mOnSurface; pointSize: Style.fontSizeXS; font.weight: root.recordAudioInput ? Font.Bold : Font.Normal }
                        }
                        MouseArea { id: micArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.recordAudioInput = !root.recordAudioInput
                            onEntered: TooltipService.show(micArea, "Record microphone")
                            onExited: TooltipService.hide() }
                    }
                }

                Rectangle {
                    width: parent.width; height: 38; radius: Style.radiusM
                    color: recStartBtn.containsMouse ? Color.mPrimary : Color.mSurface
                    border.color: Color.mPrimary; border.width: Style.capsuleBorderWidth || 1
                    Row {
                        anchors.centerIn: parent; spacing: Style.marginS
                        NIcon { icon: "video"; color: recStartBtn.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                        NText { text: "Record"; color: recStartBtn.containsMouse ? Color.mOnPrimary : Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS }
                    }
                    MouseArea { id: recStartBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.main.runRecord(root.selectedRecordFormat, root.recordAudioOutput, root.recordAudioInput) }
                }
            }

            // ── Mirror ────────────────────────────────────
            Column {
                width: parent.width; spacing: Style.marginM
                visible: root.viewedTool === "mirror"

                Row {
                    width: parent.width; spacing: Style.marginS
                    NIcon { icon: "camera"; color: Color.mPrimary; anchors.verticalCenter: parent.verticalCenter }
                    NText { text: "Webcam Mirror"; color: Color.mOnSurface; font.weight: Font.Bold; pointSize: Style.fontSizeS; anchors.verticalCenter: parent.verticalCenter }
                }

                NText {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "Floating camera preview. Drag to move, resize from corners."
                    color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS
                }

                Rectangle {
                    width: parent.width; height: 38; radius: Style.radiusM
                    color: root.main && root.main.mirrorVisible ? Color.mError : (mirrorToggleBtn.containsMouse ? Color.mPrimary : Color.mSurface)
                    border.color: root.main && root.main.mirrorVisible ? Color.mError : Color.mPrimary
                    border.width: Style.capsuleBorderWidth || 1
                    Row {
                        anchors.centerIn: parent; spacing: Style.marginS
                        NIcon {
                            icon: root.main && root.main.mirrorVisible ? "camera-off" : "camera"
                            color: root.main && root.main.mirrorVisible ? Color.mOnError : (mirrorToggleBtn.containsMouse ? Color.mOnPrimary : Color.mPrimary)
                        }
                        NText {
                            text: root.main && root.main.mirrorVisible ? "Close Mirror" : "Open Mirror"
                            color: root.main && root.main.mirrorVisible ? Color.mOnError : (mirrorToggleBtn.containsMouse ? Color.mOnPrimary : Color.mPrimary)
                            font.weight: Font.Bold; pointSize: Style.fontSizeS
                        }
                    }
                    MouseArea { id: mirrorToggleBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.main.runMirror() }
                }
            }

            // ── Color Result ──────────────────────────────
            Column {
                width: parent.width; spacing: Style.marginM
                visible: root.viewedTool === "colorpicker" && root.pickedHex !== ""

                Row {
                    width: parent.width; spacing: Style.marginM

                    Rectangle {
                        width: 110; height: 110; radius: Style.radiusM
                        color: Color.mSurfaceVariant; clip: true
                        border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                        Image {
                            id: pixelImg
                            anchors.fill: parent
                            source: root.colorCapturePath !== "" ? ("file://" + root.colorCapturePath + "?t=" + Date.now()) : ""
                            fillMode: Image.Stretch; smooth: false; cache: false
                            visible: status === Image.Ready
                        }
                        Rectangle {
                            anchors.centerIn: parent; width: 10; height: 10; radius: 5
                            color: "transparent"; border.color: "white"; border.width: 1
                            visible: pixelImg.status === Image.Ready
                        }
                        NText { anchors.centerIn: parent; visible: pixelImg.status !== Image.Ready; text: "..."; color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeS }
                    }

                    Column {
                        width: parent.width - 110 - Style.marginM; spacing: Style.marginS
                        Rectangle {
                            id: colorSwatch
                            width: parent.width; height: 72; radius: Style.radiusM; color: "#888888"
                            border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                            Connections {
                                target: root
                                function onPickedHexChanged() { if (root.pickedHex !== "") colorSwatch.color = root.pickedHex }
                            }
                        }
                        NText {
                            width: parent.width; text: root.pickedHex.toUpperCase()
                            color: Color.mOnSurface; font.weight: Font.Bold; pointSize: Style.fontSizeM
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                Repeater {
                    model: [
                        { label: "HEX", value: root.pickedHex },
                        { label: "RGB", value: root.pickedRgb },
                        { label: "HSL", value: root.pickedHsl },
                        { label: "HSV", value: root.pickedHsv }
                    ]
                    delegate: Rectangle {
                        width: mainCol.width; height: 36; radius: Style.radiusM
                        color: rh.containsMouse ? Color.mHover : Color.mSurface
                        border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                        Row {
                            anchors.fill: parent; anchors.leftMargin: Style.marginS; anchors.rightMargin: Style.marginS; spacing: Style.marginS
                            NText { text: modelData.label; color: Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS; width: 36; height: parent.height; verticalAlignment: Text.AlignVCenter }
                            NText { text: modelData.value || "—"; color: Color.mOnSurface; pointSize: Style.fontSizeS; width: mainCol.width - 90; height: parent.height; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        }
                        NIcon { icon: "copy"; color: Color.mOnSurfaceVariant; anchors.right: parent.right; anchors.rightMargin: Style.marginS; anchors.verticalCenter: parent.verticalCenter }
                        MouseArea { id: rh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.main?.copyToClipboard(modelData.value); ToastService.showNotice(modelData.label + " copied") } }
                    }
                }

                Row {
                    width: parent.width; spacing: Style.marginS
                    Rectangle {
                        width: parent.width - 46; height: 36; radius: Style.radiusM
                        color: cah.containsMouse ? Color.mPrimary : Color.mSurface
                        border.color: Color.mPrimary; border.width: Style.capsuleBorderWidth || 1
                        Row { anchors.centerIn: parent; spacing: Style.marginS
                            NIcon { icon: "copy"; color: cah.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                            NText { text: "Copy All"; color: cah.containsMouse ? Color.mOnPrimary : Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS }
                        }
                        MouseArea { id: cah; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.main?.copyToClipboard(root.pickedHex + "\n" + root.pickedRgb + "\n" + root.pickedHsl + "\n" + root.pickedHsv); ToastService.showNotice("All formats copied") } }
                    }
                    Rectangle {
                        width: 38; height: 36; radius: Style.radiusM
                        color: clrh.containsMouse ? Color.mErrorContainer || "#ffcdd2" : Color.mSurface
                        border.color: clrh.containsMouse ? Color.mError || "#f44336" : (Style.capsuleBorderColor || "transparent"); border.width: Style.capsuleBorderWidth || 1
                        NIcon { anchors.centerIn: parent; icon: "trash"; color: clrh.containsMouse ? Color.mError || "#f44336" : Color.mOnSurfaceVariant }
                        MouseArea { id: clrh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (pluginApi) {
                                    pluginApi.pluginSettings.resultHex = ""; pluginApi.pluginSettings.resultRgb = ""
                                    pluginApi.pluginSettings.resultHsv = ""; pluginApi.pluginSettings.resultHsl = ""
                                    pluginApi.pluginSettings.colorCapturePath = ""; pluginApi.saveSettings()
                                }
                                root.viewedTool = ""
                            }
                            onEntered: TooltipService.show(clrh, "Clear result"); onExited: TooltipService.hide() }
                    }
                }

                Column {
                    width: parent.width; spacing: Style.marginS
                    visible: root.colorHistory.length > 0
                    Row {
                        width: parent.width; spacing: Style.marginS
                        Rectangle { width: 40; height: 1; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.verticalCenter: parent.verticalCenter }
                        NText { text: "History"; color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS }
                        Rectangle { width: parent.width - 120; height: 1; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.verticalCenter: parent.verticalCenter }
                        Rectangle {
                            width: 22; height: 22; radius: Style.radiusS || 4; anchors.verticalCenter: parent.verticalCenter
                            color: hhc.containsMouse ? Color.mErrorContainer || "#ffcdd2" : "transparent"
                            NIcon { anchors.centerIn: parent; icon: "trash"; color: hhc.containsMouse ? Color.mError || "#f44336" : Color.mOnSurfaceVariant; scale: 0.75 }
                            MouseArea { id: hhc; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (pluginApi) { pluginApi.pluginSettings.colorHistory = []; pluginApi.saveSettings() }; ToastService.showNotice("History cleared") } }
                        }
                    }
                    Row {
                        width: parent.width; spacing: Style.marginS
                        Repeater {
                            model: root.colorHistory
                            delegate: Rectangle {
                                width: 28; height: 28; radius: Style.radiusS || 6
                                border.color: hh.containsMouse ? Color.mPrimary : (Style.capsuleBorderColor || "transparent")
                                border.width: hh.containsMouse ? 2 : (Style.capsuleBorderWidth || 1)
                                Component.onCompleted: color = modelData
                                MouseArea { id: hh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.main?.copyToClipboard(modelData); ToastService.showNotice(modelData + " copied") }
                                    onEntered: TooltipService.show(hh, modelData.toUpperCase() + " — click to copy"); onExited: TooltipService.hide() }
                            }
                        }
                    }
                }
            }

            // ── OCR Result ────────────────────────────────
            Column {
                width: parent.width; spacing: Style.marginM
                visible: root.viewedTool === "ocr" && root.ocrResult !== ""

                Row {
                    width: parent.width; spacing: Style.marginS
                    NIcon { icon: "scan"; color: Color.mPrimary; anchors.verticalCenter: parent.verticalCenter }
                    NText { text: "OCR"; color: Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS; anchors.verticalCenter: parent.verticalCenter }
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(ocrThumb.implicitHeight * (parent.width / Math.max(ocrThumb.implicitWidth, 1)), 160 * Style.uiScaleRatio)
                    radius: Style.radiusM; color: "transparent"; clip: true
                    border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                    visible: root.ocrCapturePath !== "" && root.ocrResult !== "" && ocrThumb.status === Image.Ready
                    Image { id: ocrThumb; anchors.fill: parent; source: (root.ocrCapturePath !== "" && root.ocrResult !== "") ? ("file://" + root.ocrCapturePath) : ""; fillMode: Image.PreserveAspectFit; smooth: true; cache: false }
                }

                Rectangle {
                    width: parent.width; height: 120 * Style.uiScaleRatio
                    radius: Style.radiusM; color: Color.mSurface; clip: true
                    border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                    Flickable {
                        id: ocrFlick; anchors.fill: parent; anchors.margins: Style.marginS
                        contentHeight: ocrText.implicitHeight; clip: true
                        interactive: ocrText.implicitHeight > ocrFlick.height
                        TextEdit {
                            id: ocrText; width: ocrFlick.width; text: root.ocrResult; wrapMode: TextEdit.WordWrap
                            color: Color.mOnSurface; font.pointSize: Style.fontSizeS
                            horizontalAlignment: /[\u0600-\u06FF\u0590-\u05FF]/.test(root.ocrResult) ? TextEdit.AlignRight : TextEdit.AlignLeft
                            selectByMouse: true; selectionColor: Color.mPrimary; selectedTextColor: Color.mOnPrimary
                            WheelHandler { onWheel: event => { ocrFlick.flick(0, event.angleDelta.y * 5); event.accepted = false } }
                        }
                    }
                }

                Row {
                    width: parent.width; spacing: Style.marginS
                    Rectangle {
                        visible: root.ocrType === "url" || root.ocrType === "email"
                        width: 38; height: 38; radius: Style.radiusM
                        color: olinkh.containsMouse ? Color.mPrimary : Color.mSurface
                        border.color: Color.mPrimary; border.width: Style.capsuleBorderWidth || 1
                        NIcon { anchors.centerIn: parent; icon: root.ocrType === "email" ? "mail" : "external-link"; color: olinkh.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                        MouseArea { id: olinkh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.ocrType === "email" ? Qt.openUrlExternally("mailto:" + root.ocrEmail) : Qt.openUrlExternally(root.ocrUrl)
                            onEntered: TooltipService.show(olinkh, root.ocrType === "email" ? "Compose email" : "Open URL"); onExited: TooltipService.hide() }
                    }
                    Rectangle {
                        width: 38; height: 38; radius: Style.radiusM
                        color: osearchh.containsMouse ? Color.mPrimary : Color.mSurface
                        border.color: Color.mPrimary; border.width: Style.capsuleBorderWidth || 1
                        NIcon { anchors.centerIn: parent; icon: "search"; color: osearchh.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                        MouseArea { id: osearchh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally("https://www.google.com/search?q=" + encodeURIComponent(root.ocrResult.trim()))
                            onEntered: TooltipService.show(osearchh, "Search text"); onExited: TooltipService.hide() }
                    }
                    Rectangle {
                        width: 38; height: 38; radius: Style.radiusM
                        color: ocopyh.containsMouse ? Color.mPrimary : Color.mSurface
                        border.color: Color.mPrimary; border.width: Style.capsuleBorderWidth || 1
                        NIcon { anchors.centerIn: parent; icon: "copy"; color: ocopyh.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                        MouseArea { id: ocopyh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.main?.copyToClipboard(root.ocrResult); ToastService.showNotice("Text copied") }
                            onEntered: TooltipService.show(ocopyh, "Copy text"); onExited: TooltipService.hide() }
                    }
                    Rectangle {
                        width: 38; height: 38; radius: Style.radiusM
                        color: oclear.containsMouse ? Color.mErrorContainer || "#ffcdd2" : Color.mSurface
                        border.color: oclear.containsMouse ? Color.mError || "#f44336" : (Style.capsuleBorderColor || "transparent"); border.width: Style.capsuleBorderWidth || 1
                        NIcon { anchors.centerIn: parent; icon: "trash"; color: oclear.containsMouse ? Color.mError || "#f44336" : Color.mOnSurfaceVariant }
                        MouseArea { id: oclear; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (pluginApi) { pluginApi.pluginSettings.ocrResult = ""; pluginApi.pluginSettings.ocrCapturePath = ""; pluginApi.saveSettings() }; if (root.main) root.main.activeTool = "" }
                            onEntered: TooltipService.show(oclear, "Clear result"); onExited: TooltipService.hide() }
                    }
                }

                Column {
                    width: parent.width; spacing: Style.marginS

                    Row {
                        width: parent.width; spacing: Style.marginS
                        Rectangle { width: 40; height: 1; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.verticalCenter: parent.verticalCenter }
                        NIcon { icon: "world"; color: Color.mOnSurfaceVariant; scale: 0.8 }
                        NText { text: "Translate"; color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS }
                        Rectangle { width: parent.width - 130; height: 1; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.verticalCenter: parent.verticalCenter }
                    }

                    NText {
                        visible: !root.transAvailable; width: parent.width
                        text: "translate-shell not found"
                        color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS; wrapMode: Text.WordWrap
                    }

                    Row {
                        width: parent.width; spacing: Style.marginS
                        visible: root.transAvailable

                        Item {
                            id: transLangSelector
                            width: parent.width - Style.marginS - transBtnRect.width; height: 34
                            property bool open: false
                            Rectangle {
                                anchors.fill: parent; radius: Style.radiusM; color: Color.mSurface
                                border.color: transLangSelector.open ? Color.mPrimary : (Style.capsuleBorderColor || "transparent")
                                border.width: transLangSelector.open ? 2 : (Style.capsuleBorderWidth || 1)
                                Row {
                                    anchors.fill: parent; anchors.leftMargin: Style.marginS; anchors.rightMargin: Style.marginS; spacing: Style.marginS
                                    NText { text: root.transLangs.find(l => l.code === root.selectedTransLang)?.name || "English"; color: Color.mOnSurface; pointSize: Style.fontSizeS; width: parent.width - 28; elide: Text.ElideRight; height: parent.height; verticalAlignment: Text.AlignVCenter }
                                    NIcon { icon: transLangSelector.open ? "chevron-up" : "chevron-down"; color: Color.mOnSurfaceVariant; anchors.verticalCenter: parent.verticalCenter }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: transLangSelector.open = !transLangSelector.open }
                            }
                            Rectangle {
                                id: langDropdown
                                visible: transLangSelector.open
                                width: transLangSelector.width; height: 180; x: 0; y: -height - 4; z: 999
                                radius: Style.radiusM; color: Color.mSurface
                                border.color: Color.mPrimary; border.width: 1; clip: true
                                Flickable {
                                    anchors.fill: parent; anchors.margins: 4; contentHeight: langDropCol.implicitHeight; clip: true
                                    Column {
                                        id: langDropCol; width: langDropdown.width - 8; spacing: 2
                                        Repeater {
                                            model: root.transLangs
                                            delegate: Rectangle {
                                                width: langDropCol.width; height: 30; radius: Style.radiusS
                                                color: li.containsMouse ? Color.mHover : root.selectedTransLang === modelData.code ? (Color.mPrimaryContainer || Color.mSurfaceVariant) : "transparent"
                                                NText { anchors.fill: parent; anchors.leftMargin: Style.marginS; text: modelData.name; color: root.selectedTransLang === modelData.code ? Color.mPrimary : Color.mOnSurface; pointSize: Style.fontSizeS; verticalAlignment: Text.AlignVCenter }
                                                MouseArea { id: li; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: { root.selectedTransLang = modelData.code; transLangSelector.open = false } }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: transBtnRect
                            height: 34; width: tbt.implicitWidth + Style.marginL * 2; radius: Style.radiusM
                            color: tbh.containsMouse ? Color.mPrimary : Color.mSurfaceVariant
                            border.color: Color.mPrimary; border.width: Style.capsuleBorderWidth || 1
                            NText { id: tbt; anchors.centerIn: parent; text: "Translate"; color: tbh.containsMouse ? Color.mOnPrimary : Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS }
                            MouseArea { id: tbh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { transLangSelector.open = false; root.main?.runTranslate(root.ocrResult, root.selectedTransLang) } }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 120 * Style.uiScaleRatio
                        radius: Style.radiusM; color: Color.mSurface; clip: true
                        border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                        visible: root.transAvailable && root.translateResult !== ""
                        Flickable {
                            id: trFlick; anchors.fill: parent; anchors.margins: Style.marginS
                            contentHeight: trText.implicitHeight; clip: true
                            interactive: trText.implicitHeight > trFlick.height
                            TextEdit {
                                id: trText; width: trFlick.width; text: root.translateResult
                                color: Color.mOnSurface; font.pointSize: Style.fontSizeS; wrapMode: TextEdit.WordWrap
                                horizontalAlignment: /[\u0600-\u06FF\u0590-\u05FF]/.test(root.translateResult) ? TextEdit.AlignRight : TextEdit.AlignLeft
                                selectByMouse: true; selectionColor: Color.mPrimary; selectedTextColor: Color.mOnPrimary
                                WheelHandler { onWheel: event => { trFlick.flick(0, event.angleDelta.y * 5); event.accepted = false } }
                            }
                        }
                        NIcon {
                            icon: "copy"; color: Color.mOnSurfaceVariant
                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Style.marginS
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { root.main?.copyToClipboard(root.translateResult); ToastService.showNotice("Translation copied") } }
                        }
                    }
                }
            }

            // ── QR Result ─────────────────────────────────
            Column {
                width: parent.width; spacing: Style.marginM
                visible: root.viewedTool === "qr" && root.qrResult !== ""

                Row {
                    width: parent.width; spacing: Style.marginS
                    NIcon { icon: "qrcode"; color: Color.mPrimary; anchors.verticalCenter: parent.verticalCenter }
                    NText { text: "QR"; color: Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS; anchors.verticalCenter: parent.verticalCenter }
                }

                Rectangle {
                    width: parent.width
                    height: Math.min(qrThumb.implicitHeight * (parent.width / Math.max(qrThumb.implicitWidth, 1)), 160 * Style.uiScaleRatio)
                    radius: Style.radiusM; color: "transparent"; clip: true
                    border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                    visible: root.qrCapturePath !== "" && root.qrResult !== "" && qrThumb.status === Image.Ready
                    Image { id: qrThumb; anchors.fill: parent; source: (root.qrCapturePath !== "" && root.qrResult !== "") ? ("file://" + root.qrCapturePath) : ""; fillMode: Image.PreserveAspectFit; smooth: true; cache: false }
                }

                Rectangle {
                    height: 26; width: qrBadge.implicitWidth + Style.marginM * 2; radius: Style.radiusS
                    color: Color.mPrimaryContainer || Color.mSurfaceVariant
                    NText { id: qrBadge; anchors.centerIn: parent; text: root.qrType === "url" ? "🔗 URL" : root.qrType === "wifi" ? "📶 WiFi" : root.qrType === "contact" ? "👤 Contact" : root.qrType === "email" ? "✉️ Email" : root.qrType === "otp" ? "🔐 OTP" : "📄 Text"; color: Color.mOnPrimaryContainer || Color.mOnSurface; font.weight: Font.Bold; pointSize: Style.fontSizeXS }
                }

                Column {
                    width: parent.width; spacing: Style.marginS
                    visible: root.qrType === "wifi"
                    Rectangle {
                        width: parent.width; height: 38; radius: Style.radiusM; color: Color.mSurface
                        border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                        Row { anchors.fill: parent; anchors.margins: Style.marginS; spacing: Style.marginS
                            NIcon { icon: "wifi"; color: Color.mPrimary }
                            NText { text: root.qrWifiName || "Unknown"; color: Color.mOnSurface; font.weight: Font.Bold; pointSize: Style.fontSizeS } }
                    }
                    Rectangle {
                        width: parent.width; height: 38; radius: Style.radiusM
                        color: wph.containsMouse ? Color.mHover : Color.mSurface
                        border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                        Row { anchors.fill: parent; anchors.margins: Style.marginS; spacing: Style.marginS
                            NIcon { icon: "key"; color: Color.mOnSurfaceVariant }
                            NText { text: root.qrWifiPass ? "••••••••" : "No password"; color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeS }
                            NIcon { icon: "copy"; color: Color.mOnSurfaceVariant } }
                        MouseArea { id: wph; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: root.qrWifiPass !== ""
                            onClicked: { root.main?.copyToClipboard(root.qrWifiPass); ToastService.showNotice("Password copied") } }
                    }
                }

                Rectangle {
                    width: parent.width; height: 120 * Style.uiScaleRatio
                    radius: Style.radiusM; color: Color.mSurface; clip: true
                    border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                    visible: root.qrType !== "wifi"
                    Flickable {
                        id: qrFlick; anchors.fill: parent; anchors.margins: Style.marginS
                        contentHeight: qrText.implicitHeight; clip: true
                        interactive: qrText.implicitHeight > qrFlick.height
                        TextEdit {
                            id: qrText; width: qrFlick.width; text: root.qrResult; wrapMode: TextEdit.WordWrap
                            color: Color.mOnSurface; font.pointSize: Style.fontSizeS
                            selectByMouse: true; selectionColor: Color.mPrimary; selectedTextColor: Color.mOnPrimary
                            WheelHandler { onWheel: event => { qrFlick.flick(0, event.angleDelta.y * 5); event.accepted = false } }
                        }
                    }
                }

                Row {
                    width: parent.width; spacing: Style.marginS
                    Rectangle {
                        width: parent.width - 46; height: 38; radius: Style.radiusM
                        color: qah.containsMouse ? Color.mPrimary : Color.mSurface
                        border.color: Color.mPrimary; border.width: Style.capsuleBorderWidth || 1
                        Row { anchors.centerIn: parent; spacing: Style.marginS
                            NIcon { icon: root.qrType === "url" ? "external-link" : root.qrType === "email" ? "mail" : "copy"; color: qah.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                            NText { text: root.qrType === "url" ? "Open URL" : root.qrType === "email" ? "Compose Email" : "Copy"; color: qah.containsMouse ? Color.mOnPrimary : Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS } }
                        MouseArea { id: qah; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (root.qrType === "url" || root.qrType === "email") Qt.openUrlExternally(root.qrResult); else { root.main?.copyToClipboard(root.qrResult); ToastService.showNotice("Copied") } } }
                    }
                    Rectangle {
                        width: 38; height: 38; radius: Style.radiusM
                        color: qch.containsMouse ? Color.mErrorContainer || "#ffcdd2" : Color.mSurface
                        border.color: qch.containsMouse ? Color.mError || "#f44336" : (Style.capsuleBorderColor || "transparent"); border.width: Style.capsuleBorderWidth || 1
                        NIcon { anchors.centerIn: parent; icon: "trash"; color: qch.containsMouse ? Color.mError || "#f44336" : Color.mOnSurfaceVariant }
                        MouseArea { id: qch; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (pluginApi) { pluginApi.pluginSettings.qrResult = ""; pluginApi.saveSettings() }; if (root.main) root.main.activeTool = "" } }
                    }
                }
            }

            // ── Palette Result ────────────────────────────
            Column {
                width: parent.width; spacing: Style.marginM
                visible: root.viewedTool === "palette" && root.paletteColors.length > 0

                Row {
                    width: parent.width; spacing: Style.marginS
                    NIcon { icon: "palette"; color: Color.mPrimary; anchors.verticalCenter: parent.verticalCenter }
                    NText { text: "Palette"; color: Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS; anchors.verticalCenter: parent.verticalCenter }
                }

                Flow {
                    width: parent.width; spacing: Style.marginS
                    Repeater {
                        model: root.paletteColors
                        delegate: Rectangle {
                            width: (mainCol.width - Style.marginS * 2) / 3 - Style.marginS
                            height: width * 0.7; radius: Style.radiusM; color: modelData
                            border.color: swatchBtn.containsMouse ? Color.mPrimary : (Style.capsuleBorderColor || "transparent")
                            border.width: swatchBtn.containsMouse ? 2 : (Style.capsuleBorderWidth || 1)
                            NText {
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 4; anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.toUpperCase(); pointSize: Style.fontSizeXS; color: "white"
                                style: Text.Outline; styleColor: "#00000066"
                            }
                            MouseArea { id: swatchBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { root.main?.copyToClipboard(modelData); ToastService.showNotice(modelData + " copied") }
                                onEntered: TooltipService.show(swatchBtn, modelData.toUpperCase() + " — click to copy"); onExited: TooltipService.hide() }
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: 36; radius: Style.radiusM
                    color: cssBtn.containsMouse ? Color.mPrimary : Color.mSurface
                    border.color: Color.mPrimary; border.width: Style.capsuleBorderWidth || 1
                    Row { anchors.centerIn: parent; spacing: Style.marginS
                        NIcon { icon: "copy"; color: cssBtn.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                        NText { text: "Copy as CSS vars"; color: cssBtn.containsMouse ? Color.mOnPrimary : Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS } }
                    MouseArea { id: cssBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { var css = root.paletteColors.map(function(c, i) { return "--color-" + (i+1) + ": " + c + ";" }).join("\n"); root.main?.copyToClipboard(css); ToastService.showNotice("CSS vars copied") } }
                }

                Rectangle {
                    width: parent.width; height: 36; radius: Style.radiusM
                    color: hexBtn.containsMouse ? Color.mSurfaceVariant : Color.mSurface
                    border.color: Style.capsuleBorderColor || "transparent"; border.width: Style.capsuleBorderWidth || 1
                    Row { anchors.centerIn: parent; spacing: Style.marginS
                        NIcon { icon: "list"; color: hexBtn.containsMouse ? Color.mOnSurface : Color.mOnSurfaceVariant }
                        NText { text: "Copy hex list"; color: hexBtn.containsMouse ? Color.mOnSurface : Color.mOnSurfaceVariant; font.weight: Font.Bold; pointSize: Style.fontSizeS } }
                    MouseArea { id: hexBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.main?.copyToClipboard(root.paletteColors.join("\n")); ToastService.showNotice("Hex list copied") } }
                }

                Rectangle {
                    width: parent.width; height: 36; radius: Style.radiusM
                    color: palClr.containsMouse ? Color.mErrorContainer || "#ffcdd2" : Color.mSurface
                    border.color: palClr.containsMouse ? Color.mError || "#f44336" : (Style.capsuleBorderColor || "transparent"); border.width: Style.capsuleBorderWidth || 1
                    Row { anchors.centerIn: parent; spacing: Style.marginS
                        NIcon { icon: "trash"; color: palClr.containsMouse ? Color.mError || "#f44336" : Color.mOnSurfaceVariant }
                        NText { text: "Clear"; color: palClr.containsMouse ? Color.mError || "#f44336" : Color.mOnSurfaceVariant; font.weight: Font.Bold; pointSize: Style.fontSizeS } }
                    MouseArea { id: palClr; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (pluginApi) { pluginApi.pluginSettings.paletteColors = []; pluginApi.saveSettings() }; root.viewedTool = "" } }
                }
            }

        } // mainCol
    } // panelContainer

    component ToolBtn: Item {
        id: btn
        property string icon: ""
        property string label: ""
        property string tooltip: ""
        property bool active: false
        property bool focused: false
        property bool running: false
        signal triggered()

        Column {
            anchors.centerIn: parent; spacing: 3
            Rectangle {
                width: Math.min(btn.width - 4, 44); height: Math.min(btn.width - 4, 44)
                radius: Style.radiusM; anchors.horizontalCenter: parent.horizontalCenter
                color: ba.containsMouse ? Color.mHover : Color.mSurface
                border.color: btn.active ? Color.mPrimary : btn.focused ? Color.mSecondary || Color.mPrimary : (Style.capsuleBorderColor || "transparent")
                border.width: (btn.active || btn.focused) ? 2 : (Style.capsuleBorderWidth || 1)
                Rectangle { anchors.fill: parent; radius: parent.radius; color: Color.mPrimary; opacity: btn.active ? 0.15 : btn.focused ? 0.08 : 0 }
                NIcon { anchors.centerIn: parent; icon: btn.icon; color: btn.active ? Color.mPrimary : btn.focused ? Color.mSecondary || Color.mPrimary : Color.mOnSurface }
                MouseArea { id: ba; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !btn.running
                    onClicked: btn.triggered()
                    onEntered: TooltipService.show(btn, btn.tooltip !== "" ? btn.tooltip : btn.label)
                    onExited: TooltipService.hide() }
            }
            NText {
                text: btn.label; pointSize: Style.fontSizeXS
                color: btn.active ? Color.mPrimary : btn.focused ? Color.mSecondary || Color.mPrimary : Color.mOnSurfaceVariant
                anchors.horizontalCenter: parent.horizontalCenter; width: btn.width
                horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            }
        }
    }
}
