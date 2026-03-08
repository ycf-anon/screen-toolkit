import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import qs.Services.UI

Variants {
    id: measureVariants

    property bool isVisible: false

    function show() { isVisible = true }
    function hide() { isVisible = false }

    model: Quickshell.screens

    delegate: PanelWindow {
        id: overlayWin

        required property ShellScreen modelData
        screen: modelData

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        visible: measureVariants.isVisible

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: measureVariants.isVisible
            ? WlrKeyboardFocus.Exclusive
            : WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "noctalia-measure"

        Shortcut {
            sequence: "Escape"
            onActivated: measureVariants.hide()
        }

        // ── State ──────────────────────────────────────
        property bool measuring: false
        property var current: null
        property var pinned: []
        property bool _isShooting: false

        readonly property var palette: [
            "#A78BFA", "#34D399", "#F87171", "#FBBF24",
            "#60A5FA", "#F472B6", "#A3E635", "#FB923C"
        ]
        function colorForIndex(i) { return palette[i % palette.length] }

        property real x1: 0; property real y1: 0
        property real x2: 0; property real y2: 0

        readonly property real curW: current ? Math.abs(current.x2 - current.x1) : 0
        readonly property real curH: current ? Math.abs(current.y2 - current.y1) : 0
        readonly property real curDist: Math.round(Math.sqrt(curW*curW + curH*curH))

        onMeasuringChanged: measureCanvas.requestPaint()
        onCurrentChanged:   measureCanvas.requestPaint()
        onPinnedChanged:    measureCanvas.requestPaint()

        function doPin() {
            if (!current) return
            var p = pinned.slice()
            p.push({ x1: current.x1, y1: current.y1, x2: current.x2, y2: current.y2, color: colorForIndex(p.length) })
            pinned = p
            current = null
        }

        function removePinned(i) {
            var p = pinned.slice()
            p.splice(i, 1)
            for (var j = 0; j < p.length; j++)
                p[j] = { x1: p[j].x1, y1: p[j].y1, x2: p[j].x2, y2: p[j].y2, color: colorForIndex(j) }
            pinned = p
        }

        function clearAll() { pinned = [] }

        // ── Screenshot ─────────────────────────────────
        property var _shotMeasure: null
        property string _shotColor: "#ffffff"

        Process {
            id: shotProc
            onExited: (code) => {
                overlayWin._isShooting = false
                measureVariants.isVisible = true
                if (code === 0)
                    ToastService.showNotice(mainInstance.pluginApi.tr("messages.measure-saved"), "", "camera")
                else
                    ToastService.showError(mainInstance.pluginApi.tr("messages.measure-failed"))
            }
        }

        Timer {
            id: shotTimer
            interval: 400
            repeat: false
            onTriggered: {
                var m = overlayWin._shotMeasure
                if (!m) { overlayWin._isShooting = false; measureVariants.isVisible = true; return }

                // grim uses LOGICAL pixels — no dpr multiplication
                var pad = 24
                var minX = Math.min(m.x1, m.x2)
                var minY = Math.min(m.y1, m.y2)
                var maxX = Math.max(m.x1, m.x2)
                var maxY = Math.max(m.y1, m.y2)

                // Always positive — never use overlayWin.width in rw calculation
                var rx = Math.round(Math.max(0, minX - pad))
                var ry = Math.round(Math.max(0, minY - pad))
                var rw = Math.round(maxX + pad) - rx
                var rh = Math.round(maxY + pad) - ry

                // Draw coords relative to crop (also logical)
                var lx1 = Math.round(m.x1 - rx)
                var ly1 = Math.round(m.y1 - ry)
                var lx2 = Math.round(m.x2 - rx)
                var ly2 = Math.round(m.y2 - ry)
                var lw  = Math.abs(lx2 - lx1)
                var lh  = Math.abs(ly2 - ly1)
                var col = overlayWin._shotColor

                // Build script lines — written to file, no shell escaping needed
                var L = []
                L.push("#!/bin/bash")
                L.push("exec &>/tmp/measure-shot.log")   // log both stdout+stderr from start
                L.push("CROP=/tmp/measure-crop.png")
                L.push("OUT=/tmp/measure-out.png")
                L.push("")
                L.push("grim -g '" + rx + "," + ry + " " + rw + "x" + rh + "' \"$CROP\" || { echo 'grim failed'; exit 1; }")
                L.push("")
                L.push("magick \"$CROP\" \\")
                L.push("  -strokewidth 1 -stroke 'rgba(255,255,255,0.3)' -fill none \\")
                L.push("  -draw 'rectangle " + Math.min(lx1,lx2) + "," + Math.min(ly1,ly2) + " " + Math.max(lx1,lx2) + "," + Math.max(ly1,ly2) + "' \\")
                L.push("  -strokewidth 2 -stroke '" + col + "' -fill '" + col + "' \\")
                L.push("  -draw 'line " + lx1 + "," + ly1 + " " + lx2 + "," + ly2 + "' \\")
                L.push("  -fill '" + col + "' -stroke none \\")
                L.push("  -draw 'circle " + lx1 + "," + ly1 + " " + (lx1+5) + "," + ly1 + "' \\")
                L.push("  -draw 'circle " + lx2 + "," + ly2 + " " + (lx2+5) + "," + ly2 + "' \\")

                if (lw > 20) {
                    var mx  = Math.round((Math.min(lx1,lx2) + Math.max(lx1,lx2)) / 2)
                    var tty = Math.max(14, Math.min(ly1,ly2) - 10)
                    L.push("  -fill white -stroke none -pointsize 13 \\")
                    L.push("  -draw 'text " + mx + "," + tty + " \"" + lw + "px\"' \\")
                }
                if (lh > 20) {
                    var midy = Math.round((Math.min(ly1,ly2) + Math.max(ly1,ly2)) / 2)
                    var ttx  = Math.max(14, Math.min(lx1,lx2) - 10)
                    L.push("  -draw 'text " + ttx + "," + midy + " \"" + lh + "px\"' \\")
                }

                L.push("  \"$OUT\" || { echo 'magick failed'; exit 1; }")
                L.push("")
                L.push("mkdir -p \"$HOME/Pictures\"")
                L.push("cp \"$OUT\" \"$HOME/Pictures/measure-$(date +%s).png\" || { echo 'cp failed'; exit 1; }")
                L.push("wl-copy -t image/png < \"$OUT\"")
                L.push("rm -f \"$CROP\" \"$OUT\"")
                L.push("echo 'done'")

                var script = L.join("\n")
                shotProc.exec({
                    command: [
                        "python3", "-c",
                        "import subprocess\n" +
                        "open('/tmp/measure-shot.sh','w').write(" + JSON.stringify(script) + ")\n" +
                        "exit(subprocess.run(['bash','/tmp/measure-shot.sh']).returncode)"
                    ]
                })
            }
        }

        function doScreenshot(m, color) {
            if (_isShooting) return
            _shotMeasure = m
            _shotColor   = color || "#ffffff"
            _isShooting  = true
            measureVariants.isVisible = false
            shotTimer.restart()
        }

        Connections {
            target: measureVariants
            function onIsVisibleChanged() {
                if (!measureVariants.isVisible && !overlayWin._isShooting) {
                    overlayWin.measuring = false
                    overlayWin.current = null
                    overlayWin.pinned = []
                }
            }
        }

        // ── Dark overlay ───────────────────────────────
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)

            Column {
                anchors.centerIn: parent
                spacing: Style.marginS
                visible: !overlayWin.measuring && !overlayWin.current && overlayWin.pinned.length === 0
                NIcon { icon: "ruler"; color: "white"; anchors.horizontalCenter: parent.horizontalCenter; scale: 2 }
                NText {
                    text: "Click and drag to measure"
                    color: "white"; font.weight: Font.Bold; pointSize: Style.fontSizeL
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                NText {
                    text: "Pin to keep it · drag again to replace · ESC to close"
                    color: Qt.rgba(1,1,1,0.5); pointSize: Style.fontSizeS
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                hoverEnabled: true

                onPositionChanged: (mouse) => {
                    if (overlayWin.measuring) {
                        overlayWin.x2 = mouse.x
                        overlayWin.y2 = mouse.y
                        measureCanvas.requestPaint()
                    }
                }

                onPressed: (mouse) => {
                    overlayWin.measuring = true
                    overlayWin.current = null
                    overlayWin.x1 = mouse.x; overlayWin.y1 = mouse.y
                    overlayWin.x2 = mouse.x; overlayWin.y2 = mouse.y
                }

                onReleased: (mouse) => {
                    overlayWin.x2 = mouse.x; overlayWin.y2 = mouse.y
                    overlayWin.measuring = false
                    var dist = Math.sqrt(
                        Math.pow(overlayWin.x2 - overlayWin.x1, 2) +
                        Math.pow(overlayWin.y2 - overlayWin.y1, 2))
                    if (dist > 4)
                        overlayWin.current = { x1: overlayWin.x1, y1: overlayWin.y1, x2: overlayWin.x2, y2: overlayWin.y2 }
                    else
                        overlayWin.current = null
                }
            }
        }

        // ── Canvas ─────────────────────────────────────
        Canvas {
            id: measureCanvas
            anchors.fill: parent

            function drawLine(ctx, m, color) {
                var x1 = m.x1, y1 = m.y1, x2 = m.x2, y2 = m.y2
                var w = Math.abs(x2-x1), h = Math.abs(y2-y1)

                ctx.save()
                ctx.strokeStyle = "rgba(255,255,255,0.2)"; ctx.lineWidth = 1; ctx.setLineDash([4,4])
                ctx.strokeRect(Math.min(x1,x2), Math.min(y1,y2), w, h)
                ctx.restore()

                ctx.fillStyle = color
                ;[[x1,y1],[x2,y2],[x1,y2],[x2,y1]].forEach(function(pt) {
                    ctx.beginPath(); ctx.arc(pt[0],pt[1],3,0,Math.PI*2); ctx.fill()
                })

                ctx.save()
                ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.setLineDash([])
                ctx.beginPath(); ctx.moveTo(x1,y1); ctx.lineTo(x2,y2); ctx.stroke()
                ctx.restore()

                ctx.fillStyle = color
                ;[[x1,y1],[x2,y2]].forEach(function(pt) {
                    ctx.beginPath(); ctx.arc(pt[0],pt[1],5,0,Math.PI*2); ctx.fill()
                })

                if (w > 20) {
                    var midX = (Math.min(x1,x2)+Math.max(x1,x2))/2
                    var ty = Math.min(y1,y2)-12
                    ctx.save(); ctx.strokeStyle="rgba(255,255,255,0.5)"; ctx.lineWidth=1; ctx.setLineDash([])
                    ctx.beginPath(); ctx.moveTo(Math.min(x1,x2),ty); ctx.lineTo(Math.max(x1,x2),ty); ctx.stroke(); ctx.restore()
                    ctx.fillStyle="white"; ctx.font="bold 11px sans-serif"; ctx.textAlign="center"
                    ctx.fillText(Math.round(w)+"px", midX, ty-4)
                }

                if (h > 20) {
                    var midY = (Math.min(y1,y2)+Math.max(y1,y2))/2
                    var tx = Math.min(x1,x2)-12
                    ctx.save(); ctx.strokeStyle="rgba(255,255,255,0.5)"; ctx.lineWidth=1; ctx.setLineDash([])
                    ctx.beginPath(); ctx.moveTo(tx,Math.min(y1,y2)); ctx.lineTo(tx,Math.max(y1,y2)); ctx.stroke(); ctx.restore()
                    ctx.fillStyle="white"; ctx.font="bold 11px sans-serif"; ctx.textAlign="center"
                    ctx.save(); ctx.translate(tx-4,midY); ctx.rotate(-Math.PI/2)
                    ctx.fillText(Math.round(h)+"px",0,0); ctx.restore()
                }
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0,0,width,height)
                for (var i = 0; i < overlayWin.pinned.length; i++)
                    drawLine(ctx, overlayWin.pinned[i], overlayWin.pinned[i].color)
                if (overlayWin.measuring)
                    drawLine(ctx, {x1:overlayWin.x1,y1:overlayWin.y1,x2:overlayWin.x2,y2:overlayWin.y2}, "#ffffff")
                if (overlayWin.current)
                    drawLine(ctx, overlayWin.current, "#ffffff")
            }
        }

        // ── Active card ────────────────────────────────
        Rectangle {
            id: activeCard
            visible: overlayWin.current !== null && !overlayWin.measuring
            x: overlayWin.current
               ? Math.max(8, Math.min((overlayWin.current.x1+overlayWin.current.x2)/2 - width/2, overlayWin.width-width-8))
               : 0
            y: {
                if (!overlayWin.current) return 0
                var cy = (overlayWin.current.y1+overlayWin.current.y2)/2
                return (cy - height - 16 > 8) ? cy - height - 16 : cy + 16
            }
            width: activeRow.implicitWidth + Style.marginL * 2
            height: activeRow.implicitHeight + Style.marginM * 2
            radius: Style.radiusL
            color: Color.mSurface
            border.color: "white"; border.width: 2

            Row {
                id: activeRow
                anchors.centerIn: parent
                spacing: Style.marginS

                Column {
                    spacing: 1; anchors.verticalCenter: parent.verticalCenter
                    NText { text: overlayWin.curDist + " px"; color: Color.mOnSurface; font.weight: Font.Bold; pointSize: Style.fontSizeM; anchors.horizontalCenter: parent.horizontalCenter }
                    NText { text: Math.round(overlayWin.curW) + " × " + Math.round(overlayWin.curH); color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS; anchors.horizontalCenter: parent.horizontalCenter }
                }

                Rectangle {
                    width: 28; height: 28; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                    color: acopyBtn.containsMouse ? Color.mPrimary : Color.mSurfaceVariant
                    NIcon { anchors.centerIn: parent; icon: "copy"; color: acopyBtn.containsMouse ? Color.mOnPrimary : Color.mOnSurface; scale: 0.85 }
                    MouseArea { id: acopyBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { measureVariants.copyResult(overlayWin.curDist + "px (" + Math.round(overlayWin.curW) + "×" + Math.round(overlayWin.curH) + ")"); ToastService.showNotice(mainInstance.pluginApi.tr("messages.measure-copied")) }
                        onEntered: TooltipService.show(acopyBtn, "Copy measurement"); onExited: TooltipService.hide()
                    }
                }

                Rectangle {
                    width: 28; height: 28; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                    color: ascreenshotBtn.containsMouse ? Color.mPrimary : Color.mSurfaceVariant
                    NIcon { anchors.centerIn: parent; icon: "camera"; color: ascreenshotBtn.containsMouse ? Color.mOnPrimary : Color.mOnSurface; scale: 0.85 }
                    MouseArea { id: ascreenshotBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: overlayWin.doScreenshot(overlayWin.current, "#ffffff")
                        onEntered: TooltipService.show(ascreenshotBtn, "Screenshot with lines"); onExited: TooltipService.hide()
                    }
                }

                Rectangle {
                    width: 28; height: 28; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                    color: pinBtn.containsMouse ? Color.mPrimary : Color.mSurfaceVariant
                    NIcon { anchors.centerIn: parent; icon: "pin"; color: pinBtn.containsMouse ? Color.mOnPrimary : Color.mOnSurface; scale: 0.85 }
                    MouseArea { id: pinBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { overlayWin.doPin(); ToastService.showNotice(mainInstance.pluginApi.tr("messages.measure-pinned")) }
                        onEntered: TooltipService.show(pinBtn, "Pin"); onExited: TooltipService.hide()
                    }
                }

                Rectangle {
                    width: 28; height: 28; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                    color: discardBtn.containsMouse ? Color.mErrorContainer || "#ffcdd2" : Color.mSurfaceVariant
                    NIcon { anchors.centerIn: parent; icon: "x"; color: discardBtn.containsMouse ? Color.mError || "#f44336" : Color.mOnSurface; scale: 0.85 }
                    MouseArea { id: discardBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { overlayWin.current = null; if (overlayWin.pinned.length === 0) measureVariants.hide() }
                        onEntered: TooltipService.show(discardBtn, "Discard"); onExited: TooltipService.hide()
                    }
                }
            }
        }

        // ── Pinned cards ───────────────────────────────
        Repeater {
            model: overlayWin.pinned
            delegate: Rectangle {
                readonly property var mdata: modelData
                readonly property int myIdx: index
                readonly property real mw: Math.abs(mdata.x2 - mdata.x1)
                readonly property real mh: Math.abs(mdata.y2 - mdata.y1)
                readonly property real mdist: Math.round(Math.sqrt(mw*mw + mh*mh))

                x: Math.max(8, Math.min((mdata.x1+mdata.x2)/2 - width/2, overlayWin.width-width-8))
                y: {
                    var cy = (mdata.y1+mdata.y2)/2
                    return (cy - height - 16 > 8) ? cy - height - 16 : cy + 16
                }
                width: pinnedRow.implicitWidth + Style.marginL * 2
                height: pinnedRow.implicitHeight + Style.marginM * 2
                radius: Style.radiusL
                color: Color.mSurface
                border.color: mdata.color; border.width: 2

                Row {
                    id: pinnedRow
                    anchors.centerIn: parent
                    spacing: Style.marginS

                    Rectangle { width: 10; height: 10; radius: 5; color: mdata.color; anchors.verticalCenter: parent.verticalCenter }

                    Column {
                        spacing: 1; anchors.verticalCenter: parent.verticalCenter
                        NText { text: mdist + " px"; color: Color.mOnSurface; font.weight: Font.Bold; pointSize: Style.fontSizeM; anchors.horizontalCenter: parent.horizontalCenter }
                        NText { text: Math.round(mw) + " × " + Math.round(mh); color: Color.mOnSurfaceVariant; pointSize: Style.fontSizeXS; anchors.horizontalCenter: parent.horizontalCenter }
                    }

                    Rectangle {
                        width: 26; height: 26; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                        color: pcopyBtn.containsMouse ? Color.mPrimary : Color.mSurfaceVariant
                        NIcon { anchors.centerIn: parent; icon: "copy"; color: pcopyBtn.containsMouse ? Color.mOnPrimary : Color.mOnSurface; scale: 0.8 }
                        MouseArea { id: pcopyBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { measureVariants.copyResult(mdist + "px (" + Math.round(mw) + "×" + Math.round(mh) + ")"); ToastService.showNotice(mainInstance.pluginApi.tr("messages.measure-copied")) }
                            onEntered: TooltipService.show(pcopyBtn, "Copy"); onExited: TooltipService.hide()
                        }
                    }

                    Rectangle {
                        width: 26; height: 26; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                        color: pscreenshotBtn.containsMouse ? Color.mPrimary : Color.mSurfaceVariant
                        NIcon { anchors.centerIn: parent; icon: "camera"; color: pscreenshotBtn.containsMouse ? Color.mOnPrimary : Color.mOnSurface; scale: 0.8 }
                        MouseArea { id: pscreenshotBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: overlayWin.doScreenshot(mdata, mdata.color)
                            onEntered: TooltipService.show(pscreenshotBtn, "Screenshot with lines"); onExited: TooltipService.hide()
                        }
                    }

                    Rectangle {
                        width: 26; height: 26; radius: Style.radiusS; anchors.verticalCenter: parent.verticalCenter
                        color: premoveBtn.containsMouse ? Color.mErrorContainer || "#ffcdd2" : Color.mSurfaceVariant
                        NIcon { anchors.centerIn: parent; icon: "x"; color: premoveBtn.containsMouse ? Color.mError || "#f44336" : Color.mOnSurface; scale: 0.8 }
                        MouseArea { id: premoveBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: overlayWin.removePinned(myIdx)
                            onEntered: TooltipService.show(premoveBtn, "Remove"); onExited: TooltipService.hide()
                        }
                    }
                }
            }
        }

        // ── Clear all ──────────────────────────────────
        Rectangle {
            visible: overlayWin.pinned.length >= 2
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 32
            width: clearRow.implicitWidth + Style.marginL * 2
            height: 38; radius: Style.radiusM
            color: clearAllBtn.containsMouse ? Color.mErrorContainer || "#ffcdd2" : Color.mSurface
            border.color: Color.mError || "#f44336"; border.width: 1
            Row {
                id: clearRow; anchors.centerIn: parent; spacing: Style.marginS
                NIcon { icon: "trash"; color: Color.mError || "#f44336" }
                NText { text: "Clear all"; color: Color.mError || "#f44336"; font.weight: Font.Bold; pointSize: Style.fontSizeS }
            }
            MouseArea { id: clearAllBtn; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: overlayWin.clearAll()
            }
        }
    }

    property var mainInstance: null
    function copyResult(txt) {
        if (mainInstance) mainInstance.copyToClipboard(txt)
    }
}
