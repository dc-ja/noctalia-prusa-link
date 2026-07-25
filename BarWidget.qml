import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    property var mainInstance: pluginApi?.mainInstance

    readonly property string screenName: screen ? screen.name : ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"

    readonly property string printerState: mainInstance?.printerState ?? "OFFLINE"
    readonly property real progress: mainInstance?.progress ?? 0
    readonly property bool connected: mainInstance?.connected ?? false

    readonly property bool isErrorState: printerState === "ERROR" || printerState === "ATTENTION"

    readonly property bool alwaysVisible: printerState === "PRINTING" || printerState === "PAUSED" || printerState === "BUSY" || printerState === "FINISHED" || printerState === "STOPPED" || printerState === "ERROR" || printerState === "ATTENTION"

    readonly property string displayText: {
        if (printerState === "PRINTING")
            return Math.round(progress) + "%";
        if (printerState === "PAUSED")
            return "Paused";
        if (printerState === "IDLE")
            return "Idle";
        if (printerState === "READY")
            return "Ready";
        if (printerState === "BUSY")
            return "Busy";
        if (printerState === "FINISHED")
            return "Finished";
        if (printerState === "STOPPED")
            return "Stopped";
        if (printerState === "ERROR")
            return "Error";
        if (printerState === "ATTENTION")
            return "Attention";
        return "Offline";
    }

    readonly property string stateIcon: printerState === "OFFLINE" ? "printer-off" : "printer"

    readonly property color stateColor: {
        if (printerState === "PRINTING")
            return Color.mPrimary;
        if (isErrorState)
            return Color.mError;
        if (printerState === "PAUSED")
            return Color.mPrimary;
        if (printerState === "FINISHED")
            return Color.mPrimary;
        return Color.mOnSurfaceVariant;
    }

    /* ---- tooltip ---- */
    function buildTooltipContent() {
        if (!connected)
            return [["PrusaLink", "Disconnected"]];

        const stateLabel = {
            "IDLE": "idle",
            "READY": "ready",
            "BUSY": "busy",
            "PRINTING": "printing",
            "PAUSED": "paused",
            "FINISHED": "finished",
            "STOPPED": "stopped",
            "ERROR": "error",
            "ATTENTION": "attention"
        };

        const rows = [];
        const printerName = mainInstance?.infoName || mainInstance?.infoHostname || "";
        if (printerName)
            rows.push(["Printer", printerName]);
        rows.push(["State", stateLabel[root.printerState] ?? "offline"]);

        if (root.printerState === "PRINTING" || root.printerState === "PAUSED") {
            rows.push(["Progress", Math.round(root.progress) + "%"]);
            rows.push(["Time remaining", mainInstance?.formatTime(mainInstance?.timeRemaining) ?? "--:--"]);
            rows.push(["Print time", mainInstance?.formatTime(mainInstance?.timePrinting) ?? "--:--"]);
        }

        rows.push(["Nozzle", mainInstance?.tempNozzle.toFixed(1) + "\u00B0C / " + mainInstance?.targetNozzle.toFixed(1) + "\u00B0C"]);
        rows.push(["Bed", mainInstance?.tempBed.toFixed(1) + "\u00B0C / " + mainInstance?.targetBed.toFixed(1) + "\u00B0C"]);
        rows.push(["Z height", mainInstance?.axisZ.toFixed(1) + " mm"]);
        rows.push(["Flow", mainInstance?.flow + "%"]);
        rows.push(["Speed", mainInstance?.speed + "%"]);
        rows.push(["Hotend fan", mainInstance?.formatFan(mainInstance?.fanHotend)]);
        rows.push(["Print fan", mainInstance?.formatFan(mainInstance?.fanPrint)]);
        if (mainInstance?.storageName)
            rows.push(["Storage", mainInstance.storageName + (mainInstance.storageReadOnly ? " (read-only)" : "")]);
        return rows;
    }

    implicitWidth: pill.width
    implicitHeight: pill.height

    NPopupContextMenu {
        id: contextMenu
        screen: root.screen

        model: [
            {
                "label": "Refresh",
                "action": "refresh",
                "icon": "refresh"
            },
        ]

        onTriggered: (action, item) => {
            contextMenu.close();
            PanelService.closeContextMenu(root.screen);
            if (action === "refresh") {
                mainInstance?.refresh();
            }
        }
    }

    BarPill {
        id: pill

        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)
        customTextIconColor: root.stateColor
        icon: root.stateIcon
        text: root.displayText
        tooltipText: root.buildTooltipContent()
        autoHide: false
        forceOpen: !root.isBarVertical && root.alwaysVisible
        forceClose: root.isBarVertical

        onClicked: {
            TooltipService.hide();
            pluginApi?.togglePanel(root.screen, root);
        }

        onRightClicked: {
            TooltipService.hide();
            PanelService.showContextMenu(contextMenu, pill, root.screen);
        }
    }
}
