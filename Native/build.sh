#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${ORBITER_NATIVE_BUILD_DIR:-$root/build/macos-arm64}"
cmake -S "$root" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
cmake --build "$build_dir" --parallel "$(sysctl -n hw.logicalcpu)"
ctest --test-dir "$build_dir" --output-on-failure
app_path="$build_dir/Native/Orbiter Native.app"
codesign --force --sign - "$app_path"
printf '\nBuilt: %s\n' "$app_path"
if [[ "${1:-}" == "--run" ]]; then open "$app_path"; fi
