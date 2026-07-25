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
                        const url = mainInstance?.baseUrl ?? "http://127.0.0.1:9999";
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

        Item {
            Layout.fillHeight: true
        }
    }
}
