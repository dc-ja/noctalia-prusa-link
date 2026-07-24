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
    property real contentPreferredWidth: 320 * Style.uiScaleRatio
    property real contentPreferredHeight: 200 * Style.uiScaleRatio

    anchors.fill: parent

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            NText {
                text: "Prusa Link"
                pointSize: Style.fontSizeXL
                font.weight: Style.fontWeightBold
                color: Color.mOnSurface
            }

            NText {
                text: "Click the button below to open the Prusa Link web interface in your browser."
                pointSize: Style.fontSizeM
                color: Color.mOnSurfaceVariant
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            NButton {
                text: "Open Web UI"
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    const url = mainInstance?.baseUrl ?? "http://127.0.0.1:9999";
                    Quickshell.execDetached(["xdg-open", url]);
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
