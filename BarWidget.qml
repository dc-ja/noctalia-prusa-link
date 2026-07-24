import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
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
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

    readonly property string state: mainInstance?.printerState ?? "OFFLINE"
    readonly property real progress: mainInstance?.progress ?? 0
    readonly property bool connected: mainInstance?.connected ?? false

    readonly property string displayText: {
        if (!connected)
            return "\u2014";
        if (state === "PRINTING")
            return Math.round(progress) + "%";
        return state === "IDLE" ? "IDLE" : state;
    }

    readonly property string stateIcon: {
        if (state === "PRINTING")
            return "printer";
        if (state === "IDLE")
            return "printer";
        return "printer-off";
    }

    readonly property color stateColor: {
        if (state === "PRINTING")
            return Color.mPrimary;
        if (state === "IDLE")
            return Color.mOnSurfaceVariant;
        return Color.mError;
    }

    /* ---- tooltip ---- */
    function buildTooltipContent() {
        if (!connected)
            return [["Prusa Link", "Disconnected"]];

        const rows = [];
        rows.push(["Printer", root.state]);

        if (root.state === "PRINTING") {
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

    readonly property real contentWidth: isBarVertical ? capsuleHeight : content.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: isBarVertical ? content.implicitHeight + Style.marginM * 2 : capsuleHeight

    anchors.centerIn: parent
    implicitWidth: contentWidth
    implicitHeight: contentHeight

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

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        radius: Style.radiusL
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        Item {
            id: content
            anchors.centerIn: parent
            implicitWidth: rowLayout.visible ? rowLayout.implicitWidth : colLayout.implicitWidth
            implicitHeight: rowLayout.visible ? rowLayout.implicitHeight : colLayout.implicitHeight

            RowLayout {
                id: rowLayout
                visible: !root.isBarVertical
                spacing: Style.marginS

                NIcon {
                    icon: root.stateIcon
                    pointSize: root.barFontSize
                    applyUiScale: false
                    color: root.stateColor
                    Layout.alignment: Qt.AlignVCenter
                }

                NText {
                    text: root.displayText
                    pointSize: root.barFontSize
                    applyUiScale: false
                    font.weight: Style.fontWeightSemiBold
                    color: root.stateColor
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            ColumnLayout {
                id: colLayout
                visible: root.isBarVertical
                spacing: Style.marginXS

                NIcon {
                    icon: root.stateIcon
                    pointSize: root.barFontSize
                    applyUiScale: false
                    color: root.stateColor
                    Layout.alignment: Qt.AlignHCenter
                }

                NText {
                    text: root.displayText
                    pointSize: root.barFontSize
                    applyUiScale: false
                    font.weight: Style.fontWeightSemiBold
                    color: root.stateColor
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                TooltipService.hide();
                pluginApi?.togglePanel(root.screen, root);
            } else if (mouse.button === Qt.RightButton) {
                TooltipService.hide();
                PanelService.showContextMenu(contextMenu, root, root.screen);
            }
        }

        onEntered: {
            TooltipService.show(root, root.buildTooltipContent(), BarService.getTooltipDirection(root.screenName));
        }

        onExited: {
            TooltipService.hide();
        }
    }
}
