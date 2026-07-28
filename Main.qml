import QtQuick
import Quickshell
import qs.Commons

Item {
    id: root
    visible: false

    property var pluginApi: null
    property var pluginSettings: pluginApi?.pluginSettings ?? ({})

    readonly property string protocol: pluginSettings?.protocol ?? "https"
    readonly property string host: pluginSettings?.host ?? "127.0.0.1"
    readonly property int port: pluginSettings?.port ?? 8080
    readonly property string username: pluginSettings?.username ?? "maker"
    readonly property string password: pluginSettings?.password ?? ""
    readonly property string baseUrl: protocol + "://" + host + ":" + port
    property int offlineRefreshIntervalSec: pluginSettings?.offlineRefreshIntervalSec ?? 10
    readonly property int idleRefreshIntervalSec: pluginSettings?.idleRefreshIntervalSec ?? 2
    readonly property int printingRefreshIntervalSec: pluginSettings?.printingRefreshIntervalSec ?? 1
    readonly property int currentRefreshIntervalSec: {
        if (printerState === "OFFLINE") return root.offlineRefreshIntervalSec;
        if (printerState === "PRINTING" || printerState === "PAUSED") return root.printingRefreshIntervalSec;
        return root.idleRefreshIntervalSec;
    }

    /* ---------- printer info ---------- */
    property bool infoFetched: false
    property string infoName: ""
    property string infoHostname: ""
    property string infoLocation: ""
    property bool infoMmu: false
    property bool infoFarmMode: false
    property real infoNozzleDiameter: 0
    property int infoMinExtrusionTemp: 0
    property bool infoSdReady: false
    property bool infoActiveCamera: false
    property string infoPort: ""
    property bool infoNetworkErrorChime: false

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

    /* ---------- job details ---------- */
    property string jobState: ""
    property string jobFileName: ""
    property string jobFileDisplayName: ""
    property string jobFileIcon: ""
    property string jobFileThumbnail: ""
    property string jobFileIconDataUrl: ""
    property string jobFileThumbnailDataUrl: ""
    property string __cachedIconUrl: ""
    property string __cachedThumbnailUrl: ""
    property int jobFileMTime: 0
    property int jobFileSize: 0

    /* ---------- temperature history ---------- */
    readonly property real __tempResolution: 0.1
    readonly property int __historyWindowSec: 180
    readonly property int __tempArrayLen: Math.round(__historyWindowSec / __tempResolution)
    property real __tempLastTs: 0
    property var nozzleTempHistory: Array(__tempArrayLen).fill(0)
    property var nozzleTargetHistory: Array(__tempArrayLen).fill(0)
    property var bedTempHistory: Array(__tempArrayLen).fill(0)
    property var bedTargetHistory: Array(__tempArrayLen).fill(0)

    Timer {
        interval: root.currentRefreshIntervalSec * 1000
        running: true
        repeat: true
        onTriggered: root.fetchStatus()
    }

    Component.onCompleted: root.fetchStatus()

    function fetchStatus() {
        if (!root) return;

        root.error = "";
        const xhr = new XMLHttpRequest();
        xhr.open("GET", root.baseUrl + "/api/v1/status", true, root.username, root.password);
        xhr.timeout = 2000;

        xhr.onreadystatechange = function () {
            if (!root) return;
            
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                root.connected = false;
                root.infoFetched = false;
                root.printerState = "OFFLINE";
                root.jobFileName = "";
                
                if (xhr.status !== 0) {
                    root.error = "HTTP " + xhr.status;
                    Logger.e("prusa-link", "Status fetch failed (HTTP " + xhr.status + ")");
                }
                return;
            }
            root.connected = true;
            root.ready = true;
            if (!root.infoFetched) {
                root.fetchInfo();
            }
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

        root.__pushTempEntry(printer.temp_nozzle ?? 0, printer.target_nozzle ?? 0, printer.temp_bed ?? 0, printer.target_bed ?? 0);

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

        if (root.jobId >= 0) {
            root.fetchJob();
        } else {
            root.jobState = "";
            root.jobFileName = "";
            root.jobFileDisplayName = "";
            root.jobFileIcon = "";
            root.jobFileThumbnail = "";
        }
    }

    function fetchJob() {
        if (!root) {
            return;
        }
        const xhr = new XMLHttpRequest();
        xhr.open("GET", root.baseUrl + "/api/v1/job", true, root.username, root.password);
        xhr.timeout = 5000;

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 204) {
                root.jobState = "";
                root.jobFileName = "";
                root.jobFileDisplayName = "";
                root.jobFileIcon = "";
                root.jobFileThumbnail = "";
                root.jobFileIconDataUrl = "";
                root.jobFileThumbnailDataUrl = "";
                return;
            }
            if (xhr.status !== 200) {
                if (xhr.status !== 0) {
                    Logger.e("prusa-link", "Job fetch failed (HTTP " + xhr.status + ")");
                }
                return;
            }
            try {
                const data = JSON.parse(xhr.responseText);
                root.jobState = data.state ?? "";
                const file = data.file ?? {};
                root.jobFileName = file.name ?? "";
                root.jobFileDisplayName = file.display_name ?? "";
                const refs = file.refs ?? {};
                root.jobFileIcon = refs.icon ?? "";
                root.jobFileThumbnail = refs.thumbnail ?? "";
                root.jobFileMTime = file.m_timestamp ?? 0;
                root.jobFileSize = file.size ?? 0;
                if (refs.icon && refs.icon !== root.__cachedIconUrl) {
                    root.jobFileIconDataUrl = "";
                    root.__cachedIconUrl = "";
                    root.fetchImageAsDataUrl(root.jobFileIcon, function (dataUrl) {
                        root.jobFileIconDataUrl = dataUrl;
                        if (dataUrl)
                            root.__cachedIconUrl = root.jobFileIcon;
                    });
                }
                if (refs.thumbnail && refs.thumbnail !== root.__cachedThumbnailUrl) {
                    root.jobFileThumbnailDataUrl = "";
                    root.__cachedThumbnailUrl = "";
                    root.fetchImageAsDataUrl(root.jobFileThumbnail, function (dataUrl) {
                        root.jobFileThumbnailDataUrl = dataUrl;
                        if (dataUrl)
                            root.__cachedThumbnailUrl = root.jobFileThumbnail;
                    });
                }
            } catch (e) {
                Logger.e("prusa-link", "Failed to parse job:", e);
            }
        };

        xhr.send();
    }

    function fetchImageAsDataUrl(relativePath, callback) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", root.baseUrl + relativePath, true, root.username, root.password);
        xhr.timeout = 10000;
        xhr.responseType = "arraybuffer";
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                callback("");
                return;
            }
            const b64 = Qt.btoa(xhr.response);
            const mimeType = relativePath.match(/\.([^.]+)$/)?.[1]?.toLowerCase();
            let prefix = "data:image/";
            if (mimeType === "png") prefix += "png";
            else if (mimeType === "jpg" || mimeType === "jpeg") prefix += "jpeg";
            else prefix += "png";
            callback(prefix + ";base64," + b64);
        };
        xhr.send();
    }

    function fetchInfo() {
        if (!root) {
            return;
        }
        const xhr = new XMLHttpRequest();
        xhr.open("GET", root.baseUrl + "/api/v1/info", true, root.username, root.password);
        xhr.timeout = 5000;

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                if (xhr.status !== 0) {
                    Logger.e("prusa-link", "Info fetch failed (HTTP " + xhr.status + ")");
                }
                root.infoFetched = true;
                return;
            }
            try {
                const data = JSON.parse(xhr.responseText);
                root.infoName = data.name ?? "";
                root.infoHostname = data.hostname ?? "";
                root.infoLocation = data.location ?? "";
                root.infoMmu = data.mmu ?? false;
                root.infoFarmMode = data.farm_mode ?? false;
                root.infoNozzleDiameter = data.nozzle_diameter ?? 0;
                root.infoMinExtrusionTemp = data.min_extrusion_temp ?? 0;
                root.infoSdReady = data.sd_ready ?? false;
                root.infoActiveCamera = data.active_camera ?? false;
                root.infoPort = data.port ?? "";
                root.infoNetworkErrorChime = data.network_error_chime ?? false;
                root.infoFetched = true;
            } catch (e) {
                Logger.e("prusa-link", "Failed to parse info:", e);
                root.infoFetched = true;
            }
        };

        xhr.send();
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

    function formatFileSize(bytes) {
        if (!bytes || bytes <= 0)
            return "--";
        if (bytes >= 1048576)
            return (bytes / 1048576).toFixed(1) + " MiB";
        if (bytes >= 1024)
            return (bytes / 1024).toFixed(1) + " KiB";
        return bytes + " B";
    }

    function __pushTempEntry(tempNozzle, targetNozzle, tempBed, targetBed) {
        const ts = Math.round(Date.now() / 1000 / root.__tempResolution) * root.__tempResolution;

        const n = root.nozzleTempHistory.length;
        if (n === 0) {
            root.nozzleTempHistory.push(tempNozzle);
            root.nozzleTargetHistory.push(targetNozzle);
            root.bedTempHistory.push(tempBed);
            root.bedTargetHistory.push(targetBed);
            root.__tempLastTs = ts;
            root.nozzleTempHistory = root.nozzleTempHistory.slice();
            root.nozzleTargetHistory = root.nozzleTargetHistory.slice();
            root.bedTempHistory = root.bedTempHistory.slice();
            root.bedTargetHistory = root.bedTargetHistory.slice();
            return;
        }
        const prev = ts - root.__tempLastTs > root.__tempArrayLen ? (ts - 1) : root.__tempLastTs;
        const prevNozzle = root.nozzleTempHistory[n - 1];
        const prevTargetNozzle = root.nozzleTargetHistory[n - 1];
        const prevBed = root.bedTempHistory[n - 1];
        const prevTargetBed = root.bedTargetHistory[n - 1];
        const dt = ts - prev;
        const steps = Math.max(1, Math.round(dt / root.__tempResolution));
        for (let i = 1; i <= steps; i++) {
            const frac = i / steps;
            root.nozzleTempHistory.push(prevNozzle + (tempNozzle - prevNozzle) * frac);
            root.nozzleTargetHistory.push(prevTargetNozzle + (targetNozzle - prevTargetNozzle) * frac);
            root.bedTempHistory.push(prevBed + (tempBed - prevBed) * frac);
            root.bedTargetHistory.push(prevTargetBed + (targetBed - prevTargetBed) * frac);
        }
        root.__tempLastTs = ts;
        const excess = root.nozzleTempHistory.length - root.__tempArrayLen;
        if (excess > 0) {
            root.nozzleTempHistory.splice(0, excess);
            root.nozzleTargetHistory.splice(0, excess);
            root.bedTempHistory.splice(0, excess);
            root.bedTargetHistory.splice(0, excess);
        }
        // Reassign to new array so QML property binding detects the change (in-place push doesn't trigger onValuesChanged)
        root.nozzleTempHistory = root.nozzleTempHistory.slice();
        root.nozzleTargetHistory = root.nozzleTargetHistory.slice();
        root.bedTempHistory = root.bedTempHistory.slice();
        root.bedTargetHistory = root.bedTargetHistory.slice();
    }

    function formatDateRelative(date, now) {
        if (!now)
            now = new Date();
        const locale = Qt.locale();
        const format = Locale.ShortFormat;

        const todayStr = now.toLocaleDateString(locale, format);
        const dateStr = date.toLocaleDateString(locale, format);
        const tomorrow = new Date(now);
        tomorrow.setDate(tomorrow.getDate() + 1);
        const tomorrowStr = tomorrow.toLocaleDateString(locale, format);
        const yesterday = new Date(now);
        yesterday.setDate(yesterday.getDate() - 1);
        const yesterdayStr = yesterday.toLocaleDateString(locale, format);

        const timeStr = date.toLocaleTimeString(locale, format);

        if (dateStr === todayStr)
            return "Today at " + timeStr;
        if (dateStr === tomorrowStr)
            return "Tomorrow at " + timeStr;
        if (dateStr === yesterdayStr)
            return "Yesterday at " + timeStr;
        return date.toLocaleString(locale, format);
    }

    function estimatedEndTime() {
        if (!root.timeRemaining || root.timeRemaining <= 0)
            return "--:--";
        const end = new Date(Date.now() + root.timeRemaining * 1000);
        return root.formatDateRelative(end);
    }

    function formatTimestamp(epoch) {
        if (!epoch || epoch <= 0)
            return "--";
        return root.formatDateRelative(new Date(epoch * 1000));
    }
}
