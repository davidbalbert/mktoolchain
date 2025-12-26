#!/bin/bash
set -euo pipefail

print_usage() {
    echo "Usage: $(basename "$0") TARGET_DIR"
    echo ""
    echo "Make binaries relocatable by updating RPATHs and using ld-linux-shim."
    echo ""
    echo "Options:"
    echo "  --help               Display this help message"
    echo ""
    echo "Arguments:"
    echo "  TARGET_DIR           Directory tree containing binaries to make relocatable"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

for arg in "$@"; do
    case $arg in
        --help)
            print_usage
            exit 0
            ;;
        -*)
            echo "Error: Unknown option '$arg'"
            print_usage
            exit 1
            ;;
        *)
            if [ -z "${TARGET_DIR:-}" ]; then
                TARGET_DIR="$arg"
            else
                echo "Error: Too many arguments"
                print_usage
                exit 1
            fi
            ;;
    esac
done

if [ -z "${TARGET_DIR:-}" ]; then
    echo "Error: TARGET_DIR is required"
    print_usage
    exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: TARGET_DIR '$TARGET_DIR' does not exist"
    exit 1
fi

# Convert to absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

echo "Making binaries relocatable in $TARGET_DIR..."

# Delete libtool .la files - they contain hardcoded build paths and are not needed
echo "Removing .la files..."
find "$TARGET_DIR" -name "*.la" -type f -delete

# Get the built shim
SHIM_PATH="$TARGET_DIR/libexec/ld-linux-shim"

if [ ! -f "$SHIM_PATH" ]; then
    echo "Error: ld-linux-shim not found at $SHIM_PATH"
    exit 1
fi

# Always use host-sysroot for the dynamic linker
# For native compilers: host-sysroot → sysroot
# For cross-compilers: host-sysroot → BUILD toolchain's sysroot
SYSROOT_NAME="host-sysroot"

# The placeholder RPATH used during build (must match Makefile)
RPATH_PLACEHOLDER="/XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

while IFS= read -r -d '' binary; do
    if ! file "$binary" | grep -q "ELF.*executable"; then
        continue
    fi

    if file "$binary" | grep -q "statically linked"; then
        continue
    fi

    # Get path relative to TARGET_DIR
    rel_path="${binary#$TARGET_DIR/}"

    if [[ "$binary" == *.real ]]; then
        continue
    fi

    dir_path="$(dirname "$binary")"
    base_name="$(basename "$binary")"

    echo "Processing $rel_path"

    original_timestamp=$(stat -c %Y "$binary")

    real_binary="$binary.real"
    mv "$binary" "$real_binary"

    # Depth of the binary relative to TARGET_DIR
    depth=$(echo "$rel_path" | tr -cd '/' | wc -c)

    libexec_rel_path=""
    for ((i=0; i<depth; i++)); do
        libexec_rel_path+="../"
    done
    libexec_rel_path+="libexec/ld-linux-shim"

    cd "$dir_path"
    ln -sfn "$libexec_rel_path" "$base_name"
    cd - > /dev/null

    # Set rpath for sysroot location
    rpath_prefix=""
    for ((i=0; i<depth; i++)); do
        rpath_prefix+="../"
    done
    rpath="\$ORIGIN/${rpath_prefix}${SYSROOT_NAME}/usr/lib"

    echo "  Setting rpath: $rpath"
    # Directly set new rpath (placeholders are fixed-length so no --remove-rpath needed)
    patchelf --set-rpath "$rpath" "$real_binary"

    # Set interpreter to non-existent path to force use of our shim
    echo "  Setting interpreter to /nonexistent/ld.so"
    patchelf --set-interpreter "/nonexistent/ld.so" "$real_binary"

    touch -h -d "@$original_timestamp" "$binary"
    touch -h -d "@$original_timestamp" "$real_binary"
done < <(find "$TARGET_DIR" -type f -name "*.real" -prune -o -type f -print0)

# Also fix RPATH in shared libraries that have the placeholder
echo "Fixing shared library RPATHs..."
while IFS= read -r -d '' lib; do
    if ! file "$lib" | grep -q "ELF.*shared object"; then
        continue
    fi

    # Check if it has our placeholder in the RPATH
    current_rpath=$(patchelf --print-rpath "$lib" 2>/dev/null || true)
    if [[ "$current_rpath" != *"$RPATH_PLACEHOLDER"* ]] && [[ "$current_rpath" != *"/workspaces/"* ]]; then
        continue
    fi

    rel_path="${lib#$TARGET_DIR/}"
    echo "Processing shared library $rel_path"

    original_timestamp=$(stat -c %Y "$lib")

    # Calculate depth for $ORIGIN-relative path
    depth=$(echo "$rel_path" | tr -cd '/' | wc -c)
    rpath_prefix=""
    for ((i=0; i<depth; i++)); do
        rpath_prefix+="../"
    done
    rpath="\$ORIGIN/${rpath_prefix}${SYSROOT_NAME}/usr/lib"

    echo "  Setting rpath: $rpath"
    # Remove old RPATH entirely and add new one - this normalizes the section
    patchelf --remove-rpath "$lib"
    patchelf --set-rpath "$rpath" "$lib"

    touch -h -d "@$original_timestamp" "$lib"
done < <(find "$TARGET_DIR" -type f \( -name "*.so" -o -name "*.so.*" \) -print0)

echo "Relocatable binaries created in $TARGET_DIR"
