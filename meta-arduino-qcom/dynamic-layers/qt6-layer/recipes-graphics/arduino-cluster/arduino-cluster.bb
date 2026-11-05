SUMMARY = "Arduino UNO Q instrument cluster prototype (Qt Quick)"
DESCRIPTION = "Speedometer and tachometer in QML, rendered on the GPU with \
OpenGL ES through eglfs/KMS, without a compositor, and started on the \
fast-boot critical path. Logs how long each startup stage takes. Can show a \
V4L2 camera in the speedometer centre."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "imola"

SRC_URI = " \
    file://CMakeLists.txt \
    file://main.cpp \
    file://Main.qml \
    file://Cluster.qml \
    file://Gauge.qml \
    file://CameraView.qml \
    file://arduino-cluster.service \
    file://arduino-cluster.conf \
    file://arduino-cluster-mouse.conf \
"

S = "${UNPACKDIR}"

DEPENDS = "qtbase qtdeclarative qtdeclarative-native qtmultimedia libdrm systemd"

inherit qt6-cmake systemd features_check

REQUIRED_DISTRO_FEATURES = "opengl systemd"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/arduino-cluster.service ${D}${systemd_system_unitdir}/

    install -d ${D}${nonarch_libdir}/modules-load.d
    install -m 0644 ${S}/arduino-cluster.conf ${D}${nonarch_libdir}/modules-load.d/

    install -d ${D}${systemd_system_unitdir}/arduino-cluster.service.d
    install -m 0644 ${S}/arduino-cluster-mouse.conf \
        ${D}${systemd_system_unitdir}/arduino-cluster.service.d/50-mouse.conf
}

SYSTEMD_SERVICE:${PN} = "arduino-cluster.service"

FILES:${PN} += "${nonarch_libdir}/modules-load.d"

# Development: USB mouse input and a pointer (see arduino-cluster-mouse.conf)
PACKAGE_BEFORE_PN = "${PN}-mouse"
SUMMARY:${PN}-mouse = "USB mouse input for the Arduino cluster (development)"
FILES:${PN}-mouse = "${systemd_system_unitdir}/arduino-cluster.service.d/50-mouse.conf"
RDEPENDS:${PN}-mouse = "${PN}"

# QML modules (QtQuick), the eglfs platform plugin and its KMS integration,
# Mesa's EGL and freedreno driver behind glvnd, and a font for the labels.
RDEPENDS:${PN} += " \
    qtdeclarative-qmlplugins \
    qtbase-plugins \
    libegl-mesa \
    mesa-megadriver \
    ttf-dejavu-sans \
    ${CAMERA_RDEPENDS} \
"

# Camera view: Qt Multimedia's QML types and GStreamer backend, and the
# GStreamer elements its camera pipeline uses: the V4L2 source, jpegdec for
# MJPEG webcams, videoconvert/videoscale and appsink. Qt also refuses to open
# any camera without videotestsrc, its placeholder source.
CAMERA_RDEPENDS = " \
    qtmultimedia-qmlplugins \
    qtmultimedia-plugins \
    gstreamer1.0-plugins-base-app \
    gstreamer1.0-plugins-base-videoconvertscale \
    gstreamer1.0-plugins-base-videotestsrc \
    gstreamer1.0-plugins-good-jpeg \
    gstreamer1.0-plugins-good-video4linux2 \
"

RRECOMMENDS:${PN} += "kernel-module-msm kernel-module-anx7625 kernel-module-dispcc-qcm2290 \
    kernel-module-gpucc-qcm2290 kernel-module-i2c-qcom-geni kernel-module-phy-qcom-qusb2 \
    kernel-module-phy-qcom-qmp-usbc kernel-module-dwc3-qcom-legacy kernel-module-uvcvideo"
