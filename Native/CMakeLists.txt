if(NOT CMAKE_OSX_ARCHITECTURES)
    set(CMAKE_OSX_ARCHITECTURES arm64)
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 13.0)
endif()
set(CORE ${PROJECT_SOURCE_DIR}/Src/Orbiter)
add_library(OrbiterFlightCore STATIC
    ${CORE}/Vecmat.cpp ${CORE}/Astro.cpp ${CORE}/Element.cpp ${CORE}/TimeData.cpp
    Body.cpp SolarSystem.cpp
    ${PROJECT_SOURCE_DIR}/Src/Celbody/Moon/ELP82.cpp
    ${PROJECT_SOURCE_DIR}/Src/Celbody/Galsat/Lieske.cpp
    ${PROJECT_SOURCE_DIR}/Src/Celbody/Satsat/Tass17.cpp
    Flight.cpp Mesh.cpp Glider.cpp Aerodynamics.cpp Weather.cpp Cockpit.cpp Surface.cpp Base.cpp Hover.cpp Exhaust.cpp Camera.cpp ISS.cpp)
target_include_directories(OrbiterFlightCore PUBLIC ${CMAKE_CURRENT_SOURCE_DIR} ${CORE})
target_compile_definitions(OrbiterFlightCore PUBLIC ORBITER_NATIVE=1)
target_compile_options(OrbiterFlightCore PRIVATE -Wall -Wextra -Wno-unused-parameter -Wno-unused-variable)
add_executable(OrbiterNative MACOSX_BUNDLE macOS/App.mm macOS/CockpitHUD.mm macOS/NativeVisuals.mm macOS/SolarRenderer.mm macOS/RayShadows.mm macOS/GliderPanel.inc macOS/TransXPanel.inc macOS/RoutePanel.inc macOS/Panel2D.inc macOS/BurnDisplay.h macOS/DateDisplay.h macOS/TransXDrawing.mm)
target_compile_options(OrbiterNative PRIVATE -fobjc-arc -Wall -Wextra -Wno-unused-parameter)
target_link_libraries(OrbiterNative PRIVATE
    "-framework UniformTypeIdentifiers" "-framework Cocoa" "-framework Metal" "-framework MetalKit" "-framework QuartzCore")
set_target_properties(OrbiterNative PROPERTIES
    OUTPUT_NAME "Orbiter Native"
    MACOSX_BUNDLE_BUNDLE_NAME "Orbiter Native"
    MACOSX_BUNDLE_GUI_IDENTIFIER "space.orbiter.native"
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/macOS/Info.plist.in)
file(GLOB_RECURSE NATIVE_ASSET_INPUTS CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/Assets/*
    ${PROJECT_SOURCE_DIR}/Src/Vessel/DeltaGlider/Textures/*
    ${PROJECT_SOURCE_DIR}/Src/Vessel/DeltaGlider/Textures2/*.dds
    ${PROJECT_SOURCE_DIR}/Src/Vessel/ISS/Textures/*)
file(GLOB BASE_TEXTURE_INPUTS CONFIGURE_DEPENDS ${PROJECT_SOURCE_DIR}/Textures/*.dds)
set_property(TARGET OrbiterNative APPEND PROPERTY LINK_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/macOS/Shaders.metal
    ${CMAKE_CURRENT_SOURCE_DIR}/macOS/NativeVisuals.metal
    ${CMAKE_CURRENT_SOURCE_DIR}/macOS/SolarSystem.metal
    ${CMAKE_CURRENT_SOURCE_DIR}/macOS/RayShadows.metal
    ${CMAKE_CURRENT_SOURCE_DIR}/macOS/VisualTypes.h
    ${CMAKE_CURRENT_SOURCE_DIR}/PackageAssets.cmake
    ${PROJECT_SOURCE_DIR}/Src/Vessel/DeltaGlider/Meshes/deltaglider_ns.msh
    ${PROJECT_SOURCE_DIR}/Src/Vessel/ISS/Meshes/ProjectAlpha_ISS.msh
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
add_executable(TimeAccelerationTests Tests/TimeAccelerationTests.cpp)
target_link_libraries(TimeAccelerationTests PRIVATE OrbiterFlightCore)
add_test(NAME Native.TimeAcceleration COMMAND TimeAccelerationTests)
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
target_compile_definitions(ExhaustTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.Exhaust COMMAND ExhaustTests)

add_executable(ExhaustRenderTests Tests/ExhaustRenderTests.mm)
target_include_directories(ExhaustRenderTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/macOS)
target_compile_options(ExhaustRenderTests PRIVATE -fobjc-arc)
target_compile_definitions(ExhaustRenderTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
target_link_libraries(ExhaustRenderTests PRIVATE "-framework Foundation" "-framework Metal")
add_test(NAME Native.ExhaustMetal COMMAND ExhaustRenderTests)
set_tests_properties(Native.ExhaustMetal PROPERTIES SKIP_RETURN_CODE 77)

add_executable(EarthRenderTests Tests/EarthRenderTests.mm)
target_include_directories(EarthRenderTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/macOS)
target_compile_options(EarthRenderTests PRIVATE -fobjc-arc)
target_compile_definitions(EarthRenderTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
target_link_libraries(EarthRenderTests PRIVATE "-framework Cocoa" "-framework Metal" "-framework MetalKit")
add_test(NAME Native.EarthMetal COMMAND EarthRenderTests)
set_tests_properties(Native.EarthMetal PROPERTIES SKIP_RETURN_CODE 77)

add_executable(SunsetRenderTests Tests/SunsetRenderTests.mm)
target_include_directories(SunsetRenderTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/macOS)
target_compile_options(SunsetRenderTests PRIVATE -fobjc-arc)
target_compile_definitions(SunsetRenderTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
target_link_libraries(SunsetRenderTests PRIVATE OrbiterFlightCore "-framework Cocoa" "-framework Metal" "-framework MetalKit")
add_test(NAME Native.SunsetMetal COMMAND SunsetRenderTests)
set_tests_properties(Native.SunsetMetal PROPERTIES SKIP_RETURN_CODE 77)
add_test(NAME Native.SunsetLateMetal COMMAND SunsetRenderTests)
set_tests_properties(Native.SunsetLateMetal PROPERTIES SKIP_RETURN_CODE 77 ENVIRONMENT "ORBITER_SUNSET_ELAPSED=970")
add_executable(ExposureRenderTests Tests/ExposureRenderTests.mm)
target_include_directories(ExposureRenderTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/macOS)
target_compile_options(ExposureRenderTests PRIVATE -fobjc-arc)
target_compile_definitions(ExposureRenderTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
target_link_libraries(ExposureRenderTests PRIVATE "-framework Cocoa" "-framework Metal")
add_test(NAME Native.ExposureMetal COMMAND ExposureRenderTests)
set_tests_properties(Native.ExposureMetal PROPERTIES SKIP_RETURN_CODE 77)

add_executable(CockpitHudRenderTests Tests/CockpitHudRenderTests.mm macOS/CockpitHUD.mm)
target_include_directories(CockpitHudRenderTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/macOS)
target_compile_options(CockpitHudRenderTests PRIVATE -fobjc-arc)
target_compile_definitions(CockpitHudRenderTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
target_link_libraries(CockpitHudRenderTests PRIVATE OrbiterFlightCore "-framework Cocoa" "-framework Metal")
add_test(NAME Native.CockpitHudMetal COMMAND CockpitHudRenderTests)
set_tests_properties(Native.CockpitHudMetal PROPERTIES SKIP_RETURN_CODE 77)

add_executable(CockpitRainRenderTests Tests/CockpitRainRenderTests.mm)
target_include_directories(CockpitRainRenderTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/macOS)
target_compile_options(CockpitRainRenderTests PRIVATE -fobjc-arc)
target_compile_definitions(CockpitRainRenderTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
target_link_libraries(CockpitRainRenderTests PRIVATE OrbiterFlightCore "-framework Cocoa" "-framework Metal")
add_test(NAME Native.CockpitRainMetal COMMAND CockpitRainRenderTests)
set_tests_properties(Native.CockpitRainMetal PROPERTIES SKIP_RETURN_CODE 77)

add_executable(RayShadowRenderTests Tests/RayShadowRenderTests.mm macOS/RayShadows.mm)
target_include_directories(RayShadowRenderTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/macOS)
target_compile_options(RayShadowRenderTests PRIVATE -fobjc-arc)
target_compile_definitions(RayShadowRenderTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
target_link_libraries(RayShadowRenderTests PRIVATE OrbiterFlightCore "-framework Cocoa" "-framework Metal")
add_test(NAME Native.RayShadowMetal COMMAND RayShadowRenderTests)
set_tests_properties(Native.RayShadowMetal PROPERTIES SKIP_RETURN_CODE 77)

add_executable(BodyRotationTests Tests/BodyRotationTests.cpp)
target_link_libraries(BodyRotationTests PRIVATE OrbiterFlightCore)
target_compile_definitions(BodyRotationTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.BodyRotation COMMAND BodyRotationTests)

add_executable(KeyboardTests Tests/KeyboardTests.cpp)
target_link_libraries(KeyboardTests PRIVATE OrbiterFlightCore)
add_test(NAME Native.Keyboard COMMAND KeyboardTests)

add_executable(AtmosphericPanelTests Tests/AtmosphericPanelTests.mm)
target_compile_options(AtmosphericPanelTests PRIVATE -fobjc-arc)
target_compile_definitions(AtmosphericPanelTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
target_link_libraries(AtmosphericPanelTests PRIVATE OrbiterFlightCore "-framework Cocoa")
add_test(NAME Native.AtmosphericPanel COMMAND AtmosphericPanelTests)

add_executable(AtmosphericControlTests Tests/AtmosphericControlTests.cpp)
target_link_libraries(AtmosphericControlTests PRIVATE OrbiterFlightCore)
target_compile_definitions(AtmosphericControlTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.AtmosphericControl COMMAND AtmosphericControlTests)

add_executable(AtmosphericScenarioTests Tests/AtmosphericScenarioTests.cpp)
target_link_libraries(AtmosphericScenarioTests PRIVATE OrbiterFlightCore)
target_compile_definitions(AtmosphericScenarioTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.AtmosphericScenarios COMMAND AtmosphericScenarioTests)

add_executable(WeatherTests Tests/WeatherTests.cpp)
target_link_libraries(WeatherTests PRIVATE OrbiterFlightCore)
target_compile_definitions(WeatherTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.Weather COMMAND WeatherTests)

add_executable(CameraTests Tests/CameraTests.cpp)
target_link_libraries(CameraTests PRIVATE OrbiterFlightCore)
target_compile_definitions(CameraTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.Camera COMMAND CameraTests)
add_executable(ISSTests Tests/ISSTests.cpp)
target_link_libraries(ISSTests PRIVATE OrbiterFlightCore)
target_compile_definitions(ISSTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.ISS COMMAND ISSTests)
add_executable(ISSRenderTests Tests/ISSRenderTests.mm)
target_include_directories(ISSRenderTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/macOS)
target_compile_options(ISSRenderTests PRIVATE -fobjc-arc)
target_compile_definitions(ISSRenderTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
target_link_libraries(ISSRenderTests PRIVATE OrbiterFlightCore "-framework Cocoa" "-framework Metal")
add_test(NAME Native.ISSMetal COMMAND ISSRenderTests)
set_tests_properties(Native.ISSMetal PROPERTIES SKIP_RETURN_CODE 77)

add_executable(NavProgramTests Tests/NavProgramTests.cpp)
target_link_libraries(NavProgramTests PRIVATE OrbiterFlightCore)
add_test(NAME Native.NavPrograms COMMAND NavProgramTests)

add_executable(SolarSystemTests Tests/SolarSystemTests.cpp)
target_link_libraries(SolarSystemTests PRIVATE OrbiterFlightCore)
target_compile_definitions(SolarSystemTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}")
add_test(NAME Native.SolarSystem COMMAND SolarSystemTests)

# Compile the original TransX algorithms and MFD against the native host API.
file(GLOB TRANSX_ORIGINAL_SOURCES ${PROJECT_SOURCE_DIR}/Src/Plugin/TransX/*.cpp)
add_library(NativeTransX STATIC ${TRANSX_ORIGINAL_SOURCES} TransX/SDK.cpp TransX/Session.cpp TransX/WindowSearch.cpp TransX/BurnSkip.cpp)
target_link_libraries(NativeTransX PUBLIC OrbiterFlightCore)
target_include_directories(NativeTransX PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/TransX ${PROJECT_SOURCE_DIR}/Src/Plugin/TransX)
target_compile_definitions(NativeTransX PRIVATE _LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR)
target_compile_options(NativeTransX PRIVATE -include ${CMAKE_CURRENT_SOURCE_DIR}/TransX/SDK.h -Wno-deprecated-declarations -Wno-writable-strings)
add_executable(TransXTests Tests/TransXTests.cpp)
target_link_libraries(TransXTests PRIVATE NativeTransX)
target_compile_definitions(TransXTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}" _LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR)
add_test(NAME Native.TransX COMMAND TransXTests)
add_executable(RouteTests Tests/RouteTests.cpp)
target_link_libraries(RouteTests PRIVATE NativeTransX)
target_compile_definitions(RouteTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}" _LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR)
add_test(NAME Native.Route COMMAND RouteTests)
add_executable(WindowSearchTests Tests/WindowSearchTests.cpp)
target_link_libraries(WindowSearchTests PRIVATE NativeTransX)
target_compile_definitions(WindowSearchTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}" _LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR)
add_test(NAME Native.WindowSearch COMMAND WindowSearchTests)
add_executable(BurnSkipTests Tests/BurnSkipTests.cpp)
target_link_libraries(BurnSkipTests PRIVATE NativeTransX)
target_compile_definitions(BurnSkipTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}" _LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR)
add_test(NAME Native.BurnSkip COMMAND BurnSkipTests)
add_executable(RoutePanelTests Tests/RoutePanelTests.mm macOS/TransXDrawing.mm)
target_compile_options(RoutePanelTests PRIVATE -fobjc-arc)
target_compile_definitions(RoutePanelTests PRIVATE ORBITER_TEST_DATA="${PROJECT_SOURCE_DIR}" _LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR)
target_include_directories(RoutePanelTests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/macOS)
target_link_libraries(RoutePanelTests PRIVATE NativeTransX "-framework Cocoa" "-framework QuartzCore")
add_test(NAME Native.RoutePanel COMMAND RoutePanelTests)

target_link_libraries(OrbiterNative PRIVATE NativeTransX)
