cmake_minimum_required(VERSION 3.16)
project(tsumiru_linux_engine LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
find_package(PkgConfig REQUIRED)
foreach(package GTK:gtk+-3.0 EPOXY:epoxy EGL:egl X11:x11 WAYLAND:wayland-client WAYLAND_EGL:wayland-egl)
  string(REPLACE ":" ";" parts "${package}")
  list(GET parts 0 name)
  list(GET parts 1 module)
  pkg_check_modules(${name} REQUIRED IMPORTED_TARGET ${module})
endforeach()
pkg_get_variable(PROTOCOLS_DIR wayland-protocols pkgdatadir)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(PRESENTATION_XML "${PROTOCOLS_DIR}/stable/presentation-time/presentation-time.xml")
add_custom_command(
  OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/presentation-time-client-protocol.h"
         "${CMAKE_CURRENT_BINARY_DIR}/presentation-time-protocol.c"
  COMMAND ${WAYLAND_SCANNER} client-header "${PRESENTATION_XML}" "${CMAKE_CURRENT_BINARY_DIR}/presentation-time-client-protocol.h"
  COMMAND ${WAYLAND_SCANNER} private-code "${PRESENTATION_XML}" "${CMAKE_CURRENT_BINARY_DIR}/presentation-time-protocol.c"
  DEPENDS "${PRESENTATION_XML}")
add_custom_target(presentation_protocol DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/presentation-time-client-protocol.h")

include("${SOURCE_MANIFEST}")
add_library(flutter_linux_gtk SHARED ${FLUTTER_LINUX_SOURCES}
  "${CMAKE_CURRENT_BINARY_DIR}/presentation-time-protocol.c")
add_dependencies(flutter_linux_gtk presentation_protocol)
target_compile_definitions(flutter_linux_gtk PRIVATE FLUTTER_LINUX_COMPILATION FLUTTER_ENGINE_NO_PROTOTYPES)
option(BUILD_TESTING "Enable the native FFI smoke probe" OFF)
if(BUILD_TESTING)
  target_compile_definitions(flutter_linux_gtk PRIVATE TSUMIRU_NATIVE_TESTING)
endif()
target_include_directories(flutter_linux_gtk PRIVATE
  "${ENGINE_SRC}" "${ENGINE_SRC}/flutter/shell/platform/linux/public"
  "${DART_INCLUDE}" "${RAPIDJSON_SRC}/include" "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(flutter_linux_gtk PRIVATE
  PkgConfig::GTK PkgConfig::EPOXY PkgConfig::EGL PkgConfig::X11
  PkgConfig::WAYLAND PkgConfig::WAYLAND_EGL "${ENGINE_CORE}")
target_link_options(flutter_linux_gtk PRIVATE "-Wl,--no-undefined")
set_target_properties(flutter_linux_gtk PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE INSTALL_RPATH "$ORIGIN"
  LIBRARY_OUTPUT_DIRECTORY "${NATIVE_OUTPUT}")
