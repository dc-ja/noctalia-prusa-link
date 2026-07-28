import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets


Item {
    id: root

    property var pluginApi: null
    property var mainInstance: pluginApi?.mainInstance

    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true
    property real contentPreferredWidth: 600 * Style.uiScaleRatio
    property real contentPreferredHeight: panelContainer.implicitHeight + 2 * Style.marginL

    anchors.fill: parent

    ColumnLayout {
        id: panelContainer
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        NBox {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + Style.margin2M

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.margins: Style.marginM

                NIcon {
                    icon: "printer"
                    pointSize: Style.fontSizeXXL
                    color: Color.mPrimary
                }

                NText {
                    text: `PrusaLink:`
                    pointSize: Style.fontSizeL
                    font.weight: Style.fontWeightBold
                    color: Color.mOnSurface
                }

                NText {
                    readonly property string printerName: mainInstance?.infoName || mainInstance?.infoHostname || ""
                    text: printerName || "Unknown"
                    pointSize: Style.fontSizeL
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                NIconButton {
                    icon: "refresh"
                    tooltipText: "Refresh"
                    baseSize: Style.baseWidgetSize * 0.8
                    onClicked: mainInstance?.refresh()
                }

                NIconButton {
                    icon: "external-link"
                    tooltipText: "Open Web UI"
                    baseSize: Style.baseWidgetSize * 0.8
                    onClicked: {
                        const url = mainInstance?.baseUrl ?? "";
                        if (!url) return;
                        Quickshell.execDetached(["xdg-open", url]);
                    }
                }

                NIconButton {
                    icon: "close"
                    tooltipText: "Close"
                    baseSize: Style.baseWidgetSize * 0.8
                    onClicked: {
                        if (pluginApi) {
                            pluginApi.withCurrentScreen(function(s) {
                                pluginApi.closePanel(s);
                            });
                        }
                    }
                }
            }
        }

        NBox {
            Layout.fillWidth: true
            implicitHeight: statusColumn.implicitHeight + Style.margin2L

            ColumnLayout {
                id: statusColumn
                anchors.fill: parent
                anchors.margins: Style.marginL
                spacing: Style.marginL

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: mainInstance.printerState === "OFFLINE" ? "printer-off" : "printer"
                        iconColor: {
                            const s = mainInstance?.printerState ?? "OFFLINE";
                            if (s === "PRINTING" || s === "PAUSED") return Color.mPrimary;
                            if (s === "ERROR" || s === "ATTENTION") return Color.mError;
                            return Color.mOnSurfaceVariant;
                        }
                        label: "Printer status"
                        value: {
                            const m = {
                                "PRINTING": "Printing",
                                "PAUSED": "Paused",
                                "IDLE": "Idle",
                                "READY": "Ready",
                                "BUSY": "Busy",
                                "FINISHED": "Finished",
                                "STOPPED": "Stopped",
                                "ERROR": "Error",
                                "ATTENTION": "Attention"
                            };
                            return m[mainInstance?.printerState] ?? "Offline";
                        }
                    }

                    StatusProperty {
                        Layout.fillWidth: true
                        visible: mainInstance.printerState !== "OFFLINE"
                        icon: "temperature"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Nozzle temperature"
                        value: (mainInstance?.tempNozzle ?? 0).toFixed(1) + " °C / " + (mainInstance?.targetNozzle ?? 0).toFixed(1) + " °C"
                    }

                    StatusProperty {
                        Layout.fillWidth: true
                        visible: mainInstance.printerState !== "OFFLINE"
                        icon: "temperature"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Bed temperature"
                        value: (mainInstance?.tempBed ?? 0).toFixed(1) + " °C / " + (mainInstance?.targetBed ?? 0).toFixed(1) + " °C"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM
                    visible: mainInstance.printerState !== "OFFLINE"

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "gauge"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Flow speed"
                        value: (mainInstance?.flow ?? 100) + "%"
                    }

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "car-fan"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Hotend fan"
                        value: mainInstance?.formatFan(mainInstance?.fanHotend) ?? "0 RPM"
                    }

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "car-fan"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Print fan"
                        value: mainInstance?.formatFan(mainInstance?.fanPrint) ?? "0 RPM"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM
                    visible: mainInstance.printerState !== "OFFLINE"

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "gauge"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Printing speed"
                        value: (mainInstance?.speed ?? 100) + "%"
                    }

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "ruler-measure-2"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Z-height"
                        value: (mainInstance?.axisZ ?? 0).toFixed(1) + " mm"
                    }

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "ruler-measure"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Nozzle diameter"
                        value: (mainInstance?.infoNozzleDiameter ?? 0).toFixed(2) + " mm"
                    }
                }
            }
        }

        NBox {
            Layout.fillWidth: true
            implicitHeight: jobColumn.implicitHeight + Style.margin2L
            visible: mainInstance?.jobFileName !== ""

            ColumnLayout {
                id: jobColumn
                anchors.fill: parent
                anchors.margins: Style.marginL
                spacing: Style.marginM

                RowLayout {
                    id: jobLayout
                    Layout.fillWidth: true
                    spacing: Style.marginM

                    Image {
                        id: thumbnailImage
                        source: mainInstance?.jobFileIconDataUrl || mainInstance?.jobFileThumbnailDataUrl || ""
                        sourceSize: Qt.size(100 * Style.uiScaleRatio, 75 * Style.uiScaleRatio)
                        fillMode: Image.PreserveAspectFit
                        Layout.maximumHeight: 75 * Style.uiScaleRatio
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        NText {
                            text: mainInstance?.jobFileDisplayName || mainInstance?.jobFileName 
                            pointSize: Style.fontSizeM
                            font.weight: Style.fontWeightBold
                            color: Color.mOnSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Style.marginS

                            Rectangle {
                                Layout.fillWidth: true
                                height: Math.round(8 * Style.uiScaleRatio)
                                radius: Math.min(Style.radiusL, height / 2)
                                color: Color.mSurface

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: parent.height
                                    radius: parent.radius
                                    width: parent.width * (mainInstance?.progress ?? 0) / 100
                                    color: Color.mPrimary
                                }
                            }

                            NText {
                                Layout.preferredWidth: 40 * Style.uiScaleRatio
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(mainInstance?.progress ?? 0) + "%"
                                color: Color.mOnSurface
                                pointSize: Style.fontSizeS
                                font.weight: Style.fontWeightBold
                            }
                        }
                    }
                }

                NDivider {
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "hourglass-high"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Remaining time"
                        value: mainInstance?.formatTime(mainInstance?.timeRemaining) ?? "--:--"
                    }

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "hourglass-low"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Printing time"
                        value: mainInstance?.formatTime(mainInstance?.timePrinting) ?? "--:--"
                    }

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "clock"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Estimated end"
                        value: mainInstance?.estimatedEndTime() ?? "--:--"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "calendar"
                        iconColor: Color.mOnSurfaceVariant
                        label: "Last modified"
                        value: mainInstance?.formatTimestamp(mainInstance?.jobFileMTime) ?? "--"
                    }

                    StatusProperty {
                        Layout.fillWidth: true
                        icon: "file"
                        iconColor: Color.mOnSurfaceVariant
                        label: "File size"
                        value: mainInstance?.formatFileSize(mainInstance?.jobFileSize) ?? "--"
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }

        NBox {
            Layout.fillWidth: true
            implicitHeight: graphsColumn.implicitHeight + Style.margin2L
            visible: mainInstance?.printerState !== "OFFLINE"

            ColumnLayout {
                id: graphsColumn
                anchors.fill: parent
                anchors.margins: Style.marginL
                spacing: Style.marginS

                NText {
                    text: "Nozzle temperature (°C)"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }

                GraphWithAxis {
                    Layout.fillWidth: true
                    maxValue: 300
                    unit: "°C"
                    history1: mainInstance?.nozzleTargetHistory ?? []
                    history2: mainInstance?.nozzleTempHistory ?? []
                    color1: Color.mVariant
                    color2: Color.mPrimary
                    refreshInterval: mainInstance?.currentRefreshIntervalSec * 1000 ?? 10000
                }

                NText {
                    text: "Bed temperature (°C)"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }

                GraphWithAxis {
                    Layout.fillWidth: true
                    maxValue: 120
                    unit: "°C"
                    history1: mainInstance?.bedTargetHistory ?? []
                    history2: mainInstance?.bedTempHistory ?? []
                    color1: Color.mVariant
                    color2: Color.mPrimary
                    refreshInterval: mainInstance?.currentRefreshIntervalSec * 1000 ?? 10000
                }
            }
        }
    }

    component GraphWithAxis: Item {
        id: graphWithAxisRoot
        Layout.fillWidth: true
        implicitHeight: 100 * Style.uiScaleRatio

        required property real maxValue
        required property string unit
        required property var history1
        required property var history2
        required property color color1
        required property color color2
        required property int refreshInterval

        readonly property real yAxisWidth: 60 * Style.uiScaleRatio
        readonly property real curvePadding: 0.12

        function tickY(val) {
            const padding = graphWithAxisRoot.maxValue * graphWithAxisRoot.curvePadding;
            const paddedRange = graphWithAxisRoot.maxValue + 2 * padding;
            const norm = (val + padding) / paddedRange;
            return graphWithAxisRoot.height * (1.0 - norm);
        }

        NGraph {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.rightMargin: graphWithAxisRoot.yAxisWidth
            values: graphWithAxisRoot.history1
            values2: graphWithAxisRoot.history2
            color: graphWithAxisRoot.color1
            color2: graphWithAxisRoot.color2
            minValue: 0
            maxValue: graphWithAxisRoot.maxValue
            updateInterval: graphWithAxisRoot.refreshInterval
        }

        Repeater {
            model: [
                { value: 0, fraction: 0 },
                { value: graphWithAxisRoot.maxValue * 0.25, fraction: 0.25 },
                { value: graphWithAxisRoot.maxValue * 0.5, fraction: 0.5 },
                { value: graphWithAxisRoot.maxValue * 0.75, fraction: 0.75 }
            ]

            delegate: Item {
                required property var modelData
                anchors.left: parent.left
                anchors.right: parent.right
                y: graphWithAxisRoot.tickY(modelData.value)
                visible: graphWithAxisRoot.maxValue > 0

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: yLabel.left
                    anchors.rightMargin: Style.marginXS
                    height: 1
                    color: Qt.alpha(Color.mOnSurface, 0.08)
                }

                Rectangle {
                    id: yLabel
                    anchors.right: parent.right
                    y: -height / 2
                    implicitWidth: yLabelText.implicitWidth + Style.marginXS * 2
                    implicitHeight: yLabelText.implicitHeight + 2
                    radius: Style.radiusXS
                    color: Qt.alpha(graphWithAxisRoot.color2, 0.10)

                    NText {
                        id: yLabelText
                        anchors.centerIn: parent
                        text: Math.round(modelData.value) + " " + graphWithAxisRoot.unit
                        pointSize: Style.fontSizeXS * 0.8
                        color: Qt.alpha(graphWithAxisRoot.color2, 0.7)
                    }
                }
            }
        }
    }

    component StatusProperty: Item {
        id: statusPropRoot
        implicitHeight: statusPropRow.implicitHeight
        Layout.fillWidth: true

        required property string icon
        required property color iconColor
        required property string label
        required property string value

        RowLayout {
            id: statusPropRow
            anchors.fill: parent
            spacing: Style.marginS

            NIcon {
                icon: statusPropRoot.icon
                pointSize: Style.fontSizeXL
                color: statusPropRoot.iconColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXXS

                NText {
                    Layout.fillWidth: true
                    text: statusPropRoot.label
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                    elide: Text.ElideRight
                }

                NText {
                    Layout.fillWidth: true
                    text: statusPropRoot.value
                    pointSize: Style.fontSizeS
                    font.weight: Style.fontWeightBold
                    color: Color.mOnSurface
                    elide: Text.ElideRight
                }
            }
        }
    }
}
