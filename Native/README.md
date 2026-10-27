# Orbiter Native 0.2 — Delta-glider systems

A partial native Apple Silicon port of the supplied Orbiter source. Version 0.2 adds standard Delta-glider mechanisms, propulsion and cockpit interaction to the original native Earth-orbit flight milestone. This remains an experimental native flight target, **not a complete port of Orbiter or every Delta-glider subsystem**.

## Try it

Open `Orbiter Native.app`. Press **M** for the native systems panel, or use **Flight → Glider Systems**. The panel provides deployment buttons, engine sliders, gimbals, engine balance, elevator trim, RCS mode, cabin/airlock valves, cooling and light switches.

Choose **Flight → Mechanism Demonstration** to watch gear, nose, retro covers, airbrakes, radiator and escape ladder deploy with the original staged animation timing at 10× simulation time. The ladder waits for the nose cone to finish opening. Press **R** to return to the normal orbital scenario.

Press **V** to enter the original 3D cockpit. Drag to look around. Twenty-five original click regions operate supported switches, gear/nose/airbrake levers, main and hover throttles, RCS selector, trim and gimbal controls. Sixteen switch handles rotate about their original pivots; the original main/hover throttle, gear and nose lever animations are connected. Click-and-drag the main or hover throttle to adjust it. **M** provides larger accessible controls for the same systems.

The cockpit has live native orbit and propulsion displays on the original MFD meshes. These are new native displays, not the full Orbiter MFD implementation. Original analog instruments and other cockpit buttons are not all connected.

## Implemented systems

| System | Native behavior |
| --- | --- |
| Landing gear | Original staged strut and door motion; 6.67 s deployment, reversible in motion |
| Nose and escape ladder | Four nose panels and docking-port translation; ladder extension requires the nose fully open; closing the nose retracts the ladder |
| Airlocks and hatch | Outer and inner doors, top hatch and rear ladder; cabin and airlock pressure respond to openings and five supply/vent/equalization valves |
| Radiator | Original nine-component unfolding sequence, taking 50 s; deployment and coolant pump affect a reduced thermal model |
| Retro covers | Four animated covers; retro thrust is inhibited until fully open and is disabled immediately on a close command |
| Airbrake and flight surfaces | Original flap/rudder airbrake transforms, half/full deployment, elevator, trim, rudder and aileron deflection |
| Main engines | Original two 200 kN easy-model engines, independent L/R balance, 5° pitch gimbal and original yaw range; off-axis forces create torque |
| Retro engines | Original two 34 kN engines with original slightly tilted thrust vectors and mounting points |
| Hover engines | Original three-engine thrust distribution and fore/aft balance; real force, torque and propellant use |
| RCS | Six-axis translation and three-axis rotation, original torque magnitudes and normalized moments of inertia, fuel-limited jets, off/rotation/translation modes |
| Attitude assists | Finite-torque prograde, retrograde and kill-rotation control at normal speed; RCS supply and mode affect operation |
| Effects and lights | Throttle-linked main/retro/hover exhaust, RCS jets, navigation lights, flashing red beacons, white strobes and docking-light marker |
| Atmosphere/aerodynamics | Original Earth 2006 atmosphere equations, original DG vertical/horizontal lift tables, induced/wave drag; a reduced native force/moment coupling below 120 km |
| State persistence | Mechanism positions and motion targets, main/hover/retro settings, gimbals/balance, trim, RCS mode, pressures/valves, temperatures, pump, lights, attitude and angular rates |

The native animation registry contains **63 components extracted from upstream source**. It retains original mesh group indices, pivots, axes, angles, neutral states, stage intervals and deployment rates. The landing-gear mesh is defined in the deployed state upstream; the native renderer applies the proper inverse transformations when the gear is retracted.

## Controls

| Control | Action |
| --- | --- |
| M | Open glider systems panel |
| V | External view / virtual cockpit |
| Drag / scroll | Orbit external camera / zoom; drag in cockpit to look around |
| + / − or keypad + / − | Increase / decrease main throttle |
| X | Cut main, hover and retro engines |
| Arrow keys | Pitch/yaw in RCS rotation mode; vertical/lateral jets in translation mode |
| Q / E | Roll in rotation mode |
| W / S | Forward / backward RCS translation |
| A / D | Left / right RCS translation |
| Z / J | Up / down RCS translation |
| P / O | Prograde / retrograde assist |
| K / N | Kill rotation / manual attitude |
| G | Toggle landing gear |
| C | Toggle nose cone |
| L | Toggle escape ladder |
| U | Toggle retro covers |
| B / Shift-B | Extend / retract airbrake by one half-step |
| F | Toggle radiator |
| H | Toggle top hatch |
| I / Shift-I | Toggle outer / inner airlock |
| T / Y | Increase / decrease time acceleration |
| Space | Pause / resume |
| R | Restart supplied orbital flight |
| F1 | Show controls |
| F2 | Show / hide external orbit diagram |
| ⌘O / ⌘S | Open / save scenario |
| ⌘Q | Quit |

Mechanisms follow simulation time and stop while paused. Manual maneuvers, engine use, angular motion and atmospheric flight return acceleration to 1×. At high time acceleration an unpowered prograde/retrograde assist uses a kinematic alignment path. Opening the top hatch or opening both airlocks can depressurize the cabin; closing doors and opening the supply valves restores pressure. A warning appears when pressure is low or retro thrust is inhibited.

The native panel is a separate macOS window. Click the flight window to return keyboard control to the spacecraft after using panel controls.

## Build

Requires Apple Silicon, macOS 13+, Xcode command-line tools and CMake 3.19+. The native build fetches no dependencies and links only Apple system frameworks/libraries.

```sh
./Native/build.sh --run
```

Result: `build/macos-arm64/Native/Orbiter Native.app`. Set `ORBITER_NATIVE_BUILD_DIR` for another directory. The build runs the native flight and glider test suites and applies a local ad-hoc signature. Public notarization is not provided.

For a bounded rendering run:

```sh
"build/macos-arm64/Native/Orbiter Native.app/Contents/MacOS/Orbiter Native" \
  --frames 600 --prograde --glider-demo \
  --capture /absolute/path/frame.png --report /absolute/path/performance.json
```

Use `--cockpit` for the 3D cockpit, `--scenario /absolute/path/file.scn` for a supported scenario. `--glider-demo` starts with selected mechanisms deployed for a repeatable render capture; the menu demonstration runs their actual transitions. Bounded frame runs ignore manual keyboard/camera input.

Animation and cockpit geometry data can be regenerated from the included upstream sources with:

```sh
python3 Native/tools/extract_glider_animations.py
```

The generated `.inc` files are committed, so Python is not a build dependency.

## Implementation boundary

Original `Element.cpp`, `Vecmat.cpp`, `Astro.cpp` and `TimeData.cpp` are compiled into the native library with small portability changes. The native single-vessel flight layer uses original Kepler propagation for unpowered vacuum coasting and RK4 for maneuvering/atmospheric flight. The full original `Vessel`/`BodyIntegrator` engine is not compiled into this target.

Pressure uses a continuous solution to the original cabin/airlock volume and conductance equations (24 m³ cabin, 4 m³ airlock). Cooling is a new reduced energy-storage/radiator model; it is **not** the original multi-node thermal/coolant simulation. The atmospheric equations and airfoil coefficients are original, but the native force/moment application is reduced and has not been validated for full flight-model equivalence.

Still incomplete:

- Full native vessel/body engine, moving solar-system bodies, SPICE modules, perturbations, terrain, bases, surface collision response, wheel braking and takeoff/landing scenarios. Surface contact currently stops the flight.
- Full DG damage/failure model, complete coolant circuit, hover altitude/attitude hold and atmospheric autopilots, original analog instruments, all cockpit buttons and complete MFD modes.
- Docking/undocking mechanics, other ships and stations. The animated nose exposes the port, but docking requires the unported multi-vessel infrastructure.
- DG-S scramjet systems (a separate variant), original sound, Lua scripting and Windows DLL plug-ins.

Only Earth-orbit scenarios focused on a `DeltaGlider` are accepted. Other objects in those scenarios are not instantiated; native saves contain the focused vessel only, with native extension fields for its additional controls. No full-simulator equivalence is claimed.

NASA's credited global Earth image is a visual backdrop, not the high-resolution terrain/elevation system. Solar direction is fixed for this milestone. Display settings are not changed; presentation rate follows the active refresh mode.

See `Assets/CREDITS.txt`, the bundled MIT license and original source notices.
