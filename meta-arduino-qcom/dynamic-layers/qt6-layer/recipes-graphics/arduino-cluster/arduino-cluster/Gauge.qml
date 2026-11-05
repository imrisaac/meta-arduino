import QtQuick

// Round gauge with a 270° dial from bottom left to bottom right, clockwise.
Item {
    id: gauge

    property real maxValue: 100
    property int tickCount: 21          // ticks from 0 to maxValue, both ends included
    property int majorEvery: 2          // every nth tick is major and labelled
    property real redline: maxValue
    property var labels: []             // one per major tick
    property string unit
    property real value                 // needle position
    property int shown                  // number in the middle
    // QML file shown in the dial centre, under the needle (e.g. a camera view);
    // empty for none. Loaded by URL, so its imports are only resolved when shown.
    property alias centreSource: centreLoader.source
    readonly property alias centreItem: centreLoader.item

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real pad: width / 20
    readonly property real majorLength: width / 18
    readonly property real labelSize: width / 30
    // The disc inside the tick labels
    readonly property real innerRadius: width / 2 - pad - majorLength - width / 40 - 2 * labelSize

    // Clockwise from 3 o'clock, in degrees, as Item.rotation expects
    function angle(v) {
        return 135 + 270 * Math.max(0, Math.min(v, maxValue)) / maxValue
    }

    function tickColor(v, major) {
        return redline < maxValue && v >= redline ? "#f44336" : major ? "white" : "#a0a8b0"
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#101418"
        border.color: "#40464c"
        border.width: 2
    }

    Repeater {
        model: gauge.tickCount

        // Rotated about the dial centre; the tick itself points along +x
        Item {
            id: tick

            required property int index
            readonly property real v: index * gauge.maxValue / (gauge.tickCount - 1)
            readonly property bool major: index % gauge.majorEvery === 0

            anchors.fill: parent
            rotation: gauge.angle(v)

            Rectangle {
                width: tick.major ? gauge.majorLength : gauge.width / 40
                height: tick.major ? 3 : 2
                x: gauge.width - gauge.pad - width
                y: gauge.cy - height / 2
                antialiasing: true
                color: gauge.tickColor(tick.v, tick.major)
            }
        }
    }

    Repeater {
        model: gauge.labels

        Text {
            required property int index
            required property string modelData
            readonly property real v: index * gauge.majorEvery * gauge.maxValue / (gauge.tickCount - 1)
            readonly property real a: gauge.angle(v) * Math.PI / 180
            // Inside the major ticks, by the label's own extent along the radius
            readonly property real r: gauge.width / 2 - gauge.pad - gauge.majorLength - gauge.width / 80
                                      - (Math.abs(Math.cos(a)) * width + Math.abs(Math.sin(a)) * height) / 2

            x: gauge.cx + r * Math.cos(a) - width / 2
            y: gauge.cy + r * Math.sin(a) - height / 2
            text: modelData
            color: gauge.tickColor(v, true)
            font.pixelSize: gauge.labelSize
        }
    }

    Loader {
        id: centreLoader
        width: 2 * gauge.innerRadius
        height: width
        anchors.centerIn: parent
    }

    // Keeps the reading legible over the centre content
    Rectangle {
        visible: centreLoader.item !== null
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: valueLabel.top
        anchors.bottom: unitLabel.bottom
        width: Math.max(valueLabel.width, unitLabel.width) + 2 * gauge.labelSize
        radius: gauge.labelSize
        color: "#b0101418"
    }

    Text {
        id: valueLabel
        anchors.horizontalCenter: parent.horizontalCenter
        y: gauge.cy + gauge.height / 5 - height / 2
        text: gauge.shown
        color: "white"
        font.pixelSize: gauge.width / 16
    }

    Text {
        id: unitLabel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: valueLabel.bottom
        text: gauge.unit
        color: "#a0a8b0"
        font.pixelSize: gauge.labelSize
    }

    // Pivots on its left end, at the dial centre
    Rectangle {
        x: gauge.cx
        y: gauge.cy - height / 2
        width: gauge.width / 2 - gauge.width / 7
        height: 6
        radius: 3
        antialiasing: true
        color: "#ff9800"
        transformOrigin: Item.Left
        rotation: gauge.angle(gauge.value)
    }

    Rectangle {
        width: gauge.width / 16
        height: width
        x: gauge.cx - width / 2
        y: gauge.cy - height / 2
        radius: width / 2
        color: "#ff9800"
    }
}
