# Unreal visual frontend

Experimental Unreal Engine **5.8.2** frontend for the native Apple Silicon port. The original C++ orbital, glider, aerodynamic, ground-contact and hover controllers remain in `OrbiterFlightCore`. Unreal supplies rendering and input; Chaos does not integrate the spacecraft.

The existing `Orbiter Native.app` remains the separate, playable Metal frontend. This Unreal migration is being developed in tested increments; editor compilation and simulation tests alone do not establish visual quality or frame rate.

## Build and run

Requires UE 5.8, CMake, Xcode and its Metal toolchain. The default engine path is `/Users/Shared/Epic Games/UE_5.8`; override it with `ORBITER_UE_ROOT`.

```sh
./Unreal/build.sh
./Unreal/run.sh
./Unreal/run.sh -surface
```

If Unreal reports that the Metal compiler is missing:

```sh
xcodebuild -downloadComponent MetalToolchain
```

The build creates an arm64 simulation library, stages the original glider/scenarios and generates Unreal materials from `Tools/build_assets.py`. Generated engine files and imported assets are excluded from Git.

For the simulation bridge automation test, run `./Unreal/build.sh --test`. It loads the original orbital scenario and geometry, advances the original integrator, and verifies the existing 100 m hover controller and engine cutoff inside Unreal.

Controls in this initial frontend: arrows/Q/E attitude, +/- main thrust, brackets hover thrust, X cutoff, G gear, C nose, F radiator, F6/F7 hover hold, Space pause, R restart. Drag to orbit the external camera and scroll to zoom. The original native cockpit UI has not yet migrated.

## Coordinate frame

Simulation position, velocity and time stay in the native library's double precision ecliptic frame, in metres and seconds. Rendering places the spacecraft near the origin and translates Earth by the opposite simulation position. Native `(right, up, forward)` maps to Unreal `(forward, right, up)` and metres map to centimetres. Animations come from the same original Delta-glider transforms as the Metal frontend.

A bounded render check accepts `-OrbiterFrames=240 -OrbiterCapture=/absolute/path/preview.png`. Input does not affect the simulation during that check. A successful run prints `ORBITER_SMOKE_OK`; the screenshot must also be inspected.

## Earth and visual weather

The globe uses the versioned 8K NASA Blue Marble monthly composite, with mipmaps and an 8192-pixel World texture limit. See `SourceAssets/CREDITS.md` for provenance and resolution limits. The globe rotates with the same sidereal time and axial tilt as the ground simulation.

Unreal Sky Atmosphere and volumetric clouds provide the atmospheric limb, cloud lighting and cloud shadows. W cycles clear, scattered, overcast and storm visual presets. These are synthetic weather presets, not live weather or a meteorological simulation. The camera uses physical daylight exposure (ISO 100, f/16, 1/125 s) with a 110,000 lux sun.

Validation: the arm64 editor module builds; the native bridge automation test passed; a 1600 × 1000 Metal render check completed with the original glider, a curved atmospheric horizon and visible volumetric clouds. Performance has not yet been measured for the finished effects.

## Exhaust and RCS

Main, retro, hover and RCS nozzles use the applied, fuel-scaled commands from the shared flight model. Main balance and gimbals, all three independent hover outputs, and both signs of all rotation/translation axes drive their own particles. Nozzles retain the original Delta-glider visual positions. Atmospheric pressure controls plume expansion and lifetime. Soft additive particles fade with age and scene depth; main-engine glow lights the rear hull.

These are bounded visual particles, not a computational fluid dynamics model or a calibrated propellant spectrum. The system caps tail particles at 1536 and batches them in one mesh section. A second bounded mesh supplies continuous three-dimensional flame cores at the nozzle mouths.

- **M:** cycle RCS rotation → translation → off.
- **Arrows / Q / E:** attitude in rotation mode; arrows give lateral/vertical translation and Q/E give forward/back translation in translation mode.
- **Numpad 8 / 2:** forward/back translation.
- **Numpad 6 / 4:** right/left translation.
- **Numpad 9 / 3:** up/down translation.
- **K:** toggle kill rotation.
- **T / Y:** increase/decrease simulation time acceleration. The simulation returns to real time for powered flight.
- **F5:** toggle hover attitude control; **F6/F7:** toggle altitude/zero vertical speed hold.

The separate RCS tank, RCS-off state and fuel exhaustion remain part of the flight model. Native exhaust tests check torque and force direction for both signs on every axis, mixer output, cutoff and vacuum expansion (48 checks). All six native suites pass in Release and with address/undefined-behavior sanitizers.

Material generation validates every graph connection. Editor render checks wait for shader and texture compilation before capturing a frame. The global globe does not cast mesh shadows; atmospheric transmittance handles planet-scale sunlight, and clouds cast their own shadows. The analytic atmospheric ground lies 500 m below the globe radius to avoid intersecting the globe's polygon chords.

The current procedural spacecraft has no Lumen distance-field representation. The default uses direct solar lighting, atmospheric transmittance, captured sky lighting and screen-space reflections; hardware ray tracing is disabled. Cloud ray samples are capped through the component's 0.75 view sample scale. This configuration preserves the current lighting while avoiding unsupported procedural-mesh Lumen work.


## Standalone app

Run `./Unreal/package.sh` after installing the build dependencies. It builds the editor/core/assets and creates the self-contained arm64 Development app in `../Orbiter-Unreal-Apple-Silicon/Mac/OrbiterUE.app`. The packaged app requires macOS 14 or newer and does not require the Unreal editor to run. It uses local signing; Developer ID distribution/notarization is not configured.

Packaging settings live in `DefaultGame.ini`, including the original simulation data staged as loose files for the C++ parsers. Materials and the cloud assets are explicitly cooked. The script includes a tested fallback for the local UE 5.8.2/Xcode 27.1 post-build failure: it finalizes the generated Xcode project directly, invokes Unreal's metadata writer for that compiled target, then resumes cooking/staging. It does not modify the installed engine. Logs are in `Saved/Packaging`.

This is an external-flight preview. The native cockpit UI, full instrumentation and detailed local terrain/base rendering remain in the Metal frontend. Visual weather uses presets; live meteorological data and weather-driven flight forces are not implemented.


## 0.5.1 plume alignment correction

The entry map's PlayerStart offset is removed from the ship-centred render frame. Flame origins and emission directions use the exact rendered vessel transform, including translation, rather than a separate assumption that the visible craft is at the origin. Main visual origins are on the original mesh's nozzle lips at z = -8.043 m; the force application points at -7.7 m remain unchanged in the flight model.

Continuous blue-white cores stay attached to the mouths; thin blue particles fade downstream. Core depth testing still respects the hull, but the former one-metre soft-particle fade cannot erase the flame base. Regression checks compare the visual origins to the original mesh and verify agreement between the simulation and rendered nozzle frames under nonzero spawn offsets and different attitudes. Rear and side Metal render checks at 80% main thrust verify the alignment visually.

Generated materials carry schema metadata so a rebuild upgrades cached materials after changes to their graphs.


## 0.5.2 native camera response

The orbit controller uses the same .009 radians per mouse point and exponential scroll curve as the Cocoa/Metal version. Window-local Cocoa events retain fractional motion and bypass Unreal's sensitivity, FOV scaling and mouse smoothing. Position-based fallback handles coalesced/accessibility-generated drags. The listener is removed when the game world ends, and events from other windows are ignored.

The external camera uses the native radial/velocity reference frame, so spacecraft attitude changes do not roll the orbital chase view. Near the surface it follows the native heading/ground-clearance behavior. Camera tests cover event batching, subpixel motion, sensitivity, pitch/distance limits, radial motion and reference-frame stability.

Retina output uses Metal dynamic resolution with a 16.667 ms GPU budget and a 40–100% internal render range; TSR reconstructs the output and HUD stays at output resolution. The packaged 0.5.2 app averaged 61.9 FPS at 4112 × 2580 output on the M4 Max, using the 40% internal limit. This is an adaptive-resolution measurement, not native-resolution 4K rendering. Motion blur is disabled for a crisp orbit response.
