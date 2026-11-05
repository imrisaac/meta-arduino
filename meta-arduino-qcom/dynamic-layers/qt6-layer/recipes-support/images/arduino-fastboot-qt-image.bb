require recipes-support/images/arduino-fastboot-image.bb

SUMMARY = "Arduino fast-boot image with the Qt Quick cluster"
DESCRIPTION = "arduino-fastboot-image with arduino-cluster, a QML instrument \
cluster rendered on the GPU, as the application on the boot critical path. \
Build it with ci/fastboot.yml:ci/qt.yml."

FASTBOOT_APP = "arduino-cluster"

# Development: USB mouse input for the cluster. Remove it to measure boot time,
# as Qt then sets up its input handling before the first frame.
IMAGE_INSTALL += "arduino-cluster-mouse"

# Qualcomm's proprietary Adreno EGL needs the out-of-tree KGSL driver and would
# take precedence over Mesa in glvnd. The cluster renders through Mesa
# (freedreno) on the upstream msm driver; fail the build if anything pulls the
# proprietary EGL in.
PACKAGE_EXCLUDE += "qcom-adreno-egl"
