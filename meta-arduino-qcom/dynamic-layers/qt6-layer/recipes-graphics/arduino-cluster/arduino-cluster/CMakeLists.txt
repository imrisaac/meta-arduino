cmake_minimum_required(VERSION 3.21)
project(arduino-cluster LANGUAGES CXX)

find_package(Qt6 6.5 REQUIRED COMPONENTS Gui Quick)
find_package(PkgConfig REQUIRED)
pkg_check_modules(DRM REQUIRED IMPORTED_TARGET libdrm)
pkg_check_modules(SYSTEMD REQUIRED IMPORTED_TARGET libsystemd)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(arduino-cluster main.cpp)

# The QML is compiled ahead of time and linked into the executable, so
# startup neither parses QML nor loads a plugin for it.
qt_add_qml_module(arduino-cluster
    URI Cluster
    QML_FILES Main.qml Cluster.qml Gauge.qml CameraView.qml
)

target_link_libraries(arduino-cluster PRIVATE
    Qt6::Gui Qt6::Quick PkgConfig::DRM PkgConfig::SYSTEMD)

install(TARGETS arduino-cluster RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
