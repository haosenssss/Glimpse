#!/usr/bin/env bash
# Runs `swift <args>` for this package, working around two known leftovers from
# partial Command Line Tools upgrades. Both fixes only kick in when the stale
# file is detected (older than its replacement), so a clean toolchain runs as-is.
#
# 1. Stale PackageDescription *.private.swiftinterface: the manifest compiles
#    against the old interface and fails to link. Fix: use a cleaned copy of the
#    manifest libraries via SWIFTPM_CUSTOM_LIBS_DIR.
# 2. Stale usr/include/swift/module.modulemap duplicating bridging.modulemap
#    ("redefinition of module 'SwiftBridging'"). Fix: hide it with a VFS overlay.
#
# Permanent fix: move the stale files out of /Library/Developer/CommandLineTools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN_USR="$(dirname "$(xcrun --find swift)")/.."
PM_DIR="$TOOLCHAIN_USR/lib/swift/pm"
SWIFT_INCLUDE="$TOOLCHAIN_USR/include/swift"
FIX_DIR="$ROOT/.build/toolchain-fix"

has_stale_manifest_interface() {
    local file
    for file in "$PM_DIR"/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface; do
        [[ -f "$file" && "$file" -ot "$PM_DIR/ManifestAPI/libPackageDescription.dylib" ]] && return 0
    done
    return 1
}

has_stale_module_map() {
    [[ -f "$SWIFT_INCLUDE/module.modulemap" && -f "$SWIFT_INCLUDE/bridging.modulemap" \
        && "$SWIFT_INCLUDE/module.modulemap" -ot "$SWIFT_INCLUDE/bridging.modulemap" ]]
}

prepare_manifest_libs() {
    local libs="$FIX_DIR/pmlibs"
    if [[ ! -f "$libs/ManifestAPI/libPackageDescription.dylib" ]]; then
        mkdir -p "$libs"
        cp -R "$PM_DIR"/. "$libs"/
        rm -f "$libs"/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$libs"
}

write_overlay() {
    local include_dir
    include_dir="$(cd "$SWIFT_INCLUDE" && pwd -P)"
    mkdir -p "$FIX_DIR"
    : > "$FIX_DIR/empty.modulemap"
    cat > "$FIX_DIR/overlay.yaml" <<EOF
{"version":0,"case-sensitive":"false","roots":[{"type":"directory","name":"$include_dir","contents":[{"type":"file","name":"module.modulemap","external-contents":"$FIX_DIR/empty.modulemap"}]}]}
EOF
}

cd "$ROOT"
has_stale_manifest_interface && prepare_manifest_libs

extra_flags=()
if has_stale_module_map && [[ "${1:-}" =~ ^(build|test|run)$ ]]; then
    write_overlay
    extra_flags=(-Xcc -ivfsoverlay -Xcc "$FIX_DIR/overlay.yaml" -Xswiftc -vfsoverlay -Xswiftc "$FIX_DIR/overlay.yaml")
fi

exec swift "$@" ${extra_flags[@]+"${extra_flags[@]}"}
