# mktoolchain implementation plan

## Project Goal
Build statically linked C/C++ cross compilers and sysroots that don't depend on any system libraries. The toolchains will be used with Bazel, so sysroots need to contain only Linux kernel headers, libc + headers, and C++ standard library + headers.

## Current status
Migrating the various scripts that build the toolchain to a Makefile

## Proposed User Interface

### Primary Usage
```bash
# Build the complete toolchain (default)
make toolchain

# Build for different architectures
make toolchain HOST=linux/aarch64 TARGET=linux/x86_64

# Just download and verify sources
make download

# Clean everything
make clean
```

### Variables
- `HOST` - Where the compiler runs (defaults to build system)
- `TARGET` - What the compiler builds for (defaults to HOST)
- `CONFIG` - Config file (default: config.mk)
- `BUILD_ROOT` - Build directory (default: current directory)

### File Structure Generated
```
out/
├── linux/
│   ├── aarch64/
│   │   ├── aarch64-linux-gnu-gcc-15.1.0/
│   │   │   ├── toolchain/     # Final toolchain (HOST=aarch64, TARGET=aarch64)
│   │   │   └── sysroot/       # Final sysroot
│   │   └── x86_64-linux-gnu-gcc-15.1.0/
│   │       ├── toolchain/     # Cross-compiler (HOST=aarch64, TARGET=x86_64)
│   │       └── sysroot/       # Cross-compiler sysroot
│   └── x86_64/
│       └── x86_64-linux-gnu-gcc-15.1.0/
│           ├── toolchain/     # Final toolchain (HOST=x86_64, TARGET=x86_64)
│           └── sysroot/       # Final sysroot
└── bootstrap/
    └── aarch64/
        └── aarch64-linux-gnu-gcc-15.1.0/
            └── toolchain/     # Bootstrap toolchain (minimal for build system)
```

### Key Design Principles
1. **Ease of use**: Multi-phase build happens automatically via dependencies
2. **Conditional phases**: Cross-compiler built only when HOST ≠ BUILD system
3. **Automatic naming**: Toolchain names constructed from TARGET + config suffix
4. **Granular control**: Individual component and bootstrap targets available
5. **Parallel safe**: All targets support `make -j`
6. **Resumable**: Can restart from any phase if previous phases complete

## Config File Design

### config.mk Example
```makefile
# Toolchain recipe identifier (architecture/OS/libc added automatically)
TOOLCHAIN_NAME := gcc-15.1.0
LIBC := glibc  # or musl

# Package versions
GCC_VERSION := 15.1.0
BINUTILS_VERSION := 2.44
GLIBC_VERSION := 2.41
LINUX_VERSION := 6.6.89

# Expected SHA256 checksums
GCC_SHA256 := 51b9919ea69c980d7a381db95d4be27edf73b21254eb13d752a08003b4d013b1
BINUTILS_SHA256 := 0cdd76777a0dfd3dd3a63f215f030208ddb91c2361d2bcc02acec0f1c16b6a2e
GLIBC_SHA256 := c7be6e25eeaf4b956f5d4d56a04d23e4db453fc07760f872903bb61a49519b80
LINUX_SHA256 := 724f68742eeccf26e090f03dd8dfbf9c159d65f91d59b049e41f996fa41d9bc1

# Full toolchain name constructed as: $(TARGET_ARCH)-$(TARGET_OS)-$(ENV)-$(TOOLCHAIN_SUFFIX)
# where ENV maps: glibc → gnu, musl → musl
# Examples: aarch64-linux-gnu-gcc-15.1.0, x86_64-linux-gnu-gcc-15.1.0
```

### Future Config Variations
```makefile
# musl-toolchain.mk
TOOLCHAIN_NAME := gcc-15.1.0-musl
LIBC := musl

BINUTILS_VERSION := 2.44
MUSL_VERSION := 1.2.4
LINUX_VERSION := 6.6.89
GCC_VERSION := 15.1.0
# Results in: x86_64-linux-musl-gcc-15.1.0-musl

# clang-toolchain.mk
TOOLCHAIN_NAME := clang-18.0.0
LIBC := glibc
COMPILER := clang

BINUTILS_VERSION := 2.44
GLIBC_VERSION := 2.41
LINUX_VERSION := 6.6.89
LLVM_VERSION := 18.0.0
# Results in: x86_64-linux-gnu-clang-18.0.0
```

### Config File Rules
1. **Package versions and checksums** - Core responsibility
2. **Build tool selection** - LIBC, COMPILER choices
3. **Recipe suffix only** - Architecture/OS automatically added from TARGET
4. **No reproducibility settings** - Always set appropriately by makefile
5. **Makefile syntax** - Simple variable assignments for easy inclusion

## Dependency Graph

### Multi-Phase Build Flow

The number of phases depends on the relationship between BUILD system, HOST, and TARGET:

#### Case 1: BUILD = HOST = TARGET (Native build on build system)
```
Downloads & Sources → Bootstrap → Native Toolchain
```

#### Case 2: BUILD = HOST ≠ TARGET (Cross-compiler for build system)
```
Downloads & Sources → Bootstrap → Native Toolchain → Final Cross-Compiler
```

#### Case 3: BUILD ≠ HOST (Toolchain for different system)
```
Downloads & Sources → Bootstrap → Native → Cross-Compiler → Final Toolchain
```

### Make Target Dependencies
```makefile
# Default config file
CONFIG ?= config.mk

# Default HOST and TARGET to build system
HOST ?= $(BUILD)
TARGET ?= $(HOST)

# Map LIBC to environment name (LLVM convention)
ifeq ($(LIBC),glibc)
  ENV := gnu
else
  ENV := $(LIBC)
endif

# Construct toolchain names for different phases
BUILD_TOOLCHAIN_NAME := $(BUILD)-linux-$(ENV)-$(TOOLCHAIN_SUFFIX)
CROSS_TOOLCHAIN_NAME := $(HOST)-linux-$(ENV)-$(TOOLCHAIN_SUFFIX)
TARGET_TOOLCHAIN_NAME := $(TARGET)-linux-$(ENV)-$(TOOLCHAIN_SUFFIX)

# Main user-facing target
toolchain: build/linux/$(HOST)/$(TARGET_TOOLCHAIN_NAME)/.gcc.installed

# Target-specific variables set on actual .installed file targets
build/bootstrap/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.gcc.installed: TOOLCHAIN_TYPE = bootstrap
build/linux/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.gcc.installed: TOOLCHAIN_TYPE = native
build/linux/$(BUILD)/$(CROSS_TOOLCHAIN_NAME)/.gcc.installed: TOOLCHAIN_TYPE = cross
build/linux/$(HOST)/$(TARGET_TOOLCHAIN_NAME)/.gcc.installed: TOOLCHAIN_TYPE = final
```

## Changes Needed to Migrate from current Makefile setup.

### Toolchain Naming
- Keep `TOOLCHAIN_NAME := gcc-15.1.0` in config.mk
- Change toolchain directory names to `$(TARGET_TRIPLE)-$(TOOLCHAIN_NAME)`
- So `aarch64-linux-gnu` target becomes `aarch64-linux-gnu-gcc-15.1.0`
- Update all path variables to use new computed toolchain directory names

### Directory Structure
- Keep `os/arch` format for BUILD/HOST/TARGET
- Use consistent `out/OS/ARCH/full-toolchain-name/` pattern
- Eliminate separate bootstrap path logic, unify into single pattern

## Implementation Plan

*When you've finished a step, please check it off*

## Cross-Compilation Bug Investigation (June 2025)

### Reported Issues

1. **Build stops after one target**: Running `make -f /workspace/mktoolchain/Makefile HOST=... TARGET=...` builds one target file (e.g. `.binutils.installed`) and then stops. Need to re-run make multiple times.

2. **Wrong binary prefixes in cross-compiler**: Building aarch64→x86_64 cross-compiler produces binaries with `aarch64-linux-gnu-` prefix instead of `x86_64-linux-gnu-`:
   ```
   out/linux/aarch64/x86_64-linux-gnu-gcc-15.1.0/toolchain/bin/
   aarch64-linux-gnu-addr2line  (WRONG - should be x86_64-linux-gnu-)
   ```

### Root Cause Analysis

**Issue 1 (Build stops)**: Likely a Make dependency issue where:
- A target is marked complete but its dependencies aren't properly declared
- The default goal only triggers one branch of the dependency tree
- Pattern rule matching may be inconsistent

**Issue 2 (Wrong prefixes)**: In `binutils.mk` line 45:
```makefile
--program-prefix=$(TARGET_TRIPLE)-
```
The `TARGET_TRIPLE` variable must be getting the wrong value. Looking at the target-specific variables:
- `$(TARGET_BUILD_DIR)/.binutils.installed` does NOT set `TARGET_TRIPLE` explicitly
- It inherits the global `TARGET_TRIPLE` which is correct for the final target
- BUT for cross-compiler builds, the CROSS toolchain builds BUILD→HOST binutils

Looking at line 18-22 in binutils.mk:
```makefile
$(CROSS_BUILD_DIR)/.binutils.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.binutils.installed: TARGET_TRIPLE := $(HOST_TRIPLE)  # BUG: This sets to HOST_TRIPLE AFTER redefining HOST_TRIPLE
```

The issue is that `$(HOST_TRIPLE)` on the RHS refers to the global `HOST_TRIPLE`, not the just-assigned target-specific one. This is correct for CROSS.

For TARGET (the final toolchain), there's no explicit `TARGET_TRIPLE` assignment, so it uses the global value which should be correct.

Wait - the issue is in the path structure. Let me check:
- `CROSS_BUILD_DIR` = `build/linux/BUILD_ARCH/HOST_TRIPLE-gcc-15.1.0`
- When building aarch64→x86_64, HOST=x86_64, so:
  - `HOST_TRIPLE` = x86_64-linux-gnu
  - `CROSS_TOOLCHAIN_NAME` = x86_64-linux-gnu-gcc-15.1.0
  - `CROSS_BUILD_DIR` = build/linux/aarch64/x86_64-linux-gnu-gcc-15.1.0

But the binutils in CROSS are being built with aarch64 target prefix... Let me trace through more carefully.

Actually, looking at line 18-19:
```makefile
$(CROSS_BUILD_DIR)/.binutils.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.binutils.installed: TARGET_TRIPLE := $(HOST_TRIPLE)
```

#### Tips for Long Builds:
The heartbeat pattern prevents the 300s Bash inactivity timeout:
```bash
(while true; do sleep 60; echo -n "."; done) &
HEARTBEAT_PID=$!
make -f /workspaces/mktoolchain/Makefile toolchain > logs/build.log 2>&1
kill $HEARTBEAT_PID 2>/dev/null
```

Always redirect build output to log files (don't use `tee`). Check logs with `tail -20 logs/build.log`.

## Reproducibility Verification (December 2024)

### Verified Reproducible
The following key binaries are **byte-for-byte identical** when built from different directories:

| Binary | Status |
|--------|--------|
| libc.so.6 | ✅ Reproducible |
| gcc | ✅ Reproducible |
| g++ | ✅ Reproducible |
| ld | ✅ Reproducible |
| libgcc.a | ✅ Reproducible |
| libgcc_eh.a | ✅ Reproducible |
| libgcc_s.so.1 | ✅ Reproducible |
| as | ✅ Reproducible |
| ar | ✅ Reproducible |
| ranlib | ✅ Reproducible |
| ld-linux-shim | ✅ Reproducible |

### Fixes Applied for libgcc Archives
1. Modified gcc.mk to patch `AR_CREATE_FOR_TARGET` in libgcc/Makefile from `rc` to `Drc`
2. Added `RANLIB_FOR_TARGET=$(RANLIB) -D` to make commands to use deterministic ranlib

### Remaining Non-Reproducible Items
- **libc.a** and other glibc static archives have non-deterministic symbol table timestamps
- **libstdc++.a** archives may have similar issues
- These only affect static linking and are not critical for most use cases

## Reproducibility Verification (December 2024 - Phase 2)

### Current Status: 100% Reproducible ✅

| Metric | Count |
|--------|-------|
| Total files | 6,529 |
| Matching files | 6,529 |
| Differing files | 0 |

### Fixes Applied in This Phase

#### 1. Fixed-length interpreter symlink (`INTERP_SYMLINK`)

**Problem**: ELF executables embed the path to the dynamic linker (ld-linux) in their `.interp` section. When we link binaries with `--dynamic-linker=/path/to/ld-linux`, that path gets embedded. If the build directory path differs (e.g., `/workspaces/buildroot` vs `/workspaces/buildroot2`), the `.interp` section has different lengths, making the entire ELF file layout differ.

**Solution**: Create a fixed-length symlink at `/tmp/ld-shim-XXX...XXX` (exactly 128 characters) that points to the real ld-linux. All binaries use this symlink as their interpreter. Since the symlink path is always the same length, ELF section layouts are identical regardless of the actual build directory.

**Location**: `Makefile` lines 74-84, used via `$(INTERP_SYMLINK)` in LDFLAGS

#### 2. Disabled build-id for bootstrap (`--build-id=none`)

**Problem**: GCC's GNU build-id is a hash computed from the binary's contents during linking. The hash includes things like timestamps or ordering that can vary between builds, making bootstrap binaries non-reproducible.

**Solution**: Pass `-Wl,--build-id=none` in LDFLAGS for bootstrap builds to disable build-id generation entirely.

**Location**: `mk/binutils.mk` lines 6-7, `mk/gcc.mk` lines 10-11

#### 3. Delete .la files

**Problem**: Libtool generates `.la` files (libtool archives) that contain hardcoded absolute paths in their `dependency_libs=` field. For example: `dependency_libs=' -L/workspaces/buildroot/out/.../lib -lz'`. These paths differ between build directories.

**Solution**: Delete all `.la` files during installation. They're only needed for linking during the build process and are not required at runtime or for using the installed toolchain.

**Location**: `mk/binutils.mk` line 79, `script/make-reloc.sh` lines 59-60

#### 4. Normalize checksum-options

**Problem**: GCC embeds an "executable checksum" in cc1/cc1plus binaries for precompiled header (PCH) compatibility checking. This checksum is computed by `genchecksum` from object files AND a `checksum-options` file. The `checksum-options` file contains the linker command line, which includes `-ffile-prefix-map=/workspaces/buildroot=.`. Since the actual build path appears in this file, the checksum differs between builds from different directories.

**Solution**: After running `configure-gcc`, patch the generated `gcc/Makefile` to replace the rule that creates `checksum-options`. Instead of writing the actual linker flags, it now writes the fixed string "deterministic". We also delete any existing `checksum-options` file to ensure it gets regenerated with the new rule.

**Location**: `mk/gcc.mk` lines 134-135:
```makefile
sed -i '/^checksum-options:/,/move-if-change/{s|echo "\$$(LINKER).*"|echo "deterministic"|g}' gcc/Makefile && \
rm -f gcc/checksum-options && \
```

#### 5. Disable libcc1 (`--disable-libcc1`)

**Problem**: The libcc1 library (used for GDB's `compile` command) was built with libtool, which hardcodes library search paths into the RPATH. Specifically, libtool sets `hardcode_into_libs=yes` and adds the bootstrap compiler's library path (e.g., `/workspaces/buildroot/out/bootstrap/.../lib64`) to the RPATH. Since this path differs between builds, the resulting `.so` files have different RPATH string lengths, causing the entire ELF string table section to differ.

We tried several fixes:
- Patching libtool's `hardcode_into_libs=no` - didn't work because libtool is generated during the build
- Using patchelf to normalize RPATH - didn't work because patchelf doesn't shrink ELF sections, just fills with padding
- Using objcopy to extract/rebuild sections - code sections were identical but metadata sections still differed

**Solution**: Disable libcc1 entirely with `--disable-libcc1` in GCC's configure. libcc1 is only used for GDB's `compile` command (which allows compiling C expressions at the GDB prompt), a feature that's rarely used in practice.

**Location**: `mk/gcc.mk` line 108:
```makefile
GCC_FINAL_CONFIG = \
    --enable-host-pie \
    --disable-fixincludes \
    --disable-libcc1
```

### Summary of File Changes

| File | Change |
|------|--------|
| `mk/binutils.mk:79` | Delete .la files during install |
| `mk/gcc.mk:10-11` | `--build-id=none` for bootstrap LDFLAGS |
| `mk/gcc.mk:108` | `--disable-libcc1` in GCC_FINAL_CONFIG |
| `mk/gcc.mk:134-135` | Normalize checksum-options content |
| `script/make-reloc.sh:59-60` | Delete .la files |
| `script/make-reloc.sh:136-168` | Fix shared library RPATHs |
| `Makefile:74-84` | Fixed-length INTERP_SYMLINK |
