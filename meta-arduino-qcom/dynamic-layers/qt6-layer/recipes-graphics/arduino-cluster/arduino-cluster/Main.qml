import QtQuick

Window {
    // Camera shown in the speedometer, -1 for none; set at startup from
    // ARDUINO_CLUSTER_CAMERA
    property alias camera: cluster.camera

    visible: true
    color: "black"
    title: "Arduino Cluster"

    Cluster {
        id: cluster
        anchors.fill: parent
    }

    // Startup needle sweep, then a simulated drive through the gears, as in
    // arduino-dash. FrameAnimation runs once per displayed frame, in step
    // with the display refresh.
    FrameAnimation {
        readonly property real sweepMs: 1200
        readonly property var gearTop: [0, 20, 45, 75, 110, 150, 240]

        running: true

        onTriggered: {
            const t = elapsedTime * 1000

            if (t < sweepMs) {
                const k = Math.sin(Math.PI * t / sweepMs)
                cluster.speed = k * 240
                cluster.speedShown = 0
                cluster.rpm = k * 8000
                cluster.rpmShown = 0
                cluster.gear = "P"
                cluster.fuel = k
                return
            }

            const d = t - sweepMs
            const speed = 70 - 60 * Math.cos(d / 6000)
            let gear = 1
            while (gear < 6 && speed > gearTop[gear])
                gear++
            const rpm = 900 + (speed - gearTop[gear - 1]) * 5600 / (gearTop[gear] - gearTop[gear - 1])

            cluster.speed = speed
            cluster.speedShown = Math.floor(speed)
            cluster.rpm = rpm
            cluster.rpmShown = Math.floor(rpm / 100) * 100
            cluster.gear = String(gear)
            cluster.fuel = (100 - Math.floor(d / 6000) % 100) / 100
        }
    }
}
