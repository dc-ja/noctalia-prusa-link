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
    
    NBox {
        Layout.fillWidth: true
        implicitHeight: connectionColumn.implicitHeight + 2 * Style.marginL

        ColumnLayout {
            id: connectionColumn
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            NText {
                text: "Connection"
                pointSize: Style.fontSizeL
                font.weight: Style.fontWeightSemiBold
                color: Color.mPrimary
            }

            RowLayout {
                Layout.fillWidth: true

                ColumnLayout {
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
                        minimumWidth: 120
                        Layout.preferredWidth: 120

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
                        text: "IP address or hostname"
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
                    spacing: Style.marginXS

                    NText {
                        text: "Port"
                        pointSize: Style.fontSizeM
                        font.weight: Style.fontWeightSemiBold
                        color: Color.mOnSurface
                    }
                    NText {
                        text: "Port for the API"
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
        }
    }
    
    NBox {
        Layout.fillWidth: true
        implicitHeight: refreshColumn.implicitHeight + 2 * Style.marginL

        ColumnLayout {
            id: refreshColumn
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM
            Layout.fillWidth: true

            NText {
                text: "Refresh intervals"
                pointSize: Style.fontSizeL
                font.weight: Style.fontWeightSemiBold
                color: Color.mPrimary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS

                Item {
                    Layout.fillWidth: true
                    implicitHeight: offlineRefreshColumn.implicitHeight

                    ColumnLayout {
                        id: offlineRefreshColumn
                        anchors.fill: parent
                        spacing: Style.marginXS

                        NText {
                            text: "Offline"
                            pointSize: Style.fontSizeM
                            font.weight: Style.fontWeightSemiBold
                            color: Color.mOnSurface
                        }
                        NText {
                            text: "Printer is unreachable"
                            pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                        }

                        NSpinBox {
                            from: 1
                            to: 120
                            value: editSettings?.offlineRefreshIntervalSec ?? 10
                            stepSize: 1
                            suffix: " s"
                            onValueChanged: {
                                editSettings.offlineRefreshIntervalSec = value;
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: idleRefreshColumn.implicitHeight
                    
                    ColumnLayout {
                        id: idleRefreshColumn
                        anchors.fill: parent
                        spacing: Style.marginXS

                        NText {
                            text: "Idle"
                            pointSize: Style.fontSizeM
                            font.weight: Style.fontWeightSemiBold
                            color: Color.mOnSurface
                        }
                        NText {
                            text: "Printer is on (no job running)"
                            pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                        }

                        NSpinBox {
                            from: 1
                            to: 120
                            value: editSettings?.idleRefreshIntervalSec ?? 2
                            stepSize: 1
                            suffix: " s"
                            onValueChanged: {
                                editSettings.idleRefreshIntervalSec = value;
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: jobRefreshColumn.implicitHeight
                    
                    ColumnLayout {
                        id: jobRefreshColumn
                        anchors.fill: parent
                        spacing: Style.marginXS

                        NText {
                            text: "Printing"
                            pointSize: Style.fontSizeM
                            font.weight: Style.fontWeightSemiBold
                            color: Color.mOnSurface
                        }
                        NText {
                            text: "Job is running"
                            pointSize: Style.fontSizeXS
                            color: Color.mOnSurfaceVariant
                        }

                        NSpinBox {
                            from: 1
                            to: 120
                            value: editSettings?.printingRefreshIntervalSec ?? 1
                            stepSize: 1
                            suffix: " s"
                            onValueChanged: {
                                editSettings.printingRefreshIntervalSec = value;
                            }
                        }
                    }
                }
            }
        }
    }
}
