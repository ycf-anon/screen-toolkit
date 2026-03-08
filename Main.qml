import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

    property bool isRunning: false
    property string activeTool: ""
    property string pendingLangStr: "eng"
    property string pendingTool: ""

    readonly property string regionFile: "/tmp/screen-toolkit-region.txt"

    // ── Settings shortcuts (mirrors official pattern) ─────────
    readonly property string selectedOcrLang: pluginApi?.pluginSettings?.selectedOcrLang || "eng"

    // ── Capability detection ──────────────────────────────────
    property bool _capsDetected: false
    property var _detectedLangs: []

    Component.onCompleted: {
        if (!_capsDetected) {
            _capsDetected = true
            detectCapabilities()
        }
    }

    // ── Processes ─────────────────────────────────────────────

    Process {
        id: detectLangsProc
        stdout: StdioCollector {}
        onExited: (code) => {
            var lines = detectLangsProc.stdout.text.trim().split("\n")
            root._detectedLangs = []
            for (var i = 0; i < lines.length; i++) {
                var file = lines[i].trim()
                if (file === "") continue
                var match = file.match(/\/([a-zA-Z_]+)\.traineddata$/)
                if (match) {
                    var lang = match[1]
                    if (lang !== "osd" && lang !== "equ" && !root._detectedLangs.includes(lang))
                        root._detectedLangs.push(lang)
                }
            }
            if (pluginApi && root._detectedLangs.length > 0) {
                pluginApi.pluginSettings.installedLangs = root._detectedLangs.slice()
                pluginApi.saveSettings()
            }
        }
    }

    Process {
        id: detectTransProc
        stdout: StdioCollector {}
        onExited: (code) => {
            var path = detectTransProc.stdout.text.trim()
            if (pluginApi) {
                pluginApi.pluginSettings.transAvailable = path !== "" && path.startsWith("/")
                pluginApi.saveSettings()
            }
        }
    }

    Process {
        id: colorPickerProc
        stdout: StdioCollector {}
        onExited: (code) => {
            root.isRunning = false
            if (code !== 0 || colorPickerProc.stdout.text.trim() === "") {
                root.activeTool = ""
                ToastService.showError(pluginApi.tr("messages.picker-cancelled"))
                return
            }
            var line  = colorPickerProc.stdout.text.trim()
            var parts = line.split("|")
            var hex   = parts[0]
            var capturePath = parts.length > 1 ? parts[1] : ""
            if (hex.length !== 7 || hex.charAt(0) !== "#") {
                root.activeTool = ""
                ToastService.showError(pluginApi.tr("messages.picker-cancelled"))
                return
            }
            var r = parseInt(hex.slice(1, 3), 16)
            var g = parseInt(hex.slice(3, 5), 16)
            var b = parseInt(hex.slice(5, 7), 16)
            var rgb = "rgb(" + r + ", " + g + ", " + b + ")"
            // HSV
            var rn = r/255, gn = g/255, bn = b/255
            var max = Math.max(rn,gn,bn), min = Math.min(rn,gn,bn)
            var d = max - min, hh = 0
            var sv = (max === 0) ? 0 : d / max
            var vv = max
            if (d !== 0) {
                if      (max === rn) hh = ((gn-bn)/d + 6) % 6
                else if (max === gn) hh = (bn-rn)/d + 2
                else                 hh = (rn-gn)/d + 4
                hh = Math.round(hh * 60)
            }
            var hsv = "hsv(" + hh + ", " + Math.round(sv*100) + "%, " + Math.round(vv*100) + "%)"
            // HSL
            var l  = (max + min) / 2
            var sl = (d === 0) ? 0 : d / (1 - Math.abs(2*l - 1))
            var hsl = "hsl(" + hh + ", " + Math.round(sl*100) + "%, " + Math.round(l*100) + "%)"
            if (pluginApi) {
                pluginApi.pluginSettings.resultHex = hex
                pluginApi.pluginSettings.resultRgb = rgb
                pluginApi.pluginSettings.resultHsv = hsv
                pluginApi.pluginSettings.resultHsl = hsl
                pluginApi.pluginSettings.colorCapturePath = capturePath
                var history = pluginApi.pluginSettings.colorHistory || []
                history = [hex].concat(history.filter(c => c !== hex)).slice(0, 8)
                pluginApi.pluginSettings.colorHistory = history
                pluginApi.saveSettings()
            }
            root.activeTool = "colorpicker"
            if (pluginApi) pluginApi.withCurrentScreen(screen => pluginApi.openPanel(screen))
        }
    }

    Process {
        id: ocrProc
        stdout: StdioCollector {}
        onExited: (code) => {
            root.isRunning = false
            var text = ocrProc.stdout.text.trim()
            if (text !== "") {
                if (pluginApi) {
                    pluginApi.pluginSettings.ocrResult = text
                    pluginApi.pluginSettings.ocrCapturePath = "/tmp/screen-toolkit-ocr.png"
                    pluginApi.pluginSettings.translateResult = ""
                    pluginApi.saveSettings()
                }
                root.activeTool = "ocr"
                if (pluginApi) pluginApi.withCurrentScreen(screen => pluginApi.openPanel(screen))
            } else {
                root.activeTool = ""
                ToastService.showError(pluginApi.tr("messages.no-text"))
            }
        }
    }

    Process {
        id: qrProc
        stdout: StdioCollector {}
        onExited: (code) => {
            root.isRunning = false
            var result = qrProc.stdout.text.trim()
            if (result !== "") {
                if (pluginApi) {
                    pluginApi.pluginSettings.qrResult = result
                    pluginApi.pluginSettings.qrCapturePath = "/tmp/screen-toolkit-qr.png"
                    pluginApi.saveSettings()
                }
                root.activeTool = "qr"
                if (pluginApi) pluginApi.withCurrentScreen(screen => pluginApi.openPanel(screen))
            } else {
                root.activeTool = ""
                ToastService.showError(pluginApi.tr("messages.no-qr"))
            }
        }
    }

    Process {
        id: lensProc
        onExited: (code) => {
            root.isRunning = false
            root.activeTool = ""
            if (code !== 0) ToastService.showError(pluginApi.tr("messages.lens-failed"))
        }
    }

    Process {
        id: annotateProc
        onExited: (code) => {
            root.isRunning = false
            if (code === 0) {
                root.activeTool = ""
                if (pluginApi) pluginApi.withCurrentScreen(screen => pluginApi.closePanel(screen))
                var region = annotateRegionProc.stdout.text.trim()
                Logger.i("ScreenToolkit", "annotate done, region=" + region)
                annotateOverlay.parseAndShow(region, "/tmp/screen-toolkit-annotate.png")
            } else {
                root.activeTool = ""
                ToastService.showError(pluginApi.tr("messages.capture-failed"))
            }
        }
    }

    Process {
        id: annotateRegionProc
        stdout: StdioCollector {}
    }

    Process {
        id: pinGrimProc
        stdout: StdioCollector {}
        onExited: (code) => {
            root.isRunning = false
            var output = pinGrimProc.stdout.text.trim()
            Logger.i("ScreenToolkit", "pinGrimProc exited: code=" + code + " output=" + output)
            if (code === 0 && output !== "") {
                var parts = output.split("|")
                Logger.i("ScreenToolkit", "pin parts=" + JSON.stringify(parts))
                if (parts.length === 2) {
                    var imgPath = parts[0]
                    var wh = parts[1].split("x")
                    var pw = parseInt(wh[0]) || 400
                    var ph = parseInt(wh[1]) || 300
                    Logger.i("ScreenToolkit", "addPin: " + imgPath + " " + pw + "x" + ph)
                    pinOverlay.addPin(imgPath, pw, ph)
                    ToastService.showNotice(pluginApi.tr("messages.pinned"))
                }
            } else if (code !== 0) {
                ToastService.showError(pluginApi.tr("messages.capture-failed"))
            }
        }
    }

    Process {
        id: paletteProc
        stdout: StdioCollector {}
        onExited: (code) => {
            root.isRunning = false
            var raw = paletteProc.stdout.text.trim()
            if (code === 0 && raw !== "") {
                var colors = raw.split("\n").filter(function(c) { return c.match(/^#[0-9a-fA-F]{6}$/) }).slice(0, 8)
                Logger.i("ScreenToolkit", "palette colors: " + JSON.stringify(colors))
                if (colors.length > 0 && pluginApi) {
                    pluginApi.pluginSettings.paletteColors = colors
                    pluginApi.saveSettings()
                    root.activeTool = "palette"
                    pluginApi.withCurrentScreen(screen => pluginApi.openPanel(screen))
                }
            } else {
                ToastService.showError(pluginApi.tr("messages.palette-failed"))
            }
        }
    }

    Process {
        id: translateProc
        property bool isTranslating: false
        stdout: StdioCollector {}
        onExited: (code) => {
            translateProc.isTranslating = false
            var result = translateProc.stdout.text.trim()
            if (pluginApi) {
                pluginApi.pluginSettings.translateResult = (code === 0 && result !== "")
                    ? result
                    : pluginApi.tr("messages.translate-failed")
                pluginApi.saveSettings()
            }
        }
    }

    Process {
        id: clipProc
    }

    // ── Overlays ──────────────────────────────────────────────
    Annotate {
        id: annotateOverlay
    }

    Measure {
        id: measureOverlay
        mainInstance: root
    }

    Pin {
        id: pinOverlay
    }

    // ── Slurp flow ────────────────────────────────────────────

    Process {
        id: clearRegionProc
    }

    Process {
        id: slurpProc
        onExited: (code) => {
            Logger.i("ScreenToolkit", "slurpProc (systemd-run) exited: " + code)
            if (code !== 0) {
                slurpPollTimer.stop()
                root.isRunning = false
                root.activeTool = ""
            }
        }
    }

    property int _slurpPollCount: 0

    Process {
        id: slurpCheckProc
        stdout: StdioCollector {}
        onExited: (code) => {
            if (code !== 0) return   // file not ready yet — poll again next tick
            var result = slurpCheckProc.stdout.text.trim()
            Logger.i("ScreenToolkit", "slurpCheck: " + result)
            slurpPollTimer.stop()
            root._slurpPollCount = 0
            if (result === "cancel") {
                root.isRunning = false
                root.activeTool = ""
            } else if (result === "ok") {
                if      (root.pendingTool === "ocr")      launchOcr.start()
                else if (root.pendingTool === "qr")       launchQr.start()
                else if (root.pendingTool === "lens")     launchLens.start()
                else if (root.pendingTool === "annotate") launchAnnotate.start()
                else if (root.pendingTool === "pin")      launchPin.start()
                else if (root.pendingTool === "palette")  launchPalette.start()
            }
        }
    }

    // ── Timers ────────────────────────────────────────────────

    Timer {
        id: launchColorPicker
        interval: 500; repeat: false
        onTriggered: {
            colorPickerProc.exec({
                command: [
                    "bash", "-c",
                    "COORDS=$(slurp -p 2>/dev/null) || exit 1; " +
                    "X=$(echo \"$COORDS\" | cut -d',' -f1); " +
                    "Y=$(echo \"$COORDS\" | cut -d',' -f2 | cut -d' ' -f1); " +
                    "GX=$((X-5)); GY=$((Y-5)); " +
                    "FILE=/tmp/screen-toolkit-colorpicker.png; " +
                    "grim -g \"${GX},${GY} 11x11\" \"$FILE\" 2>/dev/null || exit 1; " +
                    "HEX=$(magick \"$FILE\" -format '#%[hex:p{5,5}]' info:- 2>/dev/null); " +
                    "[ -n \"$HEX\" ] && printf '%s|%s' \"$HEX\" \"$FILE\" || exit 1"
                ]
            })
        }
    }

    Timer {
        id: launchSlurp
        interval: 300; repeat: false
        onTriggered: {
            Logger.i("ScreenToolkit", "launchSlurp fired for: " + root.pendingTool)
            clearRegionProc.exec({
                command: ["bash", "-c", "rm -f " + root.regionFile + " " + root.regionFile + ".cancel " + root.regionFile + ".tmp"]
            })
            slurpProc.exec({
                command: [
                    "bash", "-c",
                    "systemd-run --user --collect --quiet " +
                    "bash -c 'slurp > " + root.regionFile + ".tmp 2>/dev/null && " +
                    "REGION=$(cat " + root.regionFile + ".tmp); " +
                    "W=$(echo \"$REGION\" | cut -d\" \" -f2 | cut -dx -f1); " +
                    "H=$(echo \"$REGION\" | cut -d\" \" -f2 | cut -dx -f2); " +
                    "{ [ \"${W:-0}\" -gt 2 ] && [ \"${H:-0}\" -gt 2 ]; } && " +
                    "mv " + root.regionFile + ".tmp " + root.regionFile + " || " +
                    "{ rm -f " + root.regionFile + ".tmp; touch " + root.regionFile + ".cancel; }'"
                ]
            })
            slurpPollTimer.start()
        }
    }

    Timer {
        id: slurpPollTimer
        interval: 200; repeat: true
        onTriggered: {
            root._slurpPollCount++
            if (root._slurpPollCount > 300) {
                slurpPollTimer.stop()
                root._slurpPollCount = 0
                root.isRunning = false
                root.activeTool = ""
                Logger.i("ScreenToolkit", "slurp timed out")
                return
            }
            slurpCheckProc.exec({
                command: [
                    "bash", "-c",
                    "if [ -f " + root.regionFile + ".cancel ]; then " +
                    "  rm -f " + root.regionFile + ".cancel; echo cancel; exit 0; " +
                    "elif [ -f " + root.regionFile + " ]; then " +
                    "  echo ok; exit 0; " +
                    "else exit 1; fi"
                ]
            })
        }
    }

    Timer {
        id: launchOcr
        interval: 50; repeat: false
        onTriggered: {
            ocrProc.exec({
                command: [
                    "bash", "-c",
                    "REGION=$(cat " + root.regionFile + ") || exit 1; " +
                    "grim -g \"$REGION\" /tmp/screen-toolkit-ocr.png 2>/dev/null; " +
                    "cat /tmp/screen-toolkit-ocr.png | tesseract - - -l " + root.pendingLangStr + " 2>/dev/null; " +
                    "rm -f " + root.regionFile
                ]
            })
        }
    }

    Timer {
        id: launchQr
        interval: 50; repeat: false
        onTriggered: {
            qrProc.exec({
                command: [
                    "bash", "-c",
                    "REGION=$(cat " + root.regionFile + ") || exit 1; " +
                    "grim -g \"$REGION\" /tmp/screen-toolkit-qr.png 2>/dev/null; " +
                    "zbarimg -q --raw /tmp/screen-toolkit-qr.png 2>/dev/null; " +
                    "rm -f " + root.regionFile
                ]
            })
        }
    }

    Timer {
        id: launchLens
        interval: 50; repeat: false
        onTriggered: {
            lensProc.exec({
                command: [
                    "bash", "-c",
                    "REGION=$(cat " + root.regionFile + ") || exit 1; " +
                    "grim -g \"$REGION\" /tmp/screen-toolkit-lens.png 2>/dev/null && " +
                    "notify-send 'Screen Toolkit' 'Uploading to Lens...' 2>/dev/null; " +
                    "URL=$(curl -sS -F 'file=@/tmp/screen-toolkit-lens.png' 'https://0x0.st' 2>/dev/null); " +
                    "rm -f /tmp/screen-toolkit-lens.png; rm -f " + root.regionFile + "; " +
                    "if [ -n \"$URL\" ]; then xdg-open \"https://lens.google.com/uploadbyurl?url=$URL\" 2>/dev/null; else exit 1; fi"
                ]
            })
        }
    }

    Timer {
        id: launchAnnotate
        interval: 50; repeat: false
        onTriggered: {
            annotateRegionProc.exec({
                command: ["bash", "-c", "cat " + root.regionFile + " 2>/dev/null"]
            })
            annotateProc.exec({
                command: [
                    "bash", "-c",
                    "REGION=$(cat " + root.regionFile + ") || exit 1; " +
                    "grim -g \"$REGION\" /tmp/screen-toolkit-annotate.png 2>/dev/null; " +
                    "rm -f " + root.regionFile
                ]
            })
        }
    }

    Timer {
        id: launchPin
        interval: 50; repeat: false
        onTriggered: {
            pinGrimProc.exec({
                command: [
                    "bash", "-c",
                    "REGION=$(cat " + root.regionFile + ") || exit 1; " +
                    "FILE=/tmp/screen-toolkit-pin-$(date +%s%3N).png; " +
                    "grim -g \"$REGION\" \"$FILE\" 2>/dev/null || exit 1; " +
                    "WH=$(echo \"$REGION\" | cut -d' ' -f2); " +
                    "echo \"$FILE|$WH\"; " +
                    "rm -f " + root.regionFile
                ]
            })
        }
    }

    Timer {
        id: launchPalette
        interval: 50; repeat: false
        onTriggered: {
            paletteProc.exec({
                command: [
                    "bash", "-c",
                    "REGION=$(cat " + root.regionFile + ") || exit 1; " +
                    "FILE=/tmp/screen-toolkit-palette.png; " +
                    "grim -g \"$REGION\" \"$FILE\" 2>/dev/null || exit 1; " +
                    "magick \"$FILE\" +dither -colors 8 -unique-colors txt:- 2>/dev/null " +
                    "| grep -v '^#' | grep -oP '#[0-9a-fA-F]{6}' | head -8; " +
                    "rm -f " + root.regionFile
                ]
            })
        }
    }

    // ── Helpers ───────────────────────────────────────────────

    function copyToClipboard(text) {
        if (!text || text === "") return
        clipProc.exec({
            command: ["bash", "-c", "printf '%s' " + shellEscape(text) + " | wl-copy 2>/dev/null"]
        })
    }

    function shellEscape(str) {
        return "'" + str.replace(/'/g, "'\\''") + "'"
    }

    function closeThenLaunch(timer) {
        if (!pluginApi) { timer.start(); return }
        pluginApi.withCurrentScreen(screen => {
            pluginApi.closePanel(screen)
            timer.start()
        })
    }

    function runTranslate(text, targetLang) {
        if (!text || text === "" || translateProc.isTranslating) return
        translateProc.isTranslating = true
        if (pluginApi) {
            pluginApi.pluginSettings.translateResult = ""
            pluginApi.saveSettings()
        }
        translateProc.exec({
            command: ["bash", "-c", "trans -brief -to " + targetLang + " " + shellEscape(text)]
        })
    }

    // ── Tool Runners ──────────────────────────────────────────

    function runColorPicker() {
        if (root.isRunning) return
        root.isRunning = true
        root.activeTool = ""
        if (pluginApi) {
            pluginApi.pluginSettings.resultHex = ""
            pluginApi.pluginSettings.resultRgb = ""
            pluginApi.pluginSettings.resultHsv = ""
            pluginApi.pluginSettings.resultHsl = ""
            pluginApi.pluginSettings.colorCapturePath = ""
            pluginApi.saveSettings()
        }
        closeThenLaunch(launchColorPicker)
    }

    function runOcr(langStr) {
        if (root.isRunning) return
        root.pendingLangStr = (langStr && langStr !== "") ? langStr : "eng"
        root.pendingTool = "ocr"
        root.isRunning = true
        closeThenLaunch(launchSlurp)
    }

    function runQr() {
        if (root.isRunning) return
        root.pendingTool = "qr"
        root.isRunning = true
        closeThenLaunch(launchSlurp)
    }

    function runLens() {
        if (root.isRunning) return
        root.pendingTool = "lens"
        root.isRunning = true
        closeThenLaunch(launchSlurp)
    }

    function runAnnotate() {
        if (root.isRunning) return
        root.pendingTool = "annotate"
        root.isRunning = true
        closeThenLaunch(launchSlurp)
    }

    function runPalette() {
        if (root.isRunning) return
        root.pendingTool = "palette"
        root.isRunning = true
        if (pluginApi) {
            pluginApi.pluginSettings.paletteColors = []
            pluginApi.saveSettings()
        }
        closeThenLaunch(launchSlurp)
    }

    function runPin() {
        if (root.isRunning) return
        root.pendingTool = "pin"
        root.isRunning = true
        closeThenLaunch(launchSlurp)
    }

    function runMeasure() {
        if (root.isRunning) return
        root.activeTool = "measure"
        if (pluginApi) pluginApi.withCurrentScreen(screen => pluginApi.closePanel(screen))
        measureOverlay.show()
    }

    function detectCapabilities() {
        root._detectedLangs = []
        detectLangsProc.exec({
            command: ["bash", "-c", "ls /usr/share/tessdata/*.traineddata 2>/dev/null"]
        })
        detectTransProc.exec({
            command: ["bash", "-c", "which trans 2>/dev/null"]
        })
    }

    // ── IPC ───────────────────────────────────────────────────

    IpcHandler {
        target: "plugin:screen-toolkit"
        function colorPicker()  { root.runColorPicker() }
        function ocr()          { root.runOcr(root.selectedOcrLang) }
        function qr()           { root.runQr() }
        function lens()         { root.runLens() }
        function annotate()     { root.runAnnotate() }
        function measure()      { root.runMeasure() }
        function pin()          { root.runPin() }
        function palette()      { root.runPalette() }
        function toggle() {
            if (!pluginApi) return
            pluginApi.withCurrentScreen(screen => pluginApi.togglePanel(screen))
        }
    }
}
