FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:imola = " file://imola.cfg"
SRC_URI:append:imola = " file://0001-cpuidle-psci-initialize-after-deferred-probing.patch"
SRC_URI:append:monza = " file://monza.cfg"
