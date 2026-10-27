# Orbiter Native — first playable milestone

A partial native Apple Silicon port of the supplied Orbiter source. The application runs a Delta-glider flight in Earth orbit with a Metal renderer. This is an experimental standalone flight target, **not a complete port of Orbiter**.

## Implemented

- Native ARM64 executable using Apple's Cocoa, Metal and MetalKit frameworks. No external runtime libraries, Rosetta, Wine, Windows VM, or browser.
- Original `Element.cpp`, `Vecmat.cpp`, `Astro.cpp` and `TimeData.cpp` compile into the native flight library with small portability changes.
- The original standard Delta-glider mesh, 122 groups, 11,803 triangles, original materials and DDS textures. A native DDS decoder loads BC1/BC2/BC3 and RGB(A) files, with mipmaps generated once at startup.
- Double-precision simulation state. Original Kepler propagation during unpowered coasting; a new RK4 flight layer during powered maneuvers. The full `Vessel` and `BodyIntegrator` engine is not compiled into this target.
- Main engine thrust and fuel consumption based on the standard DG easy-model parameters: two 200 kN engines, 40,000 m/s exhaust velocity, 12,900 kg main propellant capacity, 600 kg RCS propellant capacity, 11,000 kg empty mass.
- Keyboard attitude and axial RCS controls, simplified attitude assists, pause, 1×–1000× time acceleration, external orbit camera and forward view.
- Live orbit/propulsion readouts and orbit diagram; scenario open/save for supported Earth-orbit DeltaGlider focus vessels. Position, velocity, attitude, angular rates, date and propellant are saved.
- Full Retina resolution, 4× MSAA where supported, native window resizing and fullscreen.

## Run

Open `Orbiter Native.app`. It starts directly in the supplied `DG Mk4 in orbit` scenario, roughly 168 km above Earth.

For a first burn: press **P** to align prograde, hold **+** for about one second to raise the throttle, watch apoapsis rise, then press **X** to cut the engines. Press **Space** to pause.

| Control | Action |
| --- | --- |
| + / − (or keypad + / −) | Increase / decrease main throttle |
| X | Cut main engines |
| Arrow keys | Pitch and yaw |
| Q / E | Roll |
| W / S | Forward / reverse RCS translation |
| P / O | Prograde / retrograde assist |
| K / N | Kill rotation / manual attitude |
| T / Y | Increase / decrease time acceleration |
| V | External / forward view |
| Drag / scroll | Orbit external camera / zoom |
| Space | Pause / resume |
| R | Restart supplied flight |
| F1 or Flight → Flight Controls | Show controls |
| F2 | Show / hide orbit diagram |
| ⌘O / ⌘S | Open / save scenario |
| ⌘Q | Quit |

Time acceleration automatically returns to 1× during manual maneuvers or engine burns. Prograde/retrograde alignment and manual attitude dynamics are simplified in this milestone. The forward view is not an interactive cockpit.

## Build

Requires macOS 13 or newer on Apple Silicon, Xcode command-line tools, and CMake 3.19+. All required game assets are in this source tree; the native build does not fetch dependencies.

```sh
./Native/build.sh --run
```

The result is `build/macos-arm64/Native/Orbiter Native.app`. `ORBITER_NATIVE_BUILD_DIR` can select another build directory. The script runs the flight tests and applies a local ad-hoc signature. No Apple Developer account is needed for this local build; it is not notarized for public distribution.

For a bounded render/performance run:

```sh
"build/macos-arm64/Native/Orbiter Native.app/Contents/MacOS/Orbiter Native" \
  --frames 600 --capture /absolute/path/frame.png --report /absolute/path/performance.json
```

`--scenario /absolute/path/file.scn` selects a supported scenario. `--prograde` enables the prograde assist for a repeatable demonstration. Frame runs ignore manual keyboard/camera input to keep captures repeatable. Reported presentation speed depends on the display's active refresh mode, window visibility and system load; GPU render time is measured separately. The current display configuration is not changed.

## Not ported yet

- The complete Orbiter simulation graph: moving solar-system bodies, SPICE kernels, perturbations, atmospheric models, aerodynamics, surface bases and terrain.
- The original Delta-glider systems and clickable 2D/3D cockpit, animations, hover and retro engine systems, docking, other vessels, stations, and collision response. Surface contact stops this prototype flight.
- Original Windows DLL plug-ins, Lua scripting/MFDs, Direct3D graphics-client API, XRSound, and launcher settings.
- Original scenario support beyond an Earth-orbit DeltaGlider focus vessel. Other objects in a supported scenario are not instantiated. Saved scenarios contain only the focused ship, and do not preserve the original scenario's other objects or module state.

NASA's global Earth image is a temporary background asset. It does not replace the high-resolution terrain/elevation system. Solar lighting uses a fixed initial direction in this milestone. No gameplay or visual equivalence to the full Windows version is claimed.

## Next engineering milestones

1. Isolate SDK math/types from Windows declarations, then bring the full body/vessel integrator into the native target behind a platform abstraction.
2. Port the Delta-glider module and cockpit interactions; replace simplified control/assist dynamics with the original vessel and thruster code.
3. Add native celestial-body modules, moving bodies, atmosphere, terrain streaming and surface flight.
4. Bring up stations, docking, Lua/MFD support and additional ships; define a native plug-in ABI and rebuild compatible add-ons.
5. Expand regression scenarios and profile full flights on base Apple Silicon hardware as well as this development Mac.

The top-level CMake file selects `Native/` only on Apple platforms; the original Windows build graph remains otherwise intact. `Native/` code has not been validated as a full replacement for that graph. See `Assets/CREDITS.txt` for Earth imagery credit and the original source notices for licensing.
