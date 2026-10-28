#!/bin/bash
# Build a self-contained local arm64 game with UE 5.8.2.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
ue_root="${ORBITER_UE_ROOT:-/Users/Shared/Epic Games/UE_5.8}"
archive="${1:-$root/../Orbiter-Unreal-Apple-Silicon}"
log_dir="$root/Unreal/Saved/Packaging"
mkdir -p "$log_dir"
"$root/Unreal/build.sh" > "$log_dir/editor-and-assets.log" 2>&1
uat="$ue_root/Engine/Build/BatchFiles/RunUAT.sh"
args=(BuildCookRun -project="$root/Unreal/OrbiterUE.uproject" -target=OrbiterUE -noP4 -installed
  -platform=Mac -architecture=arm64 -clientconfig=Development -cook -skipbuildeditor
  -nocompileeditor -stage -pak -compressed -package -archive -archivedirectory="$archive" -utf8output)
if "$uat" "${args[@]}" -build > "$log_dir/build.log" 2>&1; then
  tail -8 "$log_dir/build.log"
  exit 0
else
  build_status=$?
fi
# Xcode 27.1 can fail the same pre-action inside UBT while direct finalization
# succeeds. Handle only that failure; compiler/cook/signing errors still stop.
if ! /usr/bin/grep -Fq 'Failed to finalize the .app with Xcode' "$log_dir/build.log"; then
  tail -35 "$log_dir/build.log"
  exit "$build_status"
fi
printf '%s\n' 'Retrying Xcode finalization outside the UBT post-build process.'
UBT_NO_POST_DEPLOY=true xcrun xcodebuild build \
  -workspace "$root/Unreal/Intermediate/ProjectFiles/OrbiterUE_Mac_OrbiterUE.xcworkspace" \
  -scheme OrbiterUE -configuration Development -destination 'generic/platform=macOS' \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES -allowProvisioningUpdates \
  UE_XCODE_BUILD_MODE=PostBuildSync > "$log_dir/finalize.log" 2>&1
# Run Unreal's own metadata writer for the executable just linked and finalized.
"$ue_root/Engine/Binaries/ThirdParty/DotNet/10.0/mac-arm64/dotnet" \
  "$ue_root/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll" \
  -Mode=WriteMetadata -Version=2 \
  -Input="$root/Unreal/Intermediate/Build/Mac/arm64/OrbiterUE/Development/TargetMetadata.json" \
  > "$log_dir/receipt.log" 2>&1
"$uat" "${args[@]}" -skipbuild > "$log_dir/stage.log" 2>&1
tail -8 "$log_dir/stage.log"
