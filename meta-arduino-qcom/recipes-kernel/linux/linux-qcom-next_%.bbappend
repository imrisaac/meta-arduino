FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:imola = " file://imola.cfg"
# Fast-boot builds (ci/fastboot.yml)
SRC_URI:append:imola = "${@' file://fastboot.cfg' if d.getVar('ARDUINO_FASTBOOT') == '1' else ''}"
SRC_URI:append:monza = " file://monza.cfg"
