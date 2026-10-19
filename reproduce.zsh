#!/bin/zsh
# Usage: ./reproduce.zsh apple|custom YES|NO
set -euo pipefail
reproducer_root=${0:A:h}
backend=${1:-apple}
cache_enabled=${2:-YES}
case "$backend" in apple|custom) ;; *) print -u2 'Backend must be apple or custom'; exit 64 ;; esac
case "$cache_enabled" in YES|NO) ;; *) print -u2 'Caching must be YES or NO'; exit 64 ;; esac
if (( $# > 2 )); then print -u2 'Usage: reproduce.zsh apple|custom YES|NO '; exit 64; fi
developer_dir=/Applications/Xcode_27.1.app/Contents/Developer
service="$developer_dir/../SharedFrameworks/SwiftBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/MacOS/SWBBuildService"
if [[ "$backend" == custom ]]; then
 service=${CUSTOM_BUILD_SERVICE_PATH:?Set CUSTOM_BUILD_SERVICE_PATH to the custom build-service executable}
fi
[[ -x "$service" ]] || { print -u2 -- "Missing build-service executable: $service"; exit 1; }
mkdir -p "$reproducer_root/.artifacts"
output=$(mktemp -d "$reproducer_root/.artifacts/$backend-$cache_enabled-XXXXXX")
output=${output:A}
mkdir "$output/logs" "$output/work"
work="$output/work"
cp "$reproducer_root/Package.swift" "$work/Package.swift"
cp -R "$reproducer_root/Sources" "$work/Sources"
cp -R "$reproducer_root/FooPackage" "$work/FooPackage"
for relative in Package.swift Sources/Consumer/main.swift FooPackage/Sources/Foo/Foo.swift; do
 cp "$reproducer_root/Fixtures/phase1/$relative" "$work/$relative"
done
print -r -- "Output: $output"
# Clear inherited service selections before selecting the exact executable.
backend_command=(env -u XCBBUILDSERVICE_PATH -u SWBBUILDSERVICE_PATH
 -u SWBBUILDSERVICE_BUNDLE_PATH -u XCBBUILDSERVICE_BUNDLE_PATH
 "XCBBUILDSERVICE_PATH=$service" "DEVELOPER_DIR=$developer_dir")
prefix='$(inherited) "$(DERIVED_DATA_DIR)=/^reproDerivedData"'
prefix="$prefix \"$output=/^reproRepository\""
settings=(
 "COMPILATION_CACHE_ENABLE_CACHING=$cache_enabled"
 "COMPILATION_CACHE_CAS_PATH=$HOME/Library/Developer/Xcode/DerivedData/CompilationCache.noindex"
 SWIFT_ENABLE_PREFIX_MAPPING=YES SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES
 CLANG_ENABLE_PREFIX_MAPPING=YES CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES
 "SWIFT_OTHER_PREFIX_MAPPINGS=$prefix" "CLANG_OTHER_PREFIX_MAPPINGS=$prefix"
 SWIFT_INSTALL_MODULE_FOR_DEPLOYMENT=YES CODE_SIGNING_ALLOWED=NO
)
"$developer_dir/usr/bin/xcodebuild" -version > "$output/logs/xcode-version.txt"
"$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" --version > "$output/logs/swift-version.txt"
python3 - "$service" "$output/logs/backend.json" "$backend" "$cache_enabled" <<'PYBACKEND'
from pathlib import Path
import hashlib, json, sys
p = Path(sys.argv[1]).resolve()
Path(sys.argv[2]).write_text(json.dumps({"backend": sys.argv[3], "cache_enabled": sys.argv[4],
 "service_executable": str(p), "service_sha256": hashlib.sha256(p.read_bytes()).hexdigest()}, indent=2) + "\n")
PYBACKEND
cd "$work"
for phase in 1 2; do
 if [[ "$phase" == 2 ]]; then
  for relative in Package.swift Sources/Consumer/main.swift FooPackage/Sources/Foo/Foo.swift; do
   cp "$reproducer_root/$relative" "$work/$relative"
  done
 fi
 command=("${backend_command[@]}" "$developer_dir/usr/bin/xcodebuild" build
  -scheme ConsumerPackage -configuration Debug -destination 'platform=macOS,arch=arm64'
  -derivedDataPath "$output/DerivedData" -clonedSourcePackagesDirPath "$output/SourcePackages"
  -jobs 3 "${settings[@]}")
 printf '%q ' "${command[@]}" > "$output/logs/phase$phase.command"
 print >> "$output/logs/phase$phase.command"
 set +e
 "${command[@]}" > "$output/logs/phase$phase.log" 2>&1
 result=$?
 set -e
 print "$result" > "$output/logs/phase$phase.exit"
 python3 "$reproducer_root/Tools/snapshot.py" "$work" "$output" "$phase"
 print -r -- "phase=$phase exit=$result log=$output/logs/phase$phase.log"
 if [[ "$phase" == 1 && "$result" != 0 ]]; then exit "$result"; fi
done
# These optional evidence probes do not replace the phase-2 build result.
products="$output/DerivedData/Build/Products/Debug"
sdk="$developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
for mode in root-first framework-only; do
 paths=(-F "$products/PackageFrameworks")
 if [[ "$mode" == root-first ]]; then paths=(-I "$products" "${paths[@]}"); fi
 command=("$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
  -typecheck -swift-version 6 -sdk "$sdk" -target arm64-apple-macos26.0
  "${paths[@]}" "$reproducer_root/Tools/import-probe.swift")
 printf '%q ' "${command[@]}" > "$output/logs/import-$mode.command"
 print >> "$output/logs/import-$mode.command"
 set +e
 "${command[@]}" > "$output/logs/import-$mode.log" 2>&1
 probe_result=$?
 set -e
 print "$probe_result" > "$output/logs/import-$mode.exit"
 print -r -- "import=$mode exit=$probe_result"
done
exit "$result"
