SUMMARY = "Arduino fast-boot console image"
DESCRIPTION = "Console image tuned for a short power-on to application time. \
Only arduino-router (the MCU bridge) and the application are on the boot \
critical path; every other service is installed but ordered after \
arduino-app.target. Build it with ci/fastboot.yml to also drop the initramfs \
and quiet the kernel console."

LICENSE = "MIT"

inherit core-image

# Hook your own service in with:
#   [Unit]   Before=arduino-app.target
#   [Install] WantedBy=arduino-app.target
# and measure with: systemd-analyze critical-chain arduino-app.target
IMAGE_INSTALL = " \
    packagegroup-core-boot \
    arduino-boot-indicator \
    arduino-dash \
    arduino-fastboot \
    arduino-router \
    arduino-device-tree \
    libgpiod-tools \
    systemd-analyze \
    ${FASTBOOT_DEFERRED_INSTALL} \
    ${CORE_IMAGE_EXTRA_INSTALL} \
"

# Installed, but started only once arduino-app.target is reached
FASTBOOT_DEFERRED_INSTALL ?= " \
    arduino-usb-gadget \
    libusbgx-config \
    bluez5 \
    expand-rootfs \
    networkmanager \
    networkmanager-nmcli \
    wpa-supplicant \
"

IMAGE_FEATURES += "ssh-server-dropbear enable-adbd"
IMAGE_LINGUAS = ""

# Necessary to actually start android-tools-adbd, not just install it.
inherit image-adbd

# Units held back until arduino-app.target, at a lower CPU and IO weight.
# Only services are listed: sockets and early-boot units are ordered before
# basic.target or sysinit.target, so deferring them would create an ordering
# cycle. Units with DefaultDependencies=no are skipped for the same reason.
FASTBOOT_DEFERRED_UNITS ?= " \
    android-tools-adbd.service \
    avahi-daemon.service \
    bluetooth.service \
    dnsmasq.service \
    expand-rootfs.service \
    NetworkManager.service \
    ofono.service \
    rmtfs.service \
    rsyslog.service \
    systemd-networkd.service \
    tqftpserv.service \
    usb-gadget.service \
    wpa_supplicant.service \
"

defer_fastboot_units() {
    for unit in ${FASTBOOT_DEFERRED_UNITS}; do
        [ -e ${IMAGE_ROOTFS}${systemd_system_unitdir}/$unit ] || continue
        if grep -q '^DefaultDependencies=no' ${IMAGE_ROOTFS}${systemd_system_unitdir}/$unit; then
            bbwarn "Not deferring $unit: it runs before basic.target"
            continue
        fi
        install -d ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/$unit.d
        printf '[Unit]\nAfter=arduino-app.target\n\n[Service]\nCPUWeight=20\nIOWeight=20\n' \
            > ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/$unit.d/50-fastboot-defer.conf
    done
}

# Units masked outright. The systemd-boot ones write to the ESP on every boot,
# which puts its mount (and the eMMC partition scan) in front of sysinit.target.
# systemd-networkd manages no interface here (NetworkManager does), so its
# wait-online service only ever runs into its two-minute timeout.
FASTBOOT_MASKED_UNITS ?= " \
    systemd-boot-random-seed.service \
    systemd-boot-update.service \
    systemd-networkd-wait-online.service \
"

mask_fastboot_units() {
    for unit in ${FASTBOOT_MASKED_UNITS}; do
        ln -sf /dev/null ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/$unit
    done
}

ROOTFS_POSTPROCESS_COMMAND += "defer_fastboot_units"
# After do_rootfs, whose systemctl preset-all refuses masked units
IMAGE_PREPROCESS_COMMAND += "mask_fastboot_units"
