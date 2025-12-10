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
    patchelf --set-rpath "$rpath" "$real_binary"

    # Set interpreter to non-existent path to force use of our shim
    echo "  Setting interpreter to /nonexistent/ld.so"
    patchelf --set-interpreter "/nonexistent/ld.so" "$real_binary"

    touch -h -d "@$original_timestamp" "$binary"
    touch -h -d "@$original_timestamp" "$real_binary"
done < <(find "$TARGET_DIR" -type f -name "*.real" -prune -o -type f -print0)

echo "Relocatable binaries created in $TARGET_DIR"
