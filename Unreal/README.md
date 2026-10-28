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
