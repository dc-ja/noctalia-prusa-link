import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null
    readonly property color sectionBackgroundColor: Color.mSurfaceVariant

    property var editSettings: JSON.parse(JSON.stringify(pluginApi?.pluginSettings ?? pluginApi?.manifest?.metadata?.defaultSettings ?? {}))

    function saveSettings() {
        pluginApi.pluginSettings = JSON.parse(JSON.stringify(root.editSettings));
        pluginApi.saveSettings();
    }

    spacing: Style.marginL

    NText {
        text: "PrusaLink Settings"
        pointSize: Style.fontSizeXL
        font.weight: Style.fontWeightBold
        color: Color.mOnSurface
        Layout.fillWidth: true
    }

    Rectangle {
        Layout.fillWidth: true
        color: root.sectionBackgroundColor
        radius: Style.radiusS
        implicitHeight: connectionColumn.implicitHeight + Style.marginXL

        ColumnLayout {
            id: connectionColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Style.marginL
            }
            spacing: Style.marginM

            NText {
                text: "Connection"
                pointSize: Style.fontSizeL
                font.weight: Style.fontWeightSemiBold
                color: Color.mPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                NText {
                    text: "Protocol"
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightSemiBold
                    color: Color.mOnSurface
                }
                NText {
                    text: "HTTP or HTTPS"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }

                NComboBox {
                    model: [
                        {key: "https", name: "HTTPS"},
                        {key: "http", name: "HTTP"}
                    ]
                    currentKey: editSettings?.protocol ?? "https"
                    onSelected: function(key) {
                        editSettings.protocol = key;
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                NText {
                    text: "Host"
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightSemiBold
                    color: Color.mOnSurface
                }
                NText {
                    text: "IP address or hostname of the PrusaLink instance"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }

                NTextInput {
                    Layout.fillWidth: true
                    placeholderText: "127.0.0.1"
                    text: editSettings?.host ?? "127.0.0.1"
                    onTextChanged: {
                        editSettings.host = text;
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                NText {
                    text: "Port"
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightSemiBold
                    color: Color.mOnSurface
                }
                NText {
                    text: "HTTP port for the PrusaLink API"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }

                NSpinBox {
                    from: 1
                    to: 65535
                    value: editSettings?.port ?? 8080
                    stepSize: 1
                    onValueChanged: {
                        editSettings.port = value;
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                NText {
                    text: "Username"
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightSemiBold
                    color: Color.mOnSurface
                }
                NText {
                    text: "PrusaLink username (default: maker)"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }

                NTextInput {
                    Layout.fillWidth: true
                    placeholderText: "maker"
                    text: editSettings?.username ?? "maker"
                    onTextChanged: {
                        editSettings.username = text;
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                NText {
                    text: "Password"
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightSemiBold
                    color: Color.mOnSurface
                }
                NText {
                    text: "PrusaLink password"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }

                NTextInput {
                    Layout.fillWidth: true
                    placeholderText: "Enter password"
                    inputItem.echoMode: TextInput.Password
                    text: editSettings?.password ?? ""
                    onTextChanged: {
                        editSettings.password = text;
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                NText {
                    text: "Refresh interval (seconds)"
                    pointSize: Style.fontSizeM
                    font.weight: Style.fontWeightSemiBold
                    color: Color.mOnSurface
                }
                NText {
                    text: "How often to poll the printer status"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                }

                NSpinBox {
                    from: 2
                    to: 120
                    value: editSettings?.refreshIntervalSec ?? 10
                    stepSize: 1
                    onValueChanged: {
                        editSettings.refreshIntervalSec = value;
                    }
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        Item {
            Layout.fillWidth: true
        }

        NButton {
            text: "Reset"
            onClicked: {
                root.editSettings = JSON.parse(JSON.stringify(pluginApi?.manifest?.metadata?.defaultSettings ?? {}));
            }
        }
    }
}
