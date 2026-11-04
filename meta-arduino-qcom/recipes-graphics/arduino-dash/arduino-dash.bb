SUMMARY = "Arduino UNO Q dash prototype"
DESCRIPTION = "Speedometer and tachometer drawn with LVGL directly on DRM/KMS, \
started on the fast-boot critical path."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "imola"

SRC_URI = " \
    file://dash.c \
    file://arduino-dash.service \
    file://arduino-dash.conf \
    file://arduino-dash-modprobe.conf \
"

S = "${UNPACKDIR}"

DEPENDS = "lvgl libdrm systemd"

inherit pkgconfig systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -DLV_CONF_INCLUDE_SIMPLE \
        $(pkg-config --cflags lvgl libdrm libsystemd) \
        -o arduino-dash ${S}/dash.c \
        $(pkg-config --libs lvgl libdrm libsystemd) -lm
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${B}/arduino-dash ${D}${bindir}/

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/arduino-dash.service ${D}${systemd_system_unitdir}/

    install -d ${D}${libdir}/modules-load.d
    install -m 0644 ${S}/arduino-dash.conf ${D}${libdir}/modules-load.d/

    install -d ${D}${nonarch_libdir}/modprobe.d
    install -m 0644 ${S}/arduino-dash-modprobe.conf ${D}${nonarch_libdir}/modprobe.d/arduino-dash.conf
}

SYSTEMD_SERVICE:${PN} = "arduino-dash.service"

FILES:${PN} += "${libdir}/modules-load.d ${nonarch_libdir}/modprobe.d"

RRECOMMENDS:${PN} += "kernel-module-msm kernel-module-anx7625 kernel-module-dispcc-qcm2290 \
    kernel-module-i2c-qcom-geni kernel-module-phy-qcom-qusb2 kernel-module-phy-qcom-qmp-usbc"
