import QtQuick
import QtQuick.Effects
import QtMultimedia

// A V4L2 camera, through Qt Multimedia's GStreamer backend, cropped to the
// circle this item is sized to. Gauge loads it by URL only while a camera is
// shown, which keeps Qt Multimedia and GStreamer off the boot path.
Item {
    id: view

    property int index                  // into the cameras found
    // The SoC's camera subsystem exposes its offline processing engine as a
    // capture device: it is not a camera.
    readonly property var cameras: {
        const found = []
        const inputs = devices.videoInputs
        for (let i = 0; i < inputs.length; i++)
            if (!inputs[i].description.startsWith("Qualcomm CAMSS"))
                found.push(inputs[i])
        return found
    }
    readonly property int count: cameras.length
    readonly property string name: index < count ? cameras[index].description : ""
    property bool receiving: false      // a frame has arrived from the camera
    property bool round: true           // cropped to the circle; click to show the raw picture

    // QVideoFrameFormat::PixelFormat values; the enum is not exposed to QML
    readonly property int formatJpeg: 29
    readonly property var formatNames: ({ 16: "UYVY", 17: "YUYV", 18: "NV12", 19: "NV21", 29: "MJPEG" })

    function describe(f) {
        if (!f || f.resolution.width <= 0)
            return "default format"
        return f.resolution.width + "x" + f.resolution.height + " "
            + (formatNames[f.pixelFormat] || "format " + f.pixelFormat) + " "
            + f.maxFrameRate.toFixed(0) + " fps"
    }

    // Until the first frame arrives, what the camera is doing, on screen and in the journal
    readonly property string status: count === 0 ? "No camera"
        : camera.errorString ? name + "\n" + camera.errorString
        : name + "\n" + describe(camera.cameraFormat) + "\n" + (camera.active ? "waiting for frames" : "starting")
    onStatusChanged: console.log("camera:", status.replace(/\n/g, ", "))

    // YUV first, as the GPU converts it; then RGB; then MJPEG, which is decoded
    // on the CPU; and grey last, which on thermal cameras such as the FLIR Boson
    // is raw sensor data that looks black without contrast processing.
    function formatRank(pixelFormat) {
        if (pixelFormat >= 11 && pixelFormat <= 23 || pixelFormat === 31)
            return 3
        if (pixelFormat >= 1 && pixelFormat <= 10)
            return 2
        return pixelFormat === formatJpeg ? 1 : 0
    }

    // The best-ranked format up to 1280 pixels wide at 24 fps or more; the
    // largest, then the fastest, of those.
    function pickFormat(device) {
        const formats = device.videoFormats
        let best = null
        let bestScore = -1

        for (let i = 0; i < formats.length; i++) {
            const f = formats[i]
            if (f.resolution.width > 1280 || f.maxFrameRate < 24)
                continue
            const score = formatRank(f.pixelFormat) * 1e9 + f.resolution.width * f.resolution.height * 100 + f.maxFrameRate
            if (score > bestScore) {
                best = f
                bestScore = score
            }
        }
        return best
    }

    function open() {
        receiving = false
        for (let i = 0; i < cameras.length; i++)
            console.log("camera: found", i, cameras[i].description, "with", cameras[i].videoFormats.length, "formats")
        const f = pickFormat(camera.cameraDevice)
        if (f)
            camera.cameraFormat = f
        camera.start()
    }

    Component.onCompleted: open()

    MediaDevices {
        id: devices
    }

    CaptureSession {
        camera: Camera {
            id: camera
            cameraDevice: view.index < view.count ? view.cameras[view.index] : devices.defaultVideoInput
            onCameraDeviceChanged: view.open()
        }
        videoOutput: video
    }

    Connections {
        target: video.videoSink
        enabled: !view.receiving
        function onVideoFrameChanged() {
            view.receiving = true
            console.log("camera: first frame from", view.name)
        }
    }

    VideoOutput {
        id: video
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        layer.enabled: view.round
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: width / 2
        antialiasing: true
        visible: false
        layer.enabled: true
    }

    // Edge of the picture
    Rectangle {
        visible: view.round
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.color: "#40464c"
        border.width: 2
    }

    Text {
        visible: !view.receiving
        anchors.centerIn: parent
        width: parent.width * 0.7
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: view.status
        color: "#a0a8b0"
        font.pixelSize: view.width / (view.count === 0 ? 14 : 22)
    }

    // Development: tells a capture problem from a drawing one
    MouseArea {
        anchors.fill: parent
        onClicked: view.round = !view.round
    }
}
