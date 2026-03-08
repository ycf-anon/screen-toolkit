import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import qs.Services.UI

Variants {
    id: annotateVariants

    property string imagePath: "/tmp/screen-toolkit-annotate.png"
    property var mainInstance: null
    property bool isVisible: false

    property int regionX: 0
    property int regionY: 0
    property int regionW: 0
    property int regionH: 0

    // ── Zoom ───────────────────────────────────────
    property real zoomScale: 1.0
    property string lastRegion: ""

    function parseAndShow(regionStr, imgPath) {
        var parts = regionStr.trim().split(" ")
        if (parts.length < 2) return
        var xy = parts[0].split(",")
        var wh = parts[1].split("x")
        regionX = parseInt(xy[0]) || 0
        regionY = parseInt(xy[1]) || 0
        regionW = parseInt(wh[0]) || 400
        regionH = parseInt(wh[1]) || 300
        zoomScale = 1.0
        lastRegion = regionStr
        imagePath = imgPath
        _resetToken = !_resetToken
        isVisible = true
    }

    function parseAndShowZoomed(regionStr, imgPath, scale) {
        var parts = regionStr.trim().split(" ")
        if (parts.length < 2) return
        var xy = parts[0].split(",")
        var wh = parts[1].split("x")
        regionX = parseInt(xy[0]) || 0
        regionY = parseInt(xy[1]) || 0
        regionW = parseInt(wh[0]) || 400
        regionH = parseInt(wh[1]) || 300
        zoomScale = scale
        imagePath = imgPath
        _resetToken = !_resetToken
        isVisible = true
    }

    property bool _resetToken: false

    function hide() {
        isVisible = false
    }

    model: Quickshell.screens

    delegate: PanelWindow {
        id: overlayWin

        required property ShellScreen modelData
        screen: modelData

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        visible: annotateVariants.isVisible

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: annotateVariants.isVisible
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "noctalia-annotate"

        // ── State ──────────────────────────────────────
        property string tool: "pencil"
        property color drawColor: "#FF4444"
        property int drawSize: 3
        property var strokes: []
        property var currentStroke: null
        property bool drawing: false
        property bool textMode: false
        property bool isSaving: false
        property real textX: 0
        property real textY: 0
        property bool pixelImgReady: false
        property bool showPopover: false

        // ── Zoom state ─────────────────────────────────
        property real _pendingZoomScale: 1.0
        property real panX: 0.0
        property real panY: 0.0
        property real _panStartX: 0.0
        property real _panStartY: 0.0
        property real _panStartMouseX: 0.0
        property real _panStartMouseY: 0.0
        property bool isPanning: false

        // ── Zoom ───────────────────────────────────────
        property var _savedStrokes: []

        function requestZoom(scale) {
            var region = annotateVariants.lastRegion
            if (region === "") return
            if (scale === 1.0) {
                // Restore strokes and repaint
                overlayWin.strokes = overlayWin._savedStrokes.slice()
                overlayWin._savedStrokes = []
                overlayWin.panX = 0.0
                overlayWin.panY = 0.0
                annotateVariants.parseAndShow(region, "/tmp/screen-toolkit-annotate.png")
                drawCanvas.requestPaint()
                return
            }
            // First zoom in: save strokes and clear
            if (annotateVariants.zoomScale === 1.0) {
                overlayWin._savedStrokes = overlayWin.strokes.slice()
                overlayWin.strokes = []
                overlayWin.currentStroke = null
            }
            _pendingZoomScale = scale
            overlayWin.panX = 0.0
            overlayWin.panY = 0.0
            var newW = Math.round(annotateVariants.regionW * scale)
            var newH = Math.round(annotateVariants.regionH * scale)
            zoomProc.exec({ command: [
                "bash", "-c",
                "magick /tmp/screen-toolkit-annotate.png -resize " + newW + "x" + newH + "! /tmp/screen-toolkit-annotate-zoom.png 2>/dev/null"
            ]})
        }

        // ── Pixelated image for blur tool ──────────────
        Process {
            id: pixelateProc
            onExited: (code) => {
                if (code === 0) {
                    overlayWin.pixelImgReady = false
                    overlayWin.pixelImgReady = true
                }
            }
        }

        function preparePixelImage() {
            pixelImgReady = false
            pixelateProc.exec({ command: [
                "bash", "-c",
                "magick /tmp/screen-toolkit-annotate.png -scale 5% -scale 2000% /tmp/screen-toolkit-annotate-pixel.png"
            ]})
        }

        onPixelImgReadyChanged: {
            if (pixelImgReady) {
                drawCanvas.unloadImage("file:///tmp/screen-toolkit-annotate-pixel.png")
                drawCanvas.requestPaint()
            }
        }

        // ── Processes ──────────────────────────────────
        Process {
            id: zoomProc
            onExited: (code) => {
                if (code === 0) {
                    annotateVariants.parseAndShowZoomed(
                        annotateVariants.lastRegion,
                        "/tmp/screen-toolkit-annotate-zoom.png",
                        overlayWin._pendingZoomScale)
                }
            }
        }

        Process {
            id: copyProc
        }

        Process {
            id: saveProc
            onExited: (code) => {
                overlayWin.isSaving = false
                if (code === 0) {
                    ToastService.showNotice("Copied to clipboard", "", "copy")
                    annotateVariants.hide()
                } else {
                    ToastService.showError("Failed to save annotation")
                }
            }
        }

        Process {
            id: saveFileProc
            property string savedPath: ""
            onExited: (code) => {
                overlayWin.isSaving = false
                if (code === 0) {
                    ToastService.showNotice("Saved to ~/Pictures", saveFileProc.savedPath, "device-floppy")
                    annotateVariants.hide()
                } else {
                    ToastService.showError("Failed to save file")
                }
            }
        }

        // ── Keys ───────────────────────────────────────
        Shortcut {
            sequence: "Escape"
            onActivated: { overlayWin.strokes = []; annotateVariants.hide() }
        }

        // ── Dark overlay ───────────────────────────────
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.55)
            Rectangle {
                x: annotateVariants.regionX
                y: annotateVariants.regionY
                width: annotateVariants.regionW
                height: annotateVariants.regionH
                color: "transparent"
            }
            MouseArea {
                anchors.fill: parent
                onClicked: (mouse) => {
                    var ix = annotateVariants.regionX, iy = annotateVariants.regionY
                    var iw = annotateVariants.regionW, ih = annotateVariants.regionH
                    var inRegion = mouse.x >= ix && mouse.x <= ix+iw && mouse.y >= iy && mouse.y <= iy+ih
                    var inToolbar = mouse.x >= toolbar.x && mouse.x <= toolbar.x+toolbar.width
                                 && mouse.y >= toolbar.y && mouse.y <= toolbar.y+toolbar.height
                    var inPopover = overlayWin.showPopover
                                 && mouse.x >= popover.x && mouse.x <= popover.x+popover.width
                                 && mouse.y >= popover.y && mouse.y <= popover.y+popover.height
                    if (!inRegion && !inToolbar && !inPopover) {
                        overlayWin.strokes = []
                        annotateVariants.hide()
                    }
                }
            }
        }

        // ── Capture root ───────────────────────────────
        Item {
            id: captureRoot
            x: annotateVariants.regionX
            y: annotateVariants.regionY
            width: annotateVariants.regionW
            height: annotateVariants.regionH
            clip: true

            // ── Screenshot image (zoom+pan) ───────────
            Image {
                id: imgLoader
                width:  annotateVariants.zoomScale > 1.0
                        ? annotateVariants.regionW * annotateVariants.zoomScale
                        : annotateVariants.regionW
                height: annotateVariants.zoomScale > 1.0
                        ? annotateVariants.regionH * annotateVariants.zoomScale
                        : annotateVariants.regionH
                x: annotateVariants.zoomScale > 1.0
                   ? Math.max(annotateVariants.regionW - width,
                     Math.min(0, (annotateVariants.regionW - width) / 2 + overlayWin.panX))
                   : 0
                y: annotateVariants.zoomScale > 1.0
                   ? Math.max(annotateVariants.regionH - height,
                     Math.min(0, (annotateVariants.regionH - height) / 2 + overlayWin.panY))
                   : 0
                source: annotateVariants.isVisible ? "file://" + annotateVariants.imagePath : ""
                fillMode: Image.Stretch
                cache: false
                smooth: true
            }

            // ── Blur regions ───────────────────────────
            Repeater {
                model: overlayWin.strokes.filter(s => s.type === "blur" && !s.preview)
                delegate: Item {
                    x: Math.min(modelData.x1, modelData.x2)
                    y: Math.min(modelData.y1, modelData.y2)
                    width: Math.abs(modelData.x2 - modelData.x1)
                    height: Math.abs(modelData.y2 - modelData.y1)
                    clip: true
                    Image {
                        x: -parent.x
                        y: -parent.y
                        width: annotateVariants.regionW
                        height: annotateVariants.regionH
                        source: overlayWin.pixelImgReady ? "file:///tmp/screen-toolkit-annotate-pixel.png?" + Date.now() : ""
                        fillMode: Image.Stretch
                        cache: false
                        smooth: false
                    }
                }
            }
        }

        // ── Blur preview rect ──────────────────────────
        Rectangle {
            visible: annotateVariants.zoomScale <= 1.0 && overlayWin.drawing && overlayWin.currentStroke && overlayWin.currentStroke.type === "blur"
            x: annotateVariants.regionX + (overlayWin.currentStroke ? Math.min(overlayWin.currentStroke.x1, overlayWin.currentStroke.x2) : 0)
            y: annotateVariants.regionY + (overlayWin.currentStroke ? Math.min(overlayWin.currentStroke.y1, overlayWin.currentStroke.y2) : 0)
            width: overlayWin.currentStroke ? Math.abs(overlayWin.currentStroke.x2 - overlayWin.currentStroke.x1) : 0
            height: overlayWin.currentStroke ? Math.abs(overlayWin.currentStroke.y2 - overlayWin.currentStroke.y1) : 0
            color: "transparent"
            border.color: "#ffffff"
            border.width: 1.5
            opacity: 0.8
        }

        // ── "View only" zoom badge ─────────────────────
        Rectangle {
            visible: annotateVariants.zoomScale > 1.0
            x: annotateVariants.regionX + annotateVariants.regionW - width - 8
            y: annotateVariants.regionY + 8
            width: zoomBadgeRow.implicitWidth + 12
            height: 22
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.6)
            Row {
                id: zoomBadgeRow
                anchors.centerIn: parent
                spacing: 4
                NIcon { icon: "zoom-in"; color: "#ffffff" }
                NText { text: Math.round(annotateVariants.zoomScale) + "× — view only"; color: "#ffffff"; pointSize: Style.fontSizeXS }
            }
        }

        // ── Reset on hide ──────────────────────────────
        Connections {
            target: annotateVariants
            function onIsVisibleChanged() {
                if (!annotateVariants.isVisible) {
                    overlayWin.strokes = []
                    overlayWin._savedStrokes = []
                    overlayWin.currentStroke = null
                    overlayWin.drawing = false
                    overlayWin.textMode = false
                    overlayWin.showPopover = false
                    overlayWin.pixelImgReady = false
                    overlayWin.panX = 0.0
                    overlayWin.panY = 0.0
                    overlayWin.isPanning = false
                    drawCanvas.requestPaint()
                } else {
                    overlayWin.preparePixelImage()
                }
            }
        }

        // ── Drawing canvas — hidden while zoomed ───────
        // Strokes stay intact in memory, reappear instantly at 1x
        Canvas {
            id: drawCanvas
            x: annotateVariants.regionX
            y: annotateVariants.regionY
            width: annotateVariants.regionW
            height: annotateVariants.regionH
            visible: annotateVariants.zoomScale <= 1.0

            onImageLoaded: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var pixUrl = "file:///tmp/screen-toolkit-annotate-pixel.png"
                if (overlayWin.pixelImgReady && !isImageLoaded(pixUrl))
                    loadImage(pixUrl)

                for (var i = 0; i < overlayWin.strokes.length; i++)
                    drawStroke(ctx, overlayWin.strokes[i])
                if (overlayWin.currentStroke && overlayWin.drawing)
                    drawStroke(ctx, overlayWin.currentStroke)
            }

            function drawStroke(ctx, stroke) {
                ctx.strokeStyle = stroke.color
                ctx.fillStyle = stroke.color
                ctx.lineWidth = stroke.size
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                if (stroke.type === "blur" && !stroke.preview) {
                    var bx = Math.min(stroke.x1, stroke.x2)
                    var by = Math.min(stroke.y1, stroke.y2)
                    var bw = Math.abs(stroke.x2 - stroke.x1)
                    var bh = Math.abs(stroke.y2 - stroke.y1)
                    if (bw > 0 && bh > 0) {
                        var pixUrl = "file:///tmp/screen-toolkit-annotate-pixel.png"
                        if (isImageLoaded(pixUrl)) {
                            ctx.save()
                            ctx.beginPath(); ctx.rect(bx, by, bw, bh); ctx.clip()
                            ctx.drawImage(pixUrl, 0, 0, annotateVariants.regionW, annotateVariants.regionH)
                            ctx.restore()
                        }
                    }

                } else if (stroke.type === "pencil" && stroke.points.length > 1) {
                    ctx.beginPath()
                    ctx.moveTo(stroke.points[0].x, stroke.points[0].y)
                    for (var i = 1; i < stroke.points.length; i++)
                        ctx.lineTo(stroke.points[i].x, stroke.points[i].y)
                    ctx.stroke()

                } else if (stroke.type === "arrow") {
                    var dx = stroke.x2 - stroke.x1, dy = stroke.y2 - stroke.y1
                    var len = Math.sqrt(dx*dx + dy*dy)
                    if (len < 2) return
                    ctx.beginPath(); ctx.moveTo(stroke.x1, stroke.y1); ctx.lineTo(stroke.x2, stroke.y2); ctx.stroke()
                    var angle = Math.atan2(dy, dx), hs = Math.max(stroke.size * 4, 12)
                    ctx.beginPath()
                    ctx.moveTo(stroke.x2, stroke.y2)
                    ctx.lineTo(stroke.x2 - hs * Math.cos(angle - Math.PI/6), stroke.y2 - hs * Math.sin(angle - Math.PI/6))
                    ctx.lineTo(stroke.x2 - hs * Math.cos(angle + Math.PI/6), stroke.y2 - hs * Math.sin(angle + Math.PI/6))
                    ctx.closePath(); ctx.fill()

                } else if (stroke.type === "rect") {
                    ctx.beginPath()
                    ctx.strokeRect(stroke.x1, stroke.y1, stroke.x2 - stroke.x1, stroke.y2 - stroke.y1)

                } else if (stroke.type === "text") {
                    ctx.font = (stroke.size * 5 + 12) + "px sans-serif"
                    ctx.fillText(stroke.text, stroke.x1, stroke.y1)
                }
            }

            // Draw mouse area — only active at 1x (canvas is hidden at zoom > 1)
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: overlayWin.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor

                onPressed: (mouse) => {
                    overlayWin.showPopover = false
                    if (overlayWin.tool === "text") {
                        overlayWin.textX = mouse.x
                        overlayWin.textY = mouse.y
                        overlayWin.textMode = true
                        textInput.text = ""
                        textInput.forceActiveFocus()
                        return
                    }
                    overlayWin.drawing = true
                    if (overlayWin.tool === "pencil") {
                        overlayWin.currentStroke = {
                            type: "pencil", color: overlayWin.drawColor, size: overlayWin.drawSize,
                            points: [{ x: mouse.x, y: mouse.y }]
                        }
                    } else if (overlayWin.tool === "blur") {
                        overlayWin.currentStroke = {
                            type: "blur", color: overlayWin.drawColor, size: overlayWin.drawSize,
                            x1: mouse.x, y1: mouse.y, x2: mouse.x, y2: mouse.y, preview: true
                        }
                    } else {
                        overlayWin.currentStroke = {
                            type: overlayWin.tool, color: overlayWin.drawColor, size: overlayWin.drawSize,
                            x1: mouse.x, y1: mouse.y, x2: mouse.x, y2: mouse.y
                        }
                    }
                }

                onPositionChanged: (mouse) => {
                    if (!overlayWin.drawing || !overlayWin.currentStroke) return
                    if (overlayWin.tool === "pencil") {
                        var s = overlayWin.currentStroke
                        var pts = s.points.slice()
                        pts.push({ x: mouse.x, y: mouse.y })
                        overlayWin.currentStroke = { type: s.type, color: s.color, size: s.size, points: pts }
                    } else {
                        overlayWin.currentStroke = {
                            type: overlayWin.currentStroke.type,
                            color: overlayWin.currentStroke.color,
                            size: overlayWin.currentStroke.size,
                            x1: overlayWin.currentStroke.x1, y1: overlayWin.currentStroke.y1,
                            x2: mouse.x, y2: mouse.y,
                            preview: true
                        }
                    }
                    drawCanvas.requestPaint()
                }

                onReleased: {
                    if (!overlayWin.drawing || !overlayWin.currentStroke) return
                    overlayWin.drawing = false
                    var stroke = overlayWin.currentStroke
                    if (stroke.type === "blur") {
                        stroke = { type: "blur", color: stroke.color, size: stroke.size,
                                   x1: stroke.x1, y1: stroke.y1, x2: stroke.x2, y2: stroke.y2,
                                   preview: false }
                    }
                    var s = overlayWin.strokes.slice()
                    s.push(stroke)
                    overlayWin.strokes = s
                    overlayWin.currentStroke = null
                    drawCanvas.requestPaint()
                }
            }

            TextInput {
                id: textInput
                visible: overlayWin.textMode
                x: overlayWin.textX
                y: overlayWin.textY - height
                width: 300
                color: overlayWin.drawColor
                font.pixelSize: overlayWin.drawSize * 5 + 12
                font.bold: true
                Keys.onReturnPressed: commitText()
                Keys.onEscapePressed: { overlayWin.textMode = false; text = "" }
                function commitText() {
                    if (text.trim() !== "") {
                        var s = overlayWin.strokes.slice()
                        s.push({ type: "text", color: overlayWin.drawColor, size: overlayWin.drawSize,
                            x1: overlayWin.textX, y1: overlayWin.textY, text: text })
                        overlayWin.strokes = s
                        drawCanvas.requestPaint()
                    }
                    overlayWin.textMode = false; text = ""
                }
            }
        }

        // ── Pan mouse area — only shown when zoomed ────
        MouseArea {
            x: annotateVariants.regionX
            y: annotateVariants.regionY
            width: annotateVariants.regionW
            height: annotateVariants.regionH
            visible: annotateVariants.zoomScale > 1.0
            hoverEnabled: true
            cursorShape: overlayWin.isPanning ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            onPressed: (mouse) => {
                overlayWin.isPanning = true
                overlayWin._panStartX = overlayWin.panX
                overlayWin._panStartY = overlayWin.panY
                overlayWin._panStartMouseX = mouse.x
                overlayWin._panStartMouseY = mouse.y
            }
            onPositionChanged: (mouse) => {
                if (!overlayWin.isPanning) return
                overlayWin.panX = overlayWin._panStartX + (mouse.x - overlayWin._panStartMouseX)
                overlayWin.panY = overlayWin._panStartY + (mouse.y - overlayWin._panStartMouseY)
            }
            onReleased: overlayWin.isPanning = false
        }

        Rectangle {
            id: toolbar

            readonly property real spaceBelow: overlayWin.height - (annotateVariants.regionY + annotateVariants.regionH)
            readonly property real spaceAbove: annotateVariants.regionY
            readonly property real spaceRight: overlayWin.width - (annotateVariants.regionX + annotateVariants.regionW)
            readonly property bool useVertical: spaceBelow < 56 && spaceAbove < 56

            width:  useVertical ? 56 : (toolbarRowH.implicitWidth + Style.marginM * 2)
            height: useVertical ? (toolbarColV.implicitHeight + Style.marginM * 2) : 52

            x: useVertical
               ? (spaceRight >= 56
                  ? annotateVariants.regionX + annotateVariants.regionW + 8
                  : Math.max(8, annotateVariants.regionX - width - 8))
               : Math.max(8, Math.min(
                   annotateVariants.regionX + (annotateVariants.regionW - width) / 2,
                   overlayWin.width - width - 8))
            y: useVertical
               ? Math.max(8, Math.min(
                   annotateVariants.regionY + (annotateVariants.regionH - height) / 2,
                   overlayWin.height - height - 8))
               : (spaceBelow >= 56
                  ? annotateVariants.regionY + annotateVariants.regionH + 8
                  : Math.max(8, annotateVariants.regionY - height - 8))

            radius: Style.radiusL
            color: Color.mSurface
            border.color: Style.capsuleBorderColor || "transparent"
            border.width: Style.capsuleBorderWidth || 1

            // ── HORIZONTAL ────────────────────────────
            Row {
                id: toolbarRowH
                anchors.centerIn: parent
                spacing: Style.marginXS
                visible: !toolbar.useVertical

                Repeater {
                    model: [
                        { id: "pencil", icon: "pencil",         tooltip: "Draw freehand"         },
                        { id: "arrow",  icon: "arrow-up-right", tooltip: "Draw arrow"             },
                        { id: "rect",   icon: "square",         tooltip: "Draw rectangle"         },
                        { id: "text",   icon: "text-size",      tooltip: "Add text"               },
                        { id: "blur",   icon: "eye-off",        tooltip: "Pixelate region"        }
                    ]
                    delegate: Rectangle {
                        width: 34; height: 34; radius: Style.radiusS
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: annotateVariants.zoomScale > 1.0 ? 0.35 : 1.0
                        color: overlayWin.tool === modelData.id ? Color.mPrimary : (th.containsMouse ? Color.mHover : "transparent")
                        NIcon { anchors.centerIn: parent; icon: modelData.icon; color: overlayWin.tool === modelData.id ? Color.mOnPrimary : Color.mOnSurface }
                        MouseArea { id: th; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            enabled: annotateVariants.zoomScale <= 1.0
                            onClicked: {
                                if (overlayWin.textMode) textInput.commitText()
                                overlayWin.tool = modelData.id
                                overlayWin.textMode = false
                            }
                            onEntered: TooltipService.show(parent, modelData.tooltip)
                            onExited: TooltipService.hide() }
                    }
                }

                Rectangle { width: 1; height: 28; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.verticalCenter: parent.verticalCenter }

                // ── Zoom controls ─────────────────────
                Rectangle {
                    width: 28; height: 34; radius: Style.radiusS
                    anchors.verticalCenter: parent.verticalCenter
                    color: zoomOutH.containsMouse ? Color.mHover : "transparent"
                    enabled: annotateVariants.zoomScale > 1.0
                    opacity: enabled ? 1.0 : 0.3
                    NIcon { anchors.centerIn: parent; icon: "zoom-out"; color: Color.mOnSurface }
                    MouseArea { id: zoomOutH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: overlayWin.requestZoom(Math.max(1.0, annotateVariants.zoomScale - 1.0))
                        onEntered: TooltipService.show(parent, "Zoom out")
                        onExited: TooltipService.hide() }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: annotateVariants.zoomScale === 1.0 ? "1×" : Math.round(annotateVariants.zoomScale) + "×"
                    color: annotateVariants.zoomScale > 1.0 ? Color.mPrimary : Color.mOnSurfaceVariant
                    font.pixelSize: 11; font.bold: annotateVariants.zoomScale > 1.0
                    width: 22; horizontalAlignment: Text.AlignHCenter
                }

                Rectangle {
                    width: 28; height: 34; radius: Style.radiusS
                    anchors.verticalCenter: parent.verticalCenter
                    color: zoomInH.containsMouse ? Color.mHover : "transparent"
                    enabled: annotateVariants.zoomScale < 5.0
                    opacity: enabled ? 1.0 : 0.3
                    NIcon { anchors.centerIn: parent; icon: "zoom-in"; color: Color.mOnSurface }
                    MouseArea { id: zoomInH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: overlayWin.requestZoom(Math.min(5.0, annotateVariants.zoomScale + 1.0))
                        onEntered: TooltipService.show(parent, "Zoom in (view only)")
                        onExited: TooltipService.hide() }
                }

                Rectangle { width: 1; height: 28; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.verticalCenter: parent.verticalCenter }

                Rectangle {
                    width: 18; height: 18; radius: 9; anchors.verticalCenter: parent.verticalCenter
                    color: overlayWin.drawColor
                    border.color: overlayWin.showPopover ? Color.mPrimary : Qt.rgba(0,0,0,0.2)
                    border.width: overlayWin.showPopover ? 2 : 1
                    scale: colorBtn.containsMouse ? 1.1 : 1
                    Behavior on scale { NumberAnimation { duration: 80 } }
                    MouseArea { id: colorBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: overlayWin.showPopover = !overlayWin.showPopover
                        onEntered: TooltipService.show(parent, "Color & size")
                        onExited: TooltipService.hide() }
                }

                Rectangle { width: 1; height: 28; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.verticalCenter: parent.verticalCenter }

                Rectangle {
                    width: 34; height: 34; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                    color: undoH.containsMouse ? Color.mHover : "transparent"
                    NIcon { anchors.centerIn: parent; icon: "corner-up-left"; color: Color.mOnSurface }
                    MouseArea { id: undoH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (overlayWin.strokes.length > 0) { overlayWin.strokes = overlayWin.strokes.slice(0, -1); drawCanvas.requestPaint() } }
                        onEntered: TooltipService.show(parent, "Undo last stroke")
                        onExited: TooltipService.hide() }
                }

                Rectangle {
                    width: 34; height: 34; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                    color: clearH.containsMouse ? Color.mErrorContainer || "#ffcdd2" : "transparent"
                    NIcon { anchors.centerIn: parent; icon: "trash"; color: clearH.containsMouse ? Color.mError || "#f44336" : Color.mOnSurface }
                    MouseArea { id: clearH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { overlayWin.strokes = []; drawCanvas.requestPaint() }
                        onEntered: TooltipService.show(parent, "Clear all")
                        onExited: TooltipService.hide() }
                }

                Rectangle {
                    height: 36; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                    width: copyLabel.implicitWidth + 32
                    color: copyH.containsMouse ? Color.mPrimary : Color.mPrimaryContainer || Color.mSurfaceVariant
                    opacity: overlayWin.isSaving ? 0.5 : 1.0
                    Row { anchors.centerIn: parent; spacing: Style.marginXS
                        NIcon { icon: "copy"; color: copyH.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                        NText { id: copyLabel; text: overlayWin.isSaving ? "Copying..." : "Copy"; color: copyH.containsMouse ? Color.mOnPrimary : Color.mPrimary; font.weight: Font.Bold; pointSize: Style.fontSizeS }
                    }
                    MouseArea { id: copyH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !overlayWin.isSaving
                        onClicked: overlayWin.flattenAndCopy()
                        onEntered: TooltipService.show(parent, "Copy to clipboard")
                        onExited: TooltipService.hide() }
                }

                Rectangle {
                    height: 36; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                    width: saveLabel.implicitWidth + 32
                    color: saveH.containsMouse ? Color.mSecondary || Color.mPrimary : Color.mSurfaceVariant
                    opacity: overlayWin.isSaving ? 0.5 : 1.0
                    Row { anchors.centerIn: parent; spacing: Style.marginXS
                        NIcon { icon: "device-floppy"; color: saveH.containsMouse ? Color.mOnSecondary || Color.mOnPrimary : Color.mOnSurface }
                        NText { id: saveLabel; text: overlayWin.isSaving ? "Saving..." : "Save"; color: saveH.containsMouse ? Color.mOnSecondary || Color.mOnPrimary : Color.mOnSurface; font.weight: Font.Bold; pointSize: Style.fontSizeS }
                    }
                    MouseArea { id: saveH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !overlayWin.isSaving
                        onClicked: overlayWin.flattenAndSave()
                        onEntered: TooltipService.show(parent, "Save to ~/Pictures")
                        onExited: TooltipService.hide() }
                }

                Rectangle {
                    width: 34; height: 34; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                    color: closeH.containsMouse ? Color.mErrorContainer || "#ffcdd2" : "transparent"
                    NIcon { anchors.centerIn: parent; icon: "x"; color: Color.mOnSurface }
                    MouseArea { id: closeH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { overlayWin.strokes = []; annotateVariants.hide() } }
                }
            }

            // ── VERTICAL ──────────────────────────────
            Column {
                id: toolbarColV
                anchors.centerIn: parent
                spacing: Style.marginXS
                visible: toolbar.useVertical

                Repeater {
                    model: [
                        { id: "pencil", icon: "pencil",         tooltip: "Draw freehand"  },
                        { id: "arrow",  icon: "arrow-up-right", tooltip: "Draw arrow"      },
                        { id: "rect",   icon: "square",         tooltip: "Draw rectangle"  },
                        { id: "text",   icon: "text-size",      tooltip: "Add text"        },
                        { id: "blur",   icon: "eye-off",        tooltip: "Pixelate region" }
                    ]
                    delegate: Rectangle {
                        width: 34; height: 34; radius: Style.radiusS
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: annotateVariants.zoomScale > 1.0 ? 0.35 : 1.0
                        color: overlayWin.tool === modelData.id ? Color.mPrimary : (tv.containsMouse ? Color.mHover : "transparent")
                        NIcon { anchors.centerIn: parent; icon: modelData.icon; color: overlayWin.tool === modelData.id ? Color.mOnPrimary : Color.mOnSurface }
                        MouseArea { id: tv; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            enabled: annotateVariants.zoomScale <= 1.0
                            onClicked: {
                                if (overlayWin.textMode) textInput.commitText()
                                overlayWin.tool = modelData.id
                                overlayWin.textMode = false
                            }
                            onEntered: TooltipService.show(parent, modelData.tooltip)
                            onExited: TooltipService.hide() }
                    }
                }

                Rectangle { width: 28; height: 1; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.horizontalCenter: parent.horizontalCenter }

                // ── Zoom controls vertical ────────────
                Rectangle {
                    width: 28; height: 28; radius: Style.radiusS
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: zoomOutV.containsMouse ? Color.mHover : "transparent"
                    enabled: annotateVariants.zoomScale > 1.0; opacity: enabled ? 1.0 : 0.3
                    NIcon { anchors.centerIn: parent; icon: "zoom-out"; color: Color.mOnSurface }
                    MouseArea { id: zoomOutV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: overlayWin.requestZoom(Math.max(1.0, annotateVariants.zoomScale - 1.0))
                        onEntered: TooltipService.show(parent, "Zoom out")
                        onExited: TooltipService.hide() }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: annotateVariants.zoomScale === 1.0 ? "1×" : Math.round(annotateVariants.zoomScale) + "×"
                    color: annotateVariants.zoomScale > 1.0 ? Color.mPrimary : Color.mOnSurfaceVariant
                    font.pixelSize: 10; font.bold: annotateVariants.zoomScale > 1.0
                }

                Rectangle {
                    width: 28; height: 28; radius: Style.radiusS
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: zoomInV.containsMouse ? Color.mHover : "transparent"
                    enabled: annotateVariants.zoomScale < 5.0; opacity: enabled ? 1.0 : 0.3
                    NIcon { anchors.centerIn: parent; icon: "zoom-in"; color: Color.mOnSurface }
                    MouseArea { id: zoomInV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: overlayWin.requestZoom(Math.min(5.0, annotateVariants.zoomScale + 1.0))
                        onEntered: TooltipService.show(parent, "Zoom in (view only)")
                        onExited: TooltipService.hide() }
                }

                Rectangle { width: 28; height: 1; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.horizontalCenter: parent.horizontalCenter }

                Rectangle {
                    width: 18; height: 18; radius: 9; anchors.horizontalCenter: parent.horizontalCenter
                    color: overlayWin.drawColor
                    border.color: overlayWin.showPopover ? Color.mPrimary : Qt.rgba(0,0,0,0.2)
                    border.width: overlayWin.showPopover ? 2 : 1
                    scale: colorBtnV.containsMouse ? 1.1 : 1
                    Behavior on scale { NumberAnimation { duration: 80 } }
                    MouseArea { id: colorBtnV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: overlayWin.showPopover = !overlayWin.showPopover
                        onEntered: TooltipService.show(parent, "Color & size")
                        onExited: TooltipService.hide() }
                }

                Rectangle { width: 28; height: 1; color: Color.mOnSurfaceVariant; opacity: 0.3; anchors.horizontalCenter: parent.horizontalCenter }

                Rectangle {
                    width: 34; height: 34; radius: Style.radiusS; anchors.horizontalCenter: parent.horizontalCenter
                    color: undoV.containsMouse ? Color.mHover : "transparent"
                    NIcon { anchors.centerIn: parent; icon: "corner-up-left"; color: Color.mOnSurface }
                    MouseArea { id: undoV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (overlayWin.strokes.length > 0) { overlayWin.strokes = overlayWin.strokes.slice(0, -1); drawCanvas.requestPaint() } }
                        onEntered: TooltipService.show(parent, "Undo last stroke")
                        onExited: TooltipService.hide() }
                }

                Rectangle {
                    width: 34; height: 34; radius: Style.radiusS; anchors.horizontalCenter: parent.horizontalCenter
                    color: clearV.containsMouse ? Color.mErrorContainer || "#ffcdd2" : "transparent"
                    NIcon { anchors.centerIn: parent; icon: "trash"; color: clearV.containsMouse ? Color.mError || "#f44336" : Color.mOnSurface }
                    MouseArea { id: clearV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { overlayWin.strokes = []; drawCanvas.requestPaint() }
                        onEntered: TooltipService.show(parent, "Clear all")
                        onExited: TooltipService.hide() }
                }

                Rectangle {
                    width: 34; height: 34; radius: Style.radiusS; anchors.horizontalCenter: parent.horizontalCenter
                    color: copyV.containsMouse ? Color.mPrimary : Color.mPrimaryContainer || Color.mSurfaceVariant
                    opacity: overlayWin.isSaving ? 0.5 : 1.0
                    NIcon { anchors.centerIn: parent; icon: "copy"; color: copyV.containsMouse ? Color.mOnPrimary : Color.mPrimary }
                    MouseArea { id: copyV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !overlayWin.isSaving
                        onClicked: overlayWin.flattenAndCopy()
                        onEntered: TooltipService.show(parent, "Copy to clipboard")
                        onExited: TooltipService.hide() }
                }

                Rectangle {
                    width: 34; height: 34; radius: Style.radiusS; anchors.horizontalCenter: parent.horizontalCenter
                    color: saveV.containsMouse ? Color.mSecondary || Color.mPrimary : Color.mSurfaceVariant
                    opacity: overlayWin.isSaving ? 0.5 : 1.0
                    NIcon { anchors.centerIn: parent; icon: "device-floppy"; color: saveV.containsMouse ? Color.mOnPrimary : Color.mOnSurface }
                    MouseArea { id: saveV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !overlayWin.isSaving
                        onClicked: overlayWin.flattenAndSave()
                        onEntered: TooltipService.show(parent, "Save to ~/Pictures")
                        onExited: TooltipService.hide() }
                }

                Rectangle {
                    width: 34; height: 34; radius: Style.radiusS; anchors.horizontalCenter: parent.horizontalCenter
                    color: closeV.containsMouse ? Color.mErrorContainer || "#ffcdd2" : "transparent"
                    NIcon { anchors.centerIn: parent; icon: "x"; color: Color.mOnSurface }
                    MouseArea { id: closeV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { overlayWin.strokes = []; annotateVariants.hide() } }
                }
            }
        }

        // ── Color & Size Popover ───────────────────────
        Rectangle {
            id: popover
            visible: overlayWin.showPopover
            radius: Style.radiusL
            color: Color.mSurface
            border.color: Style.capsuleBorderColor || "transparent"
            border.width: Style.capsuleBorderWidth || 1

            width:  toolbar.useVertical ? (popColColors.implicitWidth + 12) : (popRowInner.implicitWidth + 16)
            height: toolbar.useVertical ? (popColColors.implicitHeight + 16) : (popRowInner.implicitHeight + 12)

            x: toolbar.useVertical
               ? (toolbar.spaceRight >= 56
                  ? toolbar.x + toolbar.width + 6
                  : toolbar.x - width - 6)
               : Math.max(8, Math.min(toolbar.x + (toolbar.width - width) / 2, overlayWin.width - width - 8))
            y: toolbar.useVertical
               ? Math.max(8, Math.min(toolbar.y + (toolbar.height - height) / 2, overlayWin.height - height - 8))
               : (toolbar.spaceAbove >= height + 10
                  ? toolbar.y - height - 6
                  : toolbar.y + toolbar.height + 6)

            Row {
                id: popRowInner
                anchors.centerIn: parent
                spacing: Style.marginS
                visible: !toolbar.useVertical

                Repeater {
                    model: ["#FF4444", "#FF8C00", "#FFD700", "#44FF88", "#44AAFF", "#CC44FF", "#FF44CC", "#FFFFFF", "#000000"]
                    delegate: Rectangle {
                        width: 20; height: 20; radius: 10
                        color: modelData
                        border.color: overlayWin.drawColor === modelData ? Color.mPrimary : Qt.rgba(0,0,0,0.15)
                        border.width: overlayWin.drawColor === modelData ? 2 : 1
                        scale: chH.containsMouse ? 1.2 : 1
                        Behavior on scale { NumberAnimation { duration: 80 } }
                        MouseArea { id: chH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { overlayWin.drawColor = modelData; overlayWin.showPopover = false } }
                    }
                }

                Rectangle { width: 1; height: 16; color: Color.mOnSurfaceVariant; opacity: 0.3 }

                Repeater {
                    model: [{ size: 2, label: "S" }, { size: 4, label: "M" }, { size: 7, label: "L" }]
                    delegate: Rectangle {
                        width: 28; height: 24; radius: Style.radiusS
                        color: overlayWin.drawSize === modelData.size ? Color.mPrimaryContainer || Color.mSurfaceVariant : (shH.containsMouse ? Color.mHover : "transparent")
                        border.color: overlayWin.drawSize === modelData.size ? Color.mPrimary : "transparent"; border.width: 1
                        Row { anchors.centerIn: parent; spacing: 3
                            Rectangle { width: modelData.size * 2; height: modelData.size * 2; radius: modelData.size; color: overlayWin.drawColor; anchors.verticalCenter: parent.verticalCenter }
                            NText { text: modelData.label; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: shH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { overlayWin.drawSize = modelData.size; overlayWin.showPopover = false } }
                    }
                }
            }

            Column {
                id: popColColors
                anchors.centerIn: parent
                spacing: Style.marginXS
                visible: toolbar.useVertical

                Repeater {
                    model: ["#FF4444", "#FF8C00", "#FFD700", "#44FF88", "#44AAFF", "#CC44FF", "#FF44CC", "#FFFFFF", "#000000"]
                    delegate: Rectangle {
                        width: 20; height: 20; radius: 10
                        color: modelData
                        border.color: overlayWin.drawColor === modelData ? Color.mPrimary : Qt.rgba(0,0,0,0.15)
                        border.width: overlayWin.drawColor === modelData ? 2 : 1
                        scale: chV.containsMouse ? 1.2 : 1
                        Behavior on scale { NumberAnimation { duration: 80 } }
                        MouseArea { id: chV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { overlayWin.drawColor = modelData; overlayWin.showPopover = false } }
                    }
                }

                Rectangle { width: 16; height: 1; color: Color.mOnSurfaceVariant; opacity: 0.3 }

                Repeater {
                    model: [{ size: 2, label: "S" }, { size: 4, label: "M" }, { size: 7, label: "L" }]
                    delegate: Rectangle {
                        width: 32; height: 24; radius: Style.radiusS
                        color: overlayWin.drawSize === modelData.size ? Color.mPrimaryContainer || Color.mSurfaceVariant : (shV.containsMouse ? Color.mHover : "transparent")
                        border.color: overlayWin.drawSize === modelData.size ? Color.mPrimary : "transparent"; border.width: 1
                        Row { anchors.centerIn: parent; spacing: 3
                            Rectangle { width: modelData.size * 2; height: modelData.size * 2; radius: modelData.size; color: overlayWin.drawColor; anchors.verticalCenter: parent.verticalCenter }
                            NText { text: modelData.label; pointSize: Style.fontSizeXS; color: Color.mOnSurfaceVariant; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { id: shV; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { overlayWin.drawSize = modelData.size; overlayWin.showPopover = false } }
                    }
                }
            }
        }

        // ── Save functions ─────────────────────────────
        function flattenAndSave() {
            if (overlayWin.isSaving) return
            overlayWin.isSaving = true
            var ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19)
            var filename = "annotate-" + ts + ".png"
            saveFileProc.savedPath = filename
            if (annotateVariants.zoomScale > 1.0) {
                // Zoomed: just save the zoomed image directly, no canvas overlay
                saveFileProc.exec({ command: [
                    "bash", "-c",
                    "mkdir -p ~/Pictures && cp " + annotateVariants.imagePath + " ~/Pictures/" + filename
                ]})
            } else {
                drawCanvas.grabToImage(function(result) {
                    result.saveToFile("/tmp/screen-toolkit-overlay.png")
                    saveFileProc.exec({ command: [
                        "bash", "-c",
                        "mkdir -p ~/Pictures && " +
                        "magick /tmp/screen-toolkit-annotate.png /tmp/screen-toolkit-overlay.png " +
                        "-composite ~/Pictures/" + filename + " && " +
                        "rm -f /tmp/screen-toolkit-overlay.png"
                    ]})
                })
            }
        }

        function flattenAndCopy() {
            if (overlayWin.isSaving) return
            overlayWin.isSaving = true
            if (annotateVariants.zoomScale > 1.0) {
                // Zoomed: copy the zoomed image directly via wl-copy
                copyProc.exec({ command: [
                    "bash", "-c",
                    "wl-copy < " + annotateVariants.imagePath + " && echo ok"
                ]})
                overlayWin.isSaving = false
                ToastService.showNotice("Copied to clipboard", "", "copy")
                annotateVariants.hide()
            } else {
                drawCanvas.grabToImage(function(result) {
                    result.saveToFile("/tmp/screen-toolkit-overlay.png")
                    saveProc.exec({ command: [
                        "bash", "-c",
                        "magick /tmp/screen-toolkit-annotate.png /tmp/screen-toolkit-overlay.png " +
                        "-composite /tmp/screen-toolkit-annotated.png && " +
                        "wl-copy < /tmp/screen-toolkit-annotated.png && " +
                        "rm -f /tmp/screen-toolkit-overlay.png"
                    ]})
                })
            }
        }
    }
}
