if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES arm64)
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 13.0)
endif()
set(CORE ${PROJECT_SOURCE_DIR}/Src/Orbiter)
add_library(OrbiterFlightCore STATIC
    ${CORE}/Vecmat.cpp ${CORE}/Astro.cpp ${CORE}/Element.cpp ${CORE}/TimeData.cpp
    Flight.cpp Mesh.cpp Glider.cpp Aerodynamics.cpp Cockpit.cpp Surface.cpp Base.cpp Hover.cpp Exhaust.cpp)
target_include_directories(OrbiterFlightCore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR} ${CORE})
target_compile_definitions(OrbiterFlightCore PUBLIC ORBITER_NATIVE=1)
target_compile_options(OrbiterFlightCore PRIVATE -Wall -Wextra -Wno-unused-parameter -Wno-unused-variable)
add_executable(OrbiterNative MACOSX_BUNDLE macOS/App.mm macOS/GliderPanel.inc)
target_compile_options(OrbiterNative PRIVATE -fobjc-arc -Wall -Wextra -Wno-unused-parameter)
target_link_libraries(OrbiterNative PRIVATE OrbiterFlightCore
    "-framework UniformTypeIdentifiers" "-framework Cocoa" "-framework Metal" "-framework MetalKit" "-framework QuartzCore")
set_target_properties(OrbiterNative PROPERTIES
    OUTPUT_NAME "Orbiter Native"
    MACOSX_BUNDLE_BUNDLE_NAME "Orbiter Native"
    MACOSX_BUNDLE_GUI_IDENTIFIER "space.orbiter.native"
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/macOS/Info.plist.in)
file(GLOB_RECURSE NATIVE_ASSET_INPUTS CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/Assets/*
    ${PROJECT_SOURCE_DIR}/Src/Vessel/DeltaGlider/Textures/*
    ${PROJECT_SOURCE_DIR}/Src/Vessel/DeltaGlider/Textures2/*.dds)
file(GLOB BASE_TEXTURE_INPUTS CONFIGURE_DEPENDS ${PROJECT_SOURCE_DIR}/Textures/*.dds)
set_property(TARGET OrbiterNative APPEND PROPERTY LINK_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/macOS/Shaders.metal
    ${CMAKE_CURRENT_SOURCE_DIR}/PackageAssets.cmake
    ${PROJECT_SOURCE_DIR}/Src/Vessel/DeltaGlider/Meshes/deltaglider_ns.msh
    "${PROJECT_SOURCE_DIR}/Scenarios/Delta-glider/DG Mk4 in orbit.scn"
    ${PROJECT_SOURCE_DIR}/Src/Celbody/Vsop87/Earth/Config/Earth/Base/Canaveral.cfg
    ${PROJECT_SOURCE_DIR}/Meshes/Tarmac2.msh
    ${BASE_TEXTURE_INPUTS}
    ${NATIVE_ASSET_INPUTS})
add_custom_command(TARGET OrbiterNative POST_BUILD
    COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_SOURCE_DIR}/PackageAssets.cmake
        -- ${PROJECT_SOURCE_DIR} "$<TARGET_BUNDLE_DIR:OrbiterNative>/Contents/Resources")
add_executable(NativeTests Tests/FlightTests.cpp)
target_link_libraries(NativeTests PRIVATE OrbiterFlightCore)
target_compile_definitions(NativeTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.Flight COMMAND NativeTests)
add_executable(GliderTests Tests/GliderTests.cpp)
target_link_libraries(GliderTests PRIVATE OrbiterFlightCore)
add_test(NAME Native.Glider COMMAND GliderTests)
add_executable(SurfaceTests Tests/SurfaceTests.cpp)
target_link_libraries(SurfaceTests PRIVATE OrbiterFlightCore)
target_compile_definitions(SurfaceTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.Surface COMMAND SurfaceTests)
add_executable(HoverTests Tests/HoverTests.cpp)
target_link_libraries(HoverTests PRIVATE OrbiterFlightCore)
target_compile_definitions(HoverTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.Hover COMMAND HoverTests)

add_executable(ExhaustTests Tests/ExhaustTests.cpp)
target_link_libraries(ExhaustTests PRIVATE OrbiterFlightCore)
add_test(NAME Native.Exhaust COMMAND ExhaustTests)
