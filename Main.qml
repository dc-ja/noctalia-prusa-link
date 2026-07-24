import QtQuick
import Quickshell

Item {
    id: root
    visible: false

    property var pluginApi: null
    property var pluginSettings: pluginApi?.pluginSettings ?? ({})

    readonly property string host: pluginSettings?.host ?? "127.0.0.1"
    readonly property int port: pluginSettings?.port ?? 9999
    readonly property string baseUrl: "http://" + host + ":" + port
    property int refreshIntervalSec: pluginSettings?.refreshIntervalSec ?? 10

    /* ---------- printer status properties ---------- */
    property bool ready: false
    property bool connected: false
    property string error: ""

    property string printerState: "OFFLINE"

    property real tempBed: 0
    property real targetBed: 0
    property real tempNozzle: 0
    property real targetNozzle: 0

    property real axisZ: 0
    property int flow: 100
    property int speed: 100
    property int fanHotend: 0
    property int fanPrint: 0

    property string storageName: ""
    property bool storageReadOnly: false

    property int jobId: -1
    property real progress: 0
    property int timeRemaining: 0
    property int timePrinting: 0

    Timer {
        interval: root.refreshIntervalSec * 1000
        running: true
        repeat: true
        onTriggered: root.fetchStatus()
    }

    Component.onCompleted: root.fetchStatus()

    function fetchStatus() {
        root.error = "";
        const xhr = new XMLHttpRequest();
        xhr.open("GET", root.baseUrl + "/status");

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                root.connected = false;
                root.printerState = "OFFLINE";
                root.error = "HTTP " + xhr.status;
                Logger.e("prusa-link", "Status fetch failed (HTTP " + xhr.status + ")");
                return;
            }
            root.connected = true;
            root.ready = true;
            try {
                const data = JSON.parse(xhr.responseText);
                root.updateFromPayload(data);
            } catch (e) {
                Logger.e("prusa-link", "Failed to parse status:", e);
                root.error = "Parse error";
            }
        };
        xhr.send();
    }

    function updateFromPayload(data) {
        const printer = data.printer ?? {};
        const job = data.job ?? {};
        const storage = data.storage ?? {};

        root.printerState = printer.state ?? "OFFLINE";

        root.tempBed = printer.temp_bed ?? 0;
        root.targetBed = printer.target_bed ?? 0;
        root.tempNozzle = printer.temp_nozzle ?? 0;
        root.targetNozzle = printer.target_nozzle ?? 0;

        root.axisZ = printer.axis_z ?? 0;
        root.flow = printer.flow ?? 100;
        root.speed = printer.speed ?? 100;
        root.fanHotend = printer.fan_hotend ?? 0;
        root.fanPrint = printer.fan_print ?? 0;

        root.storageName = storage.name ?? "";
        root.storageReadOnly = storage.read_only ?? false;

        root.jobId = job.id ?? -1;
        root.progress = job.progress ?? 0;
        root.timeRemaining = job.time_remaining ?? 0;
        root.timePrinting = job.time_printing ?? 0;
    }

    function refresh() {
        root.fetchStatus();
    }

    /* ---------- helpers ---------- */
    function formatTime(seconds) {
        if (!seconds || seconds <= 0)
            return "--:--";
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = seconds % 60;
        if (h > 0)
            return h + "h " + String(m).padStart(2, "0") + "m";
        return m + "m " + String(s).padStart(2, "0") + "s";
    }

    function formatFan(rpm) {
        if (!rpm || rpm <= 0)
            return "0 RPM";
        if (rpm >= 1000)
            return (rpm / 1000).toFixed(1) + "k RPM";
        return rpm + " RPM";
    }
}
