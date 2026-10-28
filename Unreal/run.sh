#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
ue_root="${ORBITER_UE_ROOT:-/Users/Shared/Epic Games/UE_5.8}"
exec "$ue_root/Engine/Binaries/Mac/UnrealEditor" "$root/Unreal/OrbiterUE.uproject" -game -windowed "$@"
