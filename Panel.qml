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
    //property real contentPreferredHeight: 200 * Style.uiScaleRatio
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

        Component {
            id: statusPropertyComponent

            Item {
                id: statusPropRoot
                implicitHeight: statusPropRow.implicitHeight
                Layout.fillWidth: true

                property string icon: ""
                property color iconColor: Color.mOnSurfaceVariant
                property string label: ""
                property string value: ""

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

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property string statusIcon: "printer"
                        readonly property color statusIconColor: {
                            const s = mainInstance?.printerState ?? "OFFLINE";
                            if (s === "PRINTING" || s === "PAUSED") return Color.mPrimary;
                            if (s === "ERROR" || s === "ATTENTION") return Color.mError;
                            return Color.mOnSurfaceVariant;
                        }
                        readonly property string statusLabel: "Printer status"
                        readonly property string statusValue: {
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

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property color statusIconColor: Color.mPrimary
                        readonly property string statusIcon: "temperature"
                        readonly property string statusLabel: "Nozzle temperature"
                        readonly property string statusValue: (mainInstance?.tempNozzle ?? 0).toFixed(1) + " °C / " + (mainInstance?.targetNozzle ?? 0).toFixed(1) + " °C"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property color statusIconColor: Color.mPrimary
                        readonly property string statusIcon: "temperature"
                        readonly property string statusLabel: "Bed temperature"
                        readonly property string statusValue: (mainInstance?.tempBed ?? 0).toFixed(1) + " °C / " + (mainInstance?.targetBed ?? 0).toFixed(1) + " °C"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property string statusIcon: "gauge"
                        readonly property color statusIconColor: Color.mOnSurfaceVariant
                        readonly property string statusLabel: "Printing speed"
                        readonly property string statusValue: (mainInstance?.speed ?? 100) + "%"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property string statusIcon: "ruler-measure-2"
                        readonly property color statusIconColor: Color.mOnSurfaceVariant
                        readonly property string statusLabel: "Z-height"
                        readonly property string statusValue: (mainInstance?.axisZ ?? 0).toFixed(1) + " mm"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property string statusIcon: "ruler-measure"
                        readonly property color statusIconColor: Color.mOnSurfaceVariant
                        readonly property string statusLabel: "Nozzle diameter"
                        readonly property string statusValue: (mainInstance?.infoNozzleDiameter ?? 0).toFixed(2) + " mm"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
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

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property string statusIcon: "hourglass-high"
                        readonly property color statusIconColor: Color.mOnSurfaceVariant
                        readonly property string statusLabel: "Remaining time"
                        readonly property string statusValue: mainInstance?.formatTime(mainInstance?.timeRemaining) ?? "--:--"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property string statusIcon: "hourglass-low"
                        readonly property color statusIconColor: Color.mOnSurfaceVariant
                        readonly property string statusLabel: "Printing time"
                        readonly property string statusValue: mainInstance?.formatTime(mainInstance?.timePrinting) ?? "--:--"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property string statusIcon: "clock"
                        readonly property color statusIconColor: Color.mOnSurfaceVariant
                        readonly property string statusLabel: "Estimated end"
                        readonly property string statusValue: mainInstance?.estimatedEndTime() ?? "--:--"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property string statusIcon: "calendar"
                        readonly property color statusIconColor: Color.mOnSurfaceVariant
                        readonly property string statusLabel: "Last modified"
                        readonly property string statusValue: mainInstance?.formatTimestamp(mainInstance?.jobFileMTime) ?? "--"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: statusPropertyComponent
                        asynchronous: false
                        focus: false

                        readonly property string statusIcon: "file"
                        readonly property color statusIconColor: Color.mOnSurfaceVariant
                        readonly property string statusLabel: "File size"
                        readonly property string statusValue: mainInstance?.formatFileSize(mainInstance?.jobFileSize) ?? "--"

                        onLoaded: {
                            item.icon = statusIcon;
                            item.iconColor = statusIconColor;
                            item.label = statusLabel;
                            item.value = statusValue;
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
