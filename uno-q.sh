#!/usr/bin/env bash
# Build and flash Arduino UNO Q (imola) images from this checkout.
#
#   ./uno-q.sh build [fastboot|qt|container]   build an image (default: fastboot)
#   ./uno-q.sh flash [fastboot|qt|container]   flash the last built image to a board in EDL mode
#   ./uno-q.sh deploy [fastboot|qt] [HOST]     rebuild only the image's app and install it on a
#                                              running board: over SSH to HOST, else over adb,
#                                              else over SSH to imola.local (mDNS)
#
# fastboot: LVGL dash (arduino-dash); qt: Qt Quick cluster (arduino-cluster)
# deploy replaces the app's binary, which includes the cluster's QML; changes to
# its systemd unit or module list need a build and flash.
#
# Environment overrides:
#   UNOQ_TOP   build tree: sources, build, downloads, sstate-cache (default: /mnt/2TB/meta-arduino)
#   UNOQ_HOST  board address for deploy, e.g. 192.168.0.42
#   QDL_ARGS   extra qdl options, e.g. "--out-chunk-size=65536" or "--debug"
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
TOP=${UNOQ_TOP:-/mnt/2TB/meta-arduino}
MACHINE=imola
DEPLOY=$TOP/build/tmp/deploy/images/$MACHINE

# kas image pinned by .github/workflows/compile.yml; the 4.7 image in
# /usr/local/bin lacks the ccache that meta-qcom's ci/ccache.yml requires.
KAS_IMAGE=ghcr.io/siemens/kas/kas@sha256:3f3d3257e8d4ca3adfcb2e0025e6da24339fb8d68a6999ca36c37381351582d5
KAS=$TOP/kas/kas-container
# The corporate DNS servers in /etc/docker/daemon.json time out off-VPN.
RUNTIME_ARGS="--memory=48g --dns 192.168.0.1 --dns 8.8.8.8"

die() { echo "uno-q.sh: $*" >&2; exit 1; }

usage() { sed -n '2,18s/^# \{0,1\}//p' "$0"; exit "${1:-0}"; }

# Maps an image name to its bitbake target and extra kas overlay.
select_image() {
	case "${1:-fastboot}" in
	fastboot)  TARGET=arduino-fastboot-image;    OVERLAY=:ci/fastboot.yml ;;
	qt)        TARGET=arduino-fastboot-qt-image; OVERLAY=:ci/fastboot.yml:ci/qt.yml ;;
	container) TARGET=arduino-container-image;   OVERLAY= ;;
	*) die "unknown image '$1' (expected fastboot, qt or container)" ;;
	esac
}

# Sets up the kas-container environment for the selected image; sets KAS_CONFIG.
kas_setup() {
	cd "$REPO"
	[ -x "$KAS" ] || die "$KAS not found"
	[ -e ci ] || ln -s meta-arduino-qcom/ci ci
	local f
	for f in ${OVERLAY//:/ }; do
		[ -f "$f" ] || die "$f is missing on branch $(git branch --show-current); it lives on the fastboot-image branch"
	done

	export KAS_WORK_DIR=$TOP/sources KAS_BUILD_DIR=$TOP/build
	export DL_DIR=$TOP/downloads SSTATE_DIR=$TOP/sstate-cache
	export KAS_CONTAINER_IMAGE=$KAS_IMAGE
	mkdir -p "$KAS_WORK_DIR" "$KAS_BUILD_DIR" "$DL_DIR" "$SSTATE_DIR"
	KAS_CONFIG=ci/$MACHINE.yml:ci/$MACHINE.lock.yml:ci/nospdx.yml$OVERLAY
}

cmd_build() {
	select_image "${1:-}"
	kas_setup

	local log=$TOP/build-$MACHINE-${TARGET#arduino-}.log
	echo "Building $TARGET from $(git branch --show-current) @ $(git log -1 --format='%h %s')"
	[ -z "$(git status --porcelain -- . ':!uno-q.sh')" ] || echo "Note: the working tree has uncommitted changes; they are built too."
	echo "Log: $log"

	# -k keeps bitbake going past a flaky download; rerun to retry what failed.
	if ! "$KAS" --runtime-args "$RUNTIME_ARGS" build --target "$TARGET" "$KAS_CONFIG" -- -k 2>&1 | tee "$log"; then
		die "build failed; see $log (rerun to retry failed tasks)"
	fi
	echo "Image: $DEPLOY/$TARGET-$MACHINE.rootfs.qcomflash"
}

cmd_deploy() {
	select_image "${1:-}"
	local app host=${2:-${UNOQ_HOST:-}}
	case "$TARGET" in
	arduino-fastboot-image)    app=arduino-dash ;;
	arduino-fastboot-qt-image) app=arduino-cluster ;;
	*) die "deploy works on the fastboot and qt images" ;;
	esac
	# The board announces itself over mDNS (avahi) once its network is up.
	if [ -z "$host" ] && ! adb get-state >/dev/null 2>&1; then
		getent hosts "$MACHINE.local" >/dev/null && host=$MACHINE.local ||
			die "no board: pass its address (./uno-q.sh deploy ${1:-fastboot} 192.168.0.42) or connect it over USB for adb"
	fi
	kas_setup

	# do_install alone keeps the binary in the recipe's work directory, which
	# rm_work would delete at the end of a full build.
	local log=$TOP/deploy-$app.log start=$SECONDS
	echo "Building $app (log: $log)"
	"$KAS" --runtime-args "$RUNTIME_ARGS" shell -c "bitbake -c install $app" "$KAS_CONFIG" >"$log" 2>&1 ||
		{ tail -20 "$log" >&2; die "build failed; see $log"; }
	local bin
	bin=$(ls -t "$TOP"/build/tmp/work/*/"$app"/*/image/usr/bin/"$app" 2>/dev/null | head -1)
	[ -n "$bin" ] || die "no $app binary in the build tree; see $log"
	echo "Built in $((SECONDS - start)) s"

	# systemctl restart returns once the new binary reports its first frame.
	local new=/usr/bin/$app.new
	local install="chmod 0755 $new && mv -f $new /usr/bin/$app && systemctl restart $app && journalctl -u $app -n 3 --no-pager"
	if [ -n "$host" ]; then
		[[ $host == *@* ]] || host=root@$host
		echo "Installing on $host"
		# Every flash gives the board new host keys: neither record nor check them.
		ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR \
			-o ConnectTimeout=10 "$host" "cat > $new && $install" <"$bin"
	else
		echo "Installing over adb"
		adb push "$bin" "$new" >/dev/null && adb shell "$install"
	fi
}

# Prints the sysfs path of the board in EDL mode (05c6:9008), if connected.
edl_device() {
	local d
	for d in /sys/bus/usb/devices/*; do
		[ "$(cat "$d/idVendor" 2>/dev/null)" = 05c6 ] &&
		[ "$(cat "$d/idProduct" 2>/dev/null)" = 9008 ] && { echo "$d"; return 0; }
	done
	return 1
}

cmd_flash() {
	select_image "${1:-}"
	local src
	src=$(readlink -e "$DEPLOY/$TARGET-$MACHINE.rootfs.qcomflash") && [ -f "$src/rawprogram0.xml" ] ||
		die "no $TARGET build found in $DEPLOY; run: ./uno-q.sh build ${1:-fastboot}"
	local qdl
	qdl=$(command -v qdl) || die "qdl not found (sudo snap install qdl)"

	# The board fails to enable USB3 link power management (U1/U2) in EDL;
	# tell the kernel not to try. Takes effect when the board (re)connects.
	local quirks=/sys/module/usbcore/parameters/quirks
	if ! grep -q '05c6:9008:k' "$quirks"; then
		local cur; cur=$(cat "$quirks")
		echo "Disabling USB link power management for the board (until reboot)..."
		echo "${cur:+$cur,}05c6:9008:k" | sudo tee "$quirks" >/dev/null
		if edl_device >/dev/null; then
			echo "The board was connected before this took effect: unplug it now."
			while edl_device >/dev/null; do sleep 1; done
		fi
	fi

	local dev
	if ! dev=$(edl_device); then
		echo "Waiting for the board in EDL mode (05c6:9008)..."
		until dev=$(edl_device); do sleep 1; done
	fi
	local speed; speed=$(cat "$dev/speed")
	echo "Board connected at ${speed} Mb/s."
	[ "$speed" -le 480 ] || echo "Note: flashing has failed over USB3 on this PC; a USB 2.0 cable or hub is more reliable."

	# The qdl snap may only read non-hidden paths under $HOME, so bind-mount the
	# image there, on a fresh mount point that cannot collide with a leftover one.
	local dir=$src mnt=
	if [[ $qdl == /snap/* ]]; then
		mnt=$(mktemp -d "$HOME/uno-q-flash.XXXXXX")
		# Expanded now: $mnt is local and gone by the time the EXIT trap runs.
		trap "cd /; mountpoint -q '$mnt' && sudo umount '$mnt'; rmdir '$mnt'" EXIT
		trap 'exit 130' INT TERM
		sudo mount --bind "$src" "$mnt"
		dir=$mnt
	fi

	echo "Flashing $(basename "$src")"
	cd "$dir"
	local -a extra=()
	read -ra extra <<<"${QDL_ARGS:-}"
	local -a sudo=()
	[[ $qdl == /snap/* ]] || sudo=(sudo)  # a native qdl needs root for USB access
	"${sudo[@]}" "$qdl" --storage emmc "${extra[@]}" prog_firehose_ddr.elf rawprogram0.xml patch0.xml
}

case "${1:-}" in
build) shift; cmd_build "$@" ;;
flash) shift; cmd_flash "$@" ;;
deploy) shift; cmd_deploy "$@" ;;
-h|--help|help) usage ;;
*) usage 1 ;;
esac
