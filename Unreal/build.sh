#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
ue_root="${ORBITER_UE_ROOT:-/Users/Shared/Epic Games/UE_5.8}"
cmake -S "$root" -B "$root/build/unreal-arm64" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build "$root/build/unreal-arm64" --target OrbiterFlightCore --parallel 8
cmake -P "$root/Native/PackageAssets.cmake" -- "$root" "$root/Unreal/Content/OrbiterData"
bash "$ue_root/Engine/Build/BatchFiles/Mac/Build.sh" OrbiterUEEditor Mac Development "-Project=$root/Unreal/OrbiterUE.uproject" -architecture=arm64 -WaitMutex -NoHotReload

"$ue_root/Engine/Binaries/Mac/UnrealEditor-Cmd" "$root/Unreal/OrbiterUE.uproject" -run=pythonscript -script="$root/Unreal/Tools/build_assets.py" -unattended -NullRHI -stdout
if [[ "${1:-}" == "--test" ]]; then
  "$ue_root/Engine/Binaries/Mac/UnrealEditor-Cmd" "$root/Unreal/OrbiterUE.uproject" -unattended -NullRHI -NoSound -stdout -ExecCmds="Automation RunTests Orbiter.NativeBridge" -TestExit="Automation Test Queue Empty"
fi
