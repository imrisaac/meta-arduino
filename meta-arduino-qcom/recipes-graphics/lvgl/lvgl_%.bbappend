FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Fonts and logging used by arduino-dash
SRC_URI:append:imola = " file://arduino-dash.cfg"
