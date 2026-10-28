![Orbiter logo](./Src/Orbiter/Bitmaps/banner.png)

# Orbiter for Apple Silicon

An experimental native macOS port of [Orbiter Space Flight Simulator](https://github.com/orbitersim/orbiter), starting with a playable single-spacecraft Delta-glider flight. The application uses Cocoa and Metal with an arm64 flight library.

This is an early port. It reuses Orbiter's orbital mathematics and original spacecraft assets while replacing Windows-dependent application and rendering code. The full original simulator, vessel engine and add-on ecosystem are still being ported.

## Build and fly

Requires **Apple Silicon, macOS 13 or newer, Xcode command-line tools, and CMake 3.19 or newer**. The native target fetches no dependencies and links Apple system frameworks.

```sh
git clone https://github.com/qrobin/orbiter-apple-silicon.git
cd orbiter-apple-silicon
./Native/build.sh --run
```

The script builds `build/macos-arm64/Native/Orbiter Native.app`, runs the native tests and applies a local ad-hoc signature. Developer ID signing and notarization are not yet provided.

Start with **M** for the glider systems panel, **V** for the original 3D cockpit, **+ / −** for main throttle, **X** to cut engines, **Space** to pause, and **T / Y** to change time acceleration. **F1** shows the controls. The **Flight** menu includes a mechanism demonstration.

See the [native guide](Native/README.md) for all controls, supported scenarios, capture options and implementation details.

## Native Metal implementation

- Earth-orbit flight with original Kepler propagation, maneuvering, RCS, finite-torque attitude assists, fuel use and native scenario persistence.
- Original Delta-glider exterior and cockpit meshes, 63 original animation components, staged deployment, 32 cockpit click regions, animated switches and the original hover controls/readouts.
- Hover attitude stabilization, altitude and vertical-speed hold adapted from the original controllers, with physical engine mixing, fuel use, limits, emergency cutoff and live cockpit readouts.
- Main, retro and hover propulsion; gimbals and balance; landing gear, nose, ladder, airlocks, hatch, radiator, airbrake, control surfaces and lights.
- A partial Cape Canaveral base with 10 original landing pads, 123 block buildings, two native runway surfaces at their original coordinates, and original tarmac geometry/textures. Local ground cover is approximate; custom base objects, lights and building collisions remain unported.
- Live native surface/orbit/propulsion displays, cabin and airlock pressure, a reduced thermal model, and original atmosphere/airfoil data with reduced native aerodynamic coupling.
- Experimental ground-physics core: original touchdown geometry, suspension, wheel friction, braking, steering, hover liftoff, soft/hard contact and geographic landed-scenario loading. Interactive wheel/parking brakes, hover throttle keys, a surface start and native surface instruments are connected. Ground handling remains experimental.

The native target currently supports one focused standard `DeltaGlider` at Earth. Other ships and stations, docking, terrain and complete bases, complete MFDs and analog instruments, full damage/coolant models, DG-S scramjets, sound, scripting and Windows plug-ins are incomplete or unavailable. The [native guide](Native/README.md#implementation-boundary) describes these limits.

## Validation and CI

The flight, glider, surface, hover, exhaust and camera CTest suites pass locally in Release and with AddressSanitizer/UndefinedBehaviorSanitizer. They cover orbital propagation, fuel and propulsion, mechanism staging, cockpit/mesh geometry, scenario round trips ground-contact behavior and closed-loop hover recovery/target tracking. These checks do not establish full equivalence with the original simulator.

The [Apple Silicon workflow](.github/workflows/native-macos.yml) builds the arm64 app, runs all native suites, verifies the executable architecture and uploads a ZIP artifact. The imported Windows/Linux maintenance workflows are available as manual workflows.

## Source and licensing

The `Native/` directory contains the macOS application, Metal shaders, native flight layer and tests. The original source and assets remain in the repository, with small portability changes to the reused core. See the [upstream README](README.upstream.md) and [Windows build guide](COMPILE.md) for the original platform.

Orbiter is licensed under [MIT](LICENSE). The included D3D9Client retains its [LGPL license](OVP/D3D9Client/LGPL.txt) and is not part of the native Metal target. Original source notices are retained. NASA Earth imagery is credited in [Native/Assets/CREDITS.txt](Native/Assets/CREDITS.txt).
