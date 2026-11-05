import QtQuick

// Speedometer, tachometer, gear and fuel, laid out for any landscape screen
// the same way as arduino-dash.
Rectangle {
    id: cluster

    property real speed         // km/h, needle position
    property int speedShown     // km/h, number in the dial
    property real rpm
    property int rpmShown
    property string gear: "P"
    property real fuel          // 0 to 1
    property int camera: -1     // camera shown in the speedometer, -1 for none

    readonly property real gaugeSize: Math.min(height * 0.85, width * 0.42)

    color: "black"

    Gauge {
        id: speedo
        width: cluster.gaugeSize
        height: width
        anchors.left: parent.left
        anchors.leftMargin: cluster.width / 30
        anchors.verticalCenter: parent.verticalCenter

        maxValue: 240
        tickCount: 25
        majorEvery: 2
        labels: ["0", "20", "40", "60", "80", "100", "120", "140", "160", "180", "200", "220", "240"]
        unit: "km/h"
        value: cluster.speed
        shown: cluster.speedShown
        centreSource: cluster.camera >= 0 ? "CameraView.qml" : ""
    }

    Binding {
        when: speedo.centreItem !== null
        target: speedo.centreItem
        property: "index"
        value: cluster.camera
    }

    Gauge {
        width: cluster.gaugeSize
        height: width
        anchors.right: parent.right
        anchors.rightMargin: cluster.width / 30
        anchors.verticalCenter: parent.verticalCenter

        maxValue: 8000
        tickCount: 41
        majorEvery: 5
        redline: 6500
        labels: ["0", "1", "2", "3", "4", "5", "6", "7", "8"]
        unit: "x1000 rpm"
        value: cluster.rpm
        shown: cluster.rpmShown
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: cluster.height / 2 - cluster.height / 10 - height / 2
        text: cluster.gear
        color: "#ff9800"
        font.pixelSize: cluster.gaugeSize / 9
    }

    Text {
        id: fuelLabel
        anchors.horizontalCenter: parent.horizontalCenter
        y: cluster.height / 2 + cluster.height / 8 - height / 2
        text: "FUEL"
        color: "#a0a8b0"
        font.pixelSize: cluster.gaugeSize / 30
    }

    Rectangle {
        id: fuelBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: fuelLabel.bottom
        anchors.topMargin: 8
        width: cluster.width / 8
        height: cluster.height / 40 + 4
        radius: height / 2
        color: "#40464c"

        Rectangle {
            width: parent.width * cluster.fuel
            height: parent.height
            radius: parent.radius
            color: "#4caf50"
        }
    }

    // Development: cycles the speedometer centre through the cameras found, then off
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: fuelBar.bottom
        anchors.topMargin: cluster.height / 20
        width: cameraLabel.width + cluster.gaugeSize / 12
        height: cameraLabel.height * 1.8
        radius: height / 2
        color: cameraMouse.containsMouse ? "#2a3038" : "#1a1f24"
        border.color: "#40464c"

        Text {
            id: cameraLabel
            readonly property var view: speedo.centreItem

            anchors.centerIn: parent
            width: Math.min(implicitWidth, cluster.gaugeSize / 4)
            elide: Text.ElideRight
            text: cluster.camera < 0 ? "CAMERA OFF"
                  : !view ? "CAMERA"
                  : view.count === 0 ? "NO CAMERA"
                  : view.name || "CAMERA " + (cluster.camera + 1)
            color: "#a0a8b0"
            font.pixelSize: cluster.gaugeSize / 32
        }

        MouseArea {
            id: cameraMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                const view = speedo.centreItem
                if (cluster.camera < 0)
                    cluster.camera = 0
                else if (view && cluster.camera + 1 < view.count)
                    cluster.camera++
                else
                    cluster.camera = -1
            }
        }
    }
}
