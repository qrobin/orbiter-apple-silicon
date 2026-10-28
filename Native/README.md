# Orbiter Native 0.8.2 — original TransX and 2D panel

A partial native Apple Silicon port of the supplied Orbiter source. It includes the original TransX module, Solar System catalogue, cockpit and 2D panel, hover controls, Earth clouds and GPU exhaust. This remains an experimental native flight target, **not a complete port of Orbiter or every Delta-glider subsystem**.

## TransX

Press **F4** (or **Fn-F4** when macOS uses the function key for a system action), or choose **Navigation → TransX…**. The module is compiled directly from `Src/Plugin/TransX`: its stage handling, orbit and encounter calculations, escape/encounter/slingshot plans, original plots, variable controls, help and serialization are reused. The previous custom transfer-planner interface and its Lambert implementation have been removed.

The native window exposes the original twelve MFD actions with readable labels and tooltips. **Left MFD / Right MFD** keeps the two original view states separate. The variable menu jumps to an existing TransX variable; **Enter value** and **Apply value** use its original entry/validation path. Numeric expressions such as `100+`, `100-` and `x` retain their TransX meaning. Native entry also accepts literal zero and legal planet/moon names for the current stage. In the display, H/F/R/W, period/comma, brackets, =/−, X/E invoke the original MFD keys after clicking the display. **Return to flight** restores normal flight keyboard control.

For the usual interplanetary setup, select **Select Target → Escape** in the departure stage, then **Next stage** to reach its parent system. Select **Mars**, for example, in the Sun stage. Tune the original plan variables and change views as in TransX. **Navigation → TransX Quickstart…** opens the included original guide. This port does not supply an automatic mission or execute engine burns.

**Navigation → TransX on Left/Right MFD** selects its cockpit displays. The Delta-glider’s original twelve side buttons on each display are clickable; their labels use the original `dg_vc4.dds` glyph atlas and their hit areas/spacing come from `MfdSubsys.cpp`. Hold Increase/Decrease for continuous changes. The native window is also available while flying externally.

Drag an orbit graph in the TransX window or directly on a cockpit or 2D-panel MFD to rotate its 3D projection. Double-click the graph or choose **Reset graph** in the TransX window to return to the original projection. Each MFD keeps its own viewpoint. Target-view steering cues and the planned orbit are unchanged.

Optional **Align with RCS** points at the same vector used by the original TransX Target view for a configured manoeuvre in the current gravity reference. It uses the glider’s finite RCS torque and fuel. Main, hover and retro engine levels remain under player control. **N** releases attitude assist. Planning through an escape stage alone does not create an active manoeuvre vector: configure the original **Manoeuvre mode**, velocity components and date first. A disabled alignment button means no applicable manoeuvre is available.

Normal scenario saves include the original TransX status in a `TYPE TransX` MFD block. Opening the scenario restores it. New body/scenario starts reset the plan, while switching left/right views retains their separate view selection. The native host still supports one Delta-glider; general multi-vessel targeting, docking stacks, surface-base targets and other MFD/vessel modules are not ported. Flight uses the existing patched-conic simulation described below.

Portability changes to TransX are limited to native host API bindings, drawing commands, header guards, native input handling, a return-value correction and a stable basis for perfectly circular native starts. Its navigation model and plan workflow remain upstream implementations. Author credits and the MIT/X11 license are included in the app.

## Solar System in 0.7

Choose **Solar System → a planet → its Orbit or a moon's Orbit**. This starts a new orbit around that body at the current simulation date. **R** restarts the selected orbit. **Flight → Earth Orbit** and the Cape starts return to the original Earth scenarios.

The catalogue has **33 bodies**: Sun, eight planets, Vesta and 23 moons.

| Parent | Moons |
| --- | --- |
| Earth | Moon |
| Mars | Phobos, Deimos |
| Jupiter | Io, Europa, Ganymede, Callisto |
| Saturn | Mimas, Enceladus, Tethys, Dione, Rhea, Titan, Hyperion, Iapetus |
| Uranus | Miranda, Ariel, Umbriel, Titania, Oberon |
| Neptune | Triton, Proteus, Nereid |

Each body has its original configured mass/radius, rotating surface frame and body-specific gravity. Orbital instruments subtract the active body's radius; low-altitude surface instruments scale their threshold to the body's size. Gas giants have no solid landing surface. The reference switches automatically at sphere-of-influence boundaries, preserving heliocentric position and velocity. This is a **patched-conic** flight model: spacecraft acceleration uses the active central body, rather than summing all bodies' gravity/tidal forces.

The native ephemeris adapters use the bundled **VSOP87B** series for planets, **ELP82** for the Moon, **GALSAT/Lieske** for Jupiter's four large moons and **TASS17** for Saturn's eight moons. The remaining satellites and Vesta use the original configured mean Kepler elements. Positions/velocities are reconstructed through 60-second Hermite samples. Axial precession is frozen at the catalogue's mean J2000 orientation.

The renderer shows the other bodies at their current positions and angular sizes, with sunlit phases and Saturn's rings. The Sun direction follows the spacecraft's heliocentric position. Sun, planets and the Moon have credited 2K maps (Earth retains its NASA 8K map). Other moons and Vesta have procedural surface materials; their generated markings are approximations. Surfaces remain mean spheres without local terrain relief. Very distant bodies can be below a pixel in size.

Earth alone has the existing weather/cloud presets. Airless bodies have vacuum, and other atmospheres use a reduced hydrostatic isothermal model based on their configured pressure, density and gravity; they do not reuse Earth's atmospheric profile. The existing glider aerodynamics remain a reduced model. The spherical touchdown solver and hover controls use the active body's gravity and surface rotation. Cape scenery is drawn only at Earth.

Native scenarios can save/load supported body references in `STATUS Orbiting <body>` and `STATUS Landed <solid body>`. Other vessels and stations in the file are still not instantiated.

For a bounded render check, add `--body Moon`, `--body Mars`, `--body Jupiter` or another catalogue name. `--look-at Jupiter` or `--look-at Saturn` sets an initial camera direction for reviewing a parent planet from a moon. Native drag/scroll controls remain available in interactive flight.

## Native graphics in 0.6

The application now renders the 8K NASA Earth map, volumetric clouds, cloud shadows and exhaust directly in Metal. Choose **Weather → Clear / Scattered / Overcast / Storm**, or **F3** to cycle. Function keys may require Fn on Mac keyboards. These presets control procedural cloud coverage, density and layer height; they are not live weather and do not change the aerodynamic forces.

Clouds occupy a spherical layer above Earth. A GPU-generated 128³ Perlin/Worley noise volume shapes the density, sunlight is attenuated through the volume, and a forward-scattering phase approximation produces bright edges. A screen-space cloud shadow pass follows the actual visible ground. The cloud pass uses 48 primary samples and four sun samples, up to 760 pixels wide (no more than half output resolution), temporal reprojection and depth-aware reconstruction. Spacecraft geometry, cockpit instruments and HUD remain at full output resolution. Camera cuts, resize, scenario changes and weather changes invalidate the history.

Main, retro, hover and RCS effects use the tested shared nozzle/command data. Instanced 3D blue-white flame cores follow the craft and gimbals. A 4096-slot GPU particle pool emits and advects exhaust in the inertial frame, retaining the spacecraft's velocity at emission and responding to gravity. Pressure changes the visible spread. Soft depth intersections, local cloud attenuation, FP16 scene rendering, bloom and tone mapping integrate the exhaust into the view. The flame and particle appearance is an approximation, not a fluid/combustion simulation.

The native camera sensitivity, flight controls, original cockpit, glider systems and Cape scenery remain available. The solar direction now follows the heliocentric spacecraft position. Global imagery is not detailed local terrain; the Cape ground cover remains approximate.

## Try it

Open `Orbiter Native.app`. Press **M** for the native systems panel, or use **Flight → Glider Systems**. The panel provides deployment buttons, engine sliders, gimbals, engine balance, elevator trim, RCS mode, cabin/airlock valves, cooling and light switches.

Choose **Flight → Mechanism Demonstration** to watch gear, nose, retro covers, airbrakes, radiator and escape ladder deploy with the original staged animation timing at 10× simulation time. The ladder waits for the nose cone to finish opening. Press **R** to return to the normal orbital scenario.

Press **V** to cycle through external view, the original 3D cockpit and the original 2D instrument-panel view. The **Flight** menu also selects each view. In the 3D cockpit, drag to look around and scroll to zoom. The pilot body, head and visor are hidden from the pilot's camera. Thirty-two original click regions (30 quadrilaterals and two spherical buttons) operate supported switches, gear/nose/airbrake levers, main and hover throttles, RCS selector, trim and gimbal controls. Sixteen switch handles rotate about their original pivots; the original main/hover throttle, gear and nose lever animations are connected. The original hover dial, spring switches, hold/mode buttons, balance pointers and small numeric hover readout are also connected. Click-and-drag the main or hover throttle to adjust it. **M** provides larger accessible controls for the same systems.

The 2D view uses the original `dg_panel.dds` main-panel artwork and original MFD/button positions. Both displays mirror their cockpit counterparts; their TransX buttons and graph dragging work in either view. Main/retro and hover throttles, gear, nose, airbrake, trim, RCS mode, hover attitude and hover hold are connected. The main levers control both engines together in the native flight model. The attitude and heading underlays show live flight data; other original panel instruments and switches are not all connected yet.

The cockpit has live native surface/orbit and propulsion displays on the original MFD meshes. These are new native displays, not the full Orbiter MFD implementation. Original analog instruments and other cockpit buttons are not all connected.

Choose **Flight → Cape Canaveral — Surface Flight** to start parked at the original scenario location with low fuel, gear deployed, RCS off and parking brake set. **Shift-W** releases the parking brake; hold **,** and **.** for left/right wheel brakes. Use **[ / ]** to lower/raise hover throttle. **M** has the equivalent parking-brake switch and hover slider. Around 95% hover thrust lifts this light configuration; keep the gear down while learning. Automatic hover attitude is enabled in this starting scenario. Use **M** to select Off / Auto / Manual attitude modes and altitude / vertical speed hold.

The HUD and left cockpit display automatically show surface altitude, ground-relative speed, vertical speed, heading, pitch and bank below 120 km. The external orbit diagram becomes a surface attitude indicator. Select **Flight → Earth Orbit** to return to the orbital starting scenario. **R** restarts the scenario most recently selected or opened.

## Hover practice

Choose **Flight → Cape Canaveral — Hover Practice** for a low-fuel launch that automatically climbs to 100 m and holds altitude. It uses the same engine forces and propellant budget as manual flight; it is not a scripted animation. The controllers do not hold horizontal position or heading, so some drift is expected.

- **F5** toggles automatic hover attitude. In Auto mode, pitch/roll keys request up to 10° tilt; releasing them requests level flight. RCS translation mode keeps those keys assigned to translation instead. Manual mode holds the pitch/bank targets set in the systems panel or original cockpit switches.
- **F6** engages altitude hold at the current altitude, or disengages an existing altitude hold. **F7** similarly toggles zero vertical speed hold. The Flight menu provides the same actions. On Mac keyboards, function keys may require Fn.
- **M** exposes numeric altitude/vertical-speed targets, manual attitude targets, capture/reset buttons, engagement state, and actual front/rear-left/rear-right engine levels. Press Return to commit an edited numeric target.
- The original hover dial selects Off / Auto / Manual. Its pitch/bank switches adjust manual attitude targets; the horizontal hold-target switch adjusts the selected hold target. The mode buttons select altitude or vertical speed, the round hold button engages/disengages, and the small reset button captures current altitude or requests zero vertical speed.
- **[ / ]**, the hover slider and the cockpit hover lever disengage automatic hold when used. **X** cancels hold and cuts all engines immediately. Disengaging hold alone retains the current throttle.

Engaging hold enables Auto attitude if attitude control was off. Hold is available below 120 km with main propellant remaining; altitude targets are 0–120,000 m and interactive vertical-speed targets are −20 to +20 m/s. The original ±30° pitch/bank envelope is retained. Outside that envelope, differential stabilization is suspended and a warning is shown; manual recovery is required. Full thrust or insufficient thrust-to-weight can prevent a target from being reached. Fuel exhaustion disengages hold. Ground contact still uses the experimental spherical-surface model.

The native attitude mixer and vertical controllers adapt the original `HoverSubsys.cpp` and `Vessel::HoverHoldAltitude` algorithms, including the original gains, weighted thrust balancing, 20 m/s altitude-loop speed limit and throttle slew limit. Torque signs are adapted to the native coordinate convention. Derivative feedback is reset when engaging/loading and uses the actual preceding physics step duration. These adaptations are tested in the reduced native flight model; they do not establish full original flight-model equivalence.

The right cockpit MFD displays hover state while hover controls are enabled. The original small hover target display uses its original digit atlas and mode/engagement graphics; the two original balance pointers show commanded and actual pitch/bank.

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
| Hover engines | Three independent engine levels, original thrust distribution and manual fore/aft balance; real force, torque and propellant use |
| Hover controls | Automatic/manual attitude targets; altitude and vertical-speed hold; limits, manual override, original cockpit controls/readouts and scenario persistence |
| RCS | Six-axis translation and three-axis rotation, original torque magnitudes and normalized moments of inertia, fuel-limited jets, off/rotation/translation modes |
| Attitude assists | Original six RCS programs, finite torque and fuel use at normal speed; prograde and retrograde put the planet on the left and right respectively. Nav programs can operate with the manual RCS dial off. |
| HUD | Orbit, surface and docking selection, brightness and four colours from cockpit controls or the Navigation menu; docking displays no target until docking targets are supported |
| Effects and lights | Throttle-linked main/retro/hover exhaust, RCS jets, navigation lights, flashing red beacons, white strobes and docking-light marker |
| Atmosphere/aerodynamics | Original Earth 2006 atmosphere equations, original DG vertical/horizontal lift tables, induced/wave drag; a reduced native force/moment coupling below 120 km |
| State persistence | Mechanism positions and motion targets, main/hover/retro settings, gimbals/balance, trim, RCS mode, pressures/valves, temperatures, pump, lights, attitude and angular rates |

The native animation registry contains **63 components extracted from upstream source**. It retains original mesh group indices, pivots, axes, angles, neutral states, stage intervals and deployment rates. The landing-gear mesh is defined in the deployed state upstream; the native renderer applies the proper inverse transformations when the gear is retracted.

## Controls

| Control | Action |
| --- | --- |
| M | Open glider systems panel |
| F3 | Cycle visual cloud/weather presets |
| F4 / Cmd-Shift-T | Open original TransX MFD controls |
| F5 | Toggle automatic hover attitude |
| F6 | Toggle altitude hold at current height |
| F7 | Toggle zero vertical speed hold |
| [ / ] | Decrease / increase hover throttle |
| , / . | Hold left / right wheel brake; hold both to stop |
| Shift-W | Toggle parking brake |
| V | Cycle external / 3D cockpit / 2D instrument panel |
| Drag / scroll | Orbit external camera or look around cockpit; scroll to zoom |
| Drag / double-click TransX graph | Rotate its projection / reset it |
| + / − or keypad + / − | Increase / decrease main throttle |
| X | Cut main, hover and retro engines |
| Arrow keys | Pitch/yaw in RCS rotation mode; vertical/lateral jets in translation mode |
| Q / E | Roll in rotation mode |
| W / S | Forward / backward RCS translation |
| A / D | Left / right RCS translation |
| Z / J | Up / down RCS translation |
| P / O | Prograde / retrograde assist |
| ; / ' | Normal / anti-normal assist |
| Shift-L | Horizon-level assist |
| K / N | Kill rotation / manual attitude |
| Ctrl-H / Option-H | Cycle HUD mode / colour |
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
| R | Restart the current scenario |
| F1 | Show controls |
| F2 | Show / hide external orbit or surface attitude diagram |
| ⌘O / ⌘S | Open / save scenario |
| ⌘Q | Quit |

Mechanisms follow simulation time and stop while paused. Manual maneuvers, engine use, angular motion and atmospheric flight return acceleration to 1×. At high time acceleration an unpowered prograde/retrograde assist uses a kinematic alignment path. Opening the top hatch or opening both airlocks can depressurize the cabin; closing doors and opening the supply valves restores pressure. A warning appears when pressure is low or retro thrust is inhibited.

The native panel is a separate macOS window. Click the flight window to return keyboard control to the spacecraft after using panel controls.

## Build

Requires Apple Silicon, macOS 13+, Xcode command-line tools and CMake 3.19+. The native build fetches no dependencies and links only Apple system frameworks/libraries.

```sh
./Native/build.sh --run
```

Result: `build/macos-arm64/Native/Orbiter Native.app`. Set `ORBITER_NATIVE_BUILD_DIR` for another directory. The build runs the native flight, glider, surface, hover, exhaust, camera, Solar System and original TransX test suites and applies a local ad-hoc signature. Public notarization is not provided.

For a bounded rendering run:

```sh
"build/macos-arm64/Native/Orbiter Native.app/Contents/MacOS/Orbiter Native" \
  --frames 600 --prograde --glider-demo \
  --capture /absolute/path/frame.png --report /absolute/path/performance.json
```

Use `--hover-demo` for a repeatable hover capture (the practice flight advances 60 simulation seconds before rendering), `--surface` for the bundled parked Cape start, `--cockpit` for the 3D cockpit, `--panel2d` for the 2D panel, and `--scenario /absolute/path/file.scn` for a supported scenario. `--glider-demo` starts with selected mechanisms deployed for a repeatable render capture; the menu demonstration runs their actual transitions. Bounded frame runs ignore manual keyboard/camera input.

Animation and cockpit geometry data can be regenerated from the included upstream sources with:

```sh
python3 Native/tools/extract_glider_animations.py
python3 Native/tools/extract_base_geometry.py
```

The generated `.inc` files are committed, so Python is not a build dependency.

Additional bounded render options: `--weather 0` through `--weather 3`, `--throttle .8`, `--rcs-demo`, `--camera-yaw -30`, `--camera-pitch 45`, and `--camera-distance 60` (angles in degrees, distance in metres). `--altitude 3500 --paused` places a stationary render-review state at the current latitude/longitude inside the cloud layer. It is a visual test setup, not a flying autopilot.

## Ground physics and Cape Canaveral

The native flight includes a tested ground-contact core using the original Delta-glider touchdown geometry: spring/damper suspension, wheel friction, independent rear brakes, parking brake, nose-wheel steering, gentle landing, hard-impact detection and hover liftoff. Geographic `STATUS Landed Earth` scenarios such as `Scenarios/Delta-glider/Cape Canaveral.scn` can be loaded through Open Scenario or `--scenario`.

The original `Canaveral.cfg` supplies its geographic anchor, 10 landing-pad placements, 123 block buildings, two runway layouts and the visitor-area tarmac mesh. Landing pads retain the original geometry, numbered texture atlas, scale and rotation. Building wall/roof textures are original. The runways use native surfaces and markings at the original endpoints; they do not implement the full original runway-segment renderer or lights. Draw calls are batched by material/texture, and the geometry follows Earth curvature and rotation.

The supplied archive lacks local Earth terrain tiles. A native textured ground patch gives the Cape subset a visible surface; it is an approximation, not Florida coastline or elevation data. The Earth pass writes depth to hide geometry below the horizon, and the external camera stays above the ground. Forty unsupported base objects are omitted, including custom launch-complex meshes and hangars; base buildings currently provide visual scenery only, with no building collision response.

The physics surface is a smooth sphere at the mean Earth radius. Ground handling remains experimental, without terrain elevations or full original takeoff/landing equivalence.

## Implementation boundary

Original `Element.cpp`, `Vecmat.cpp`, `Astro.cpp` and `TimeData.cpp` are compiled into the native library with small portability changes. The native single-vessel flight layer uses original Kepler propagation for unpowered vacuum coasting and RK4 for maneuvering/atmospheric flight. The full original `Vessel`/`BodyIntegrator` engine is not compiled into this target.

Pressure uses a continuous solution to the original cabin/airlock volume and conductance equations (24 m³ cabin, 4 m³ airlock). Cooling is a new reduced energy-storage/radiator model; it is **not** the original multi-node thermal/coolant simulation. The atmospheric equations and airfoil coefficients are original, but the native force/moment application is reduced and has not been validated for full flight-model equivalence.

Still incomplete:

- Full native vessel/body engine, SPICE modules, simultaneous multi-body perturbations, terrain, complete bases and validated atmospheric flight-model equivalence. Ground contact currently uses an experimental spherical-surface model; hard impacts stop the flight.
- Full DG damage/failure model, complete coolant circuit, atmospheric ascent/landing autopilots, original analog instruments, all cockpit buttons and complete MFD modes.
- Docking/undocking mechanics, other ships and stations. The animated nose exposes the port, but docking requires the unported multi-vessel infrastructure.
- DG-S scramjet systems (a separate variant), original sound, Lua scripting and Windows DLL plug-ins.

Scenarios focused on a standard `DeltaGlider` at a catalogue body are accepted; landed scenario support is experimental. Other objects in those scenarios are not instantiated; native saves contain the focused vessel only, with native extension fields for its additional controls. No full-simulator equivalence is claimed.

NASA's credited global Earth image is a visual backdrop, not the high-resolution terrain/elevation system. Solar direction follows the heliocentric spacecraft position. Display settings are not changed; presentation rate follows the active refresh mode.

See `Assets/CREDITS.txt`, the bundled MIT license and original source notices.
