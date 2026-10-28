# Product

<!-- impeccable:product-schema 1 -->

## Platform
Native macOS desktop (Apple Silicon).

## Users
The user wants to fly Orbiter on an Apple Silicon Mac. They explicitly selected a basic flight with one spacecraft as the first playable milestone, followed by expanded compatibility.

## Product Purpose
Port the supplied Orbiter source to run natively and smoothly on Apple Silicon. Preserve its orbital simulation, spacecraft assets, and scenario data where feasible.

## Capabilities and Constraints
The native target supports a Delta-glider in Earth orbit and experimental ground flight, with its mechanisms, engines, cockpit controls, pressure and reduced thermal systems. Surface flight includes hover attitude and altitude/vertical-speed controllers, brakes, suspension, surface instruments and a subset of the original Cape Canaveral base. Full vessel-module, cockpit, atmospheric flight-model equivalence, terrain, multi-body and add-on compatibility remain later work. Native ARM64 machine code and Metal rendering are required. A Windows compatibility layer would not satisfy the request.

## Evidence on Hand
Original source, meshes, DDS textures, scenarios, and MIT license are included. NASA Blue Marble imagery supplies the initial Earth surface map because the download lacks Orbiter's Earth terrain textures.

## Product Principles
- Preserve upstream algorithms and assets where they can be isolated cleanly.
- Keep simulation state in double precision.
- Measure frame pacing and rendering cost on the real device.
- Describe incomplete compatibility explicitly.
