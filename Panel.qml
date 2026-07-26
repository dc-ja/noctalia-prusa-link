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
    property real contentPreferredHeight: 200 * Style.uiScaleRatio

    anchors.fill: parent

    ColumnLayout {
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
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
