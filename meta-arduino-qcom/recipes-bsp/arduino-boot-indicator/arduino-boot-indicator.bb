SUMMARY = "UNO Q LED matrix boot indicator"
DESCRIPTION = "BootIndicator sketch for the UNO Q MCU, a service that flashes it \
over SWD when it changes, and a service that reports the boot times to it once \
systemd has finished booting."
LICENSE = "MIT & Apache-2.0 & LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "imola"

SRC_URI = " \
    file://BootIndicator/BootIndicator.ino \
    file://arduino-boot-indicator \
    file://arduino-boot-indicator.service \
    file://arduino-mcu-flash \
    file://arduino-mcu-flash.service \
"

S = "${UNPACKDIR}"

inherit arduino-core systemd

DEPENDS += "arduino-cli-native base-passwd"

BOOT_INDICATOR_LIBS ?= "ArduinoGraphics Arduino_RouterBridge"

# arduino-cli downloads the core, toolchain and libraries
do_compile[network] = "1"
do_compile() {
    do_install_arduino_core
    ${ARDUINO_CLI} lib update-index
    ${ARDUINO_CLI} lib install ${BOOT_INDICATOR_LIBS}
    ${ARDUINO_CLI} compile --fqbn arduino:zephyr:unoq \
        --build-path ${ARDUINO_BUILD_PATH} \
        ${UNPACKDIR}/BootIndicator
}

do_install() {
    install -d ${D}${libdir}/firmware/arduino
    install -m 0644 ${ARDUINO_BUILD_PATH}/BootIndicator.ino.elf-zsk.bin ${D}${libdir}/firmware/arduino/

    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/arduino-boot-indicator ${D}${bindir}/
    install -m 0755 ${UNPACKDIR}/arduino-mcu-flash ${D}${bindir}/
    sed -i 's|@LOADER@|${ARDUINO_ZEPHYR_LOADER}|' ${D}${bindir}/arduino-mcu-flash

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/arduino-boot-indicator.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${UNPACKDIR}/arduino-mcu-flash.service ${D}${systemd_system_unitdir}/
}

SYSTEMD_SERVICE:${PN} = "arduino-boot-indicator.service arduino-mcu-flash.service"

FILES:${PN} += "${libdir}/firmware/arduino"

# The Zephyr loader comes from arduino-default-firmware, built from the same core
RDEPENDS:${PN} += "arduino-default-firmware arduino-router openocd"

PACKAGE_ARCH = "${MACHINE_ARCH}"

INSANE_SKIP:${PN} += "already-stripped split-strip arch"
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
