SUMMARY = "Arduino fast-boot systemd units"
DESCRIPTION = "Defines arduino-app.target, the end of the fast-boot critical \
path, and starts arduino-router on it without waiting for network.target."
SECTION = "console/utils"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://arduino-app.target \
    file://arduino-router.service \
"

S = "${UNPACKDIR}"

inherit allarch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/arduino-app.target ${D}${systemd_system_unitdir}/

    # Replaces the upstream unit, which orders itself after network.target and
    # would pull NetworkManager onto the critical path. The machine drop-in
    # written by systemd-arduino-router still applies.
    install -d ${D}${sysconfdir}/systemd/system
    install -m 0644 ${UNPACKDIR}/arduino-router.service ${D}${sysconfdir}/systemd/system/

    install -d ${D}${sysconfdir}/systemd/system/multi-user.target.wants
    ln -sf ${systemd_system_unitdir}/arduino-app.target \
        ${D}${sysconfdir}/systemd/system/multi-user.target.wants/arduino-app.target
}

FILES:${PN} += "${systemd_system_unitdir}"

RDEPENDS:${PN} += "arduino-router libgpiod-tools"
