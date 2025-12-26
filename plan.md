# mktoolchain implementation plan

## Project Goal
Build statically linked C/C++ cross compilers and sysroots that don't depend on any system libraries. The toolchains will be used with Bazel, so sysroots need to contain only Linux kernel headers, libc + headers, and C++ standard library + headers.

## Current status
Migrating the various scripts that build the toolchain to a Makefile

## Decisions Made

### Configuration System
- **Start with**: `config.mk` (may evolve to `toolchain-name.mk` later)
- **Config file contains**: Package versions (GCC, binutils, glibc, etc.), libc choice (glibc/musl)
- **Command line variables**: HOST and TARGET architectures (GOOS/GOARCH pattern)
- **Multiple configs**: Eventually support multiple config files in different build hierarchies

### File Organization
- **Downloads**: `dl/` directory (currently `pkg/`)
- **Build artifacts**: `out/` directory for install prefixes
- **Future**: `dist/` directory for final tarballs
- **Architecture support**: Use existing structure from plan.md

### Build Strategy
- **Approach**: Keep same build techniques as scripts, change interface to makefile
- **Out-of-tree builds**: Optimize for builds outside source tree (maybe `make -f`)
- **Cross-compilation**: Support aarch64 and x86_64, keep architecture-agnostic
- **Parallel builds**: Support `make -j` with job server integration
- **ld-linux-shim**: Include as `.mk` file, avoid recursive make

### Scope Decisions
- **No backwards compatibility** with scripts needed
- **No automated testing** for now (manual testing continues)
- **No separate config files per target**
- **Keep existing reproducibility techniques**

## Proposed User Interface

### Primary Usage
```bash
# Build the complete toolchain (default)
make toolchain

# Build for different architectures
make toolchain HOST=aarch64 TARGET=x86_64

# Just download and verify sources
make download

# Clean specific toolchain
make clean-toolchain HOST=aarch64 TARGET=aarch64

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

### Detailed Phase Breakdown
```
Downloads & Checksums
├── gcc-15.1.0.tar.gz
├── binutils-2.44.tar.gz
├── glibc-2.41.tar.gz
└── linux-6.6.89.tar.gz

Source Extraction & Patching
├── src/gcc-15.1.0/
├── src/binutils-2.44/
├── src/glibc-2.41/
└── src/linux-6.6.89/

Phase 1: Bootstrap Toolchain (BUILD→BUILD, always required)
├── bootstrap-binutils    (needs: binutils sources)
├── bootstrap-gcc         (needs: gcc sources, bootstrap-binutils)
├── linux-headers         (needs: linux sources)
├── bootstrap-glibc       (needs: glibc sources, bootstrap-gcc, linux-headers)
└── bootstrap-libstdc++   (needs: bootstrap-gcc, bootstrap-glibc)

Phase 2: Build→Build Toolchain (full-featured, always required)
├── binutils              (needs: binutils sources, bootstrap toolchain)
├── gcc                   (needs: gcc sources, binutils, bootstrap toolchain)
└── glibc                 (needs: glibc sources, gcc, bootstrap toolchain)

Phase 3: Build→Host Cross-Compiler (only when build ≠ HOST)
├── binutils              (needs: binutils sources, build→build toolchain)
├── gcc                   (needs: gcc sources, binutils, build→build toolchain)
└── glibc                 (needs: glibc sources, gcc, build→build toolchain)

Phase 4: Host→Target Toolchain (built with appropriate compiler)
├── binutils              (needs: binutils sources, compiler for HOST)
├── gcc                   (needs: gcc sources, binutils, compiler for HOST)
└── glibc                 (needs: glibc sources, gcc, compiler for HOST)
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

# Conditional file dependencies based on HOST/TARGET relationship
# Case 1: HOST == BUILD == TARGET (native compiler)
ifeq ($(HOST)_$(TARGET),$(BUILD)_$(BUILD))
  build/linux/$(HOST)/$(TARGET_TOOLCHAIN_NAME)/.gcc.installed: build/bootstrap/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.libstdc++.installed
# Case 2: HOST == BUILD ≠ TARGET (cross-compiler for current system)
else ifeq ($(HOST),$(BUILD))
  build/linux/$(HOST)/$(TARGET_TOOLCHAIN_NAME)/.gcc.installed: build/linux/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.gcc.installed
  build/linux/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.gcc.installed: build/bootstrap/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.libstdc++.installed
# Case 3: HOST ≠ BUILD (cross-compilation)
else
  build/linux/$(HOST)/$(TARGET_TOOLCHAIN_NAME)/.gcc.installed: build/linux/$(BUILD)/$(CROSS_TOOLCHAIN_NAME)/.gcc.installed
  build/linux/$(BUILD)/$(CROSS_TOOLCHAIN_NAME)/.gcc.installed: build/linux/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.gcc.installed
  build/linux/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.gcc.installed: build/bootstrap/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.libstdc++.installed
endif

# Target-specific variables set on actual .installed file targets
build/bootstrap/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.gcc.installed: TOOLCHAIN_TYPE = bootstrap
build/linux/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.gcc.installed: TOOLCHAIN_TYPE = native
build/linux/$(BUILD)/$(CROSS_TOOLCHAIN_NAME)/.gcc.installed: TOOLCHAIN_TYPE = cross
build/linux/$(HOST)/$(TARGET_TOOLCHAIN_NAME)/.gcc.installed: TOOLCHAIN_TYPE = final
```

### Key Insights
1. **Phony targets as aliases** - User-facing targets are convenience aliases pointing to .installed files
2. **Target-specific variables on file targets** - Configuration set on actual .installed targets, not phony targets
3. **Flattened conditional logic** - Three clear cases using else ifeq instead of nested conditions
4. **Consistent file structure** - All toolchains use linux/HOST/toolchain-name/ layout (no build/cross/)
5. **Cross-compiler dependencies** - HOST==BUILD but TARGET≠BUILD goes through native compiler
6. **Automatic toolchain naming** - TARGET architecture/OS/libc + config suffix
7. **Clean rebuilds at each phase** - ensures proper linking and dependencies
8. **Parallel builds possible** within each phase but not across phases
9. **Source extraction** happens automatically via pattern rule
10. **Downloads can happen in parallel** and early

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

### Makefile Interface
- Move all target-specific variables from phony targets to `.installed` file targets
- Keep component targets (`gcc`, `binutils`, `glibc`) as aliases to `.installed` files
- Keep bootstrap component targets (`bootstrap-gcc`, `bootstrap-binutils`, `bootstrap-glibc`, `bootstrap-libstdc++`) as aliases

### Build Logic
- Add conditional logic for multi-phase builds based on BUILD/HOST/TARGET relationships
- Replace hardcoded `$(BB)/` and `$(B)/` with generic pattern rules
- Add proper dependency chains for cross-compilation scenarios
- Unify bootstrap and regular build into single pattern rules

### Path Variables & Build Directories
- Replace hardcoded `BB`, `B`, `BO`, `O` variables with computed paths based on BUILD/HOST/TARGET
- Replace hardcoded `NATIVE_PREFIX`, `BOOTSTRAP_PREFIX`, `TARGET_PREFIX` with unified path computation
- Replace hardcoded `$(SYSROOT)` with computed sysroot paths per toolchain
- Remove separate bootstrap vs regular path logic - use single pattern for all toolchains

### Dependencies & Ordering
- Eliminate all order-only prerequisites (`| bootstrap-binutils`) since dependencies will be declared on `.installed` files
- Add logic to determine which phase needs which components
- Replace hardcoded prerequisite chains with computed dependency relationships based on BUILD/HOST/TARGET

### Pattern Rules
- Current pattern rules hardcode `$(BB)` and `$(B)` paths - need generic rules that work for any toolchain path
- Update linux.mk to use generic paths instead of hardcoded `$(B)`
- Unify `.configured`, `.compiled`, `.installed` patterns across all phases
- Remove duplication between bootstrap and regular build rules

### Target-Specific Variables & Variable Inheritance
- Current `.mk` files set variables on phony targets (e.g., `bootstrap-gcc:`) and pattern rules inherit them
- Need to move all build-specific variables to the final `.installed` file targets to maintain inheritance
- Variables like `SYSROOT_SYMLINK`, `SYSROOT_SYMLINK_DIR` are hardcoded to current path structure and need computation
- Ensure variables like `PATH`, `CFLAGS`, `SOURCE_DATE_EPOCH` are available to pattern rules

### Missing Components
- Add bootstrap-libstdc++ component to new framework (missing from planning)
- Update linux-headers to work with generic path computation instead of hardcoded `$(B)`

### Clean Targets & Phony Declarations
- Update clean targets to work with new unified directory structure
- Update `.PHONY:` declarations to include `bootstrap-libstdc++`, `linux-headers` and remove obsolete targets

### Keep Unchanged
- ✅ `TOOLCHAIN_NAME` variable name in config.mk
- ✅ `os/arch` format
- ✅ `os_arch_to_triple` function
- ✅ Current config.mk structure

## Implementation Plan

*When you've finished a step, please check it off*

### Step 1: Update Path Computation and Toolchain Naming
- [x] Replace hardcoded `BB`, `B`, `BO`, `O` variables with computed paths based on BUILD/HOST/TARGET
- [x] Use `$(TARGET_TRIPLE)-$(TOOLCHAIN_NAME)` directly for toolchain directory names
- [x] Update `NATIVE_PREFIX`, `BOOTSTRAP_PREFIX`, `TARGET_PREFIX` to use new computed paths
- [x] Test that new paths generate correctly for different BUILD/HOST/TARGET combinations

### Step 2: Add BUILD/HOST/TARGET Conditional Logic
- [x] Add logic to determine which build phases are needed:
  - Native build: HOST==BUILD==TARGET (1 phase)
  - Cross compile: HOST==BUILD≠TARGET (2 phases: bootstrap + final)
  - Cross compile for different host: HOST≠BUILD (3-4 phases)
- [x] Create variables to track which toolchains need to be built
- [x] Add conditional dependency chains based on build scenario

### Step 3: Refactor Pattern Rules to be Generic
- [x] Replace hardcoded `$(BB)/.component.{configured,compiled,installed}` patterns
- [x] Replace hardcoded `$(B)/.component.{configured,compiled,installed}` patterns
- [x] Update linux.mk to use generic paths instead of hardcoded `$(B)`
- [x] Create single generic pattern rule that works for any toolchain path
- [x] Remove duplication between bootstrap and regular build rules
- [x] Test that pattern rules work for all toolchain paths

### Step 4: Move Target-Specific Variables to .installed Targets
- [x] Move variables from `bootstrap-component:` to `path/.component.installed:` in binutils.mk
- [x] Move variables from `component:` to `path/.component.installed:` in binutils.mk
- [x] Repeat for gcc.mk, glibc.mk, linux.mk, libstdc++.mk
- [x] Update hardcoded paths in variables like `SYSROOT_SYMLINK`, `SYSROOT_SYMLINK_DIR`
- [x] Ensure pattern rules can still inherit variables from `.installed` targets
- [x] Test that variables are set correctly during builds

### Step 5: Update Dependencies and Prerequisites
- [x] Eliminate all order-only prerequisites (`| bootstrap-binutils`) throughout all .mk files
- [x] Make gcc dependencies conditional on build phase (declare on `.installed` files)
- [x] Make glibc dependencies conditional on build phase (declare on `.installed` files)
- [x] Make bootstrap-libstdc++ dependencies conditional on build phase (declare on `.installed` files)
- [x] Make linux-headers dependencies conditional on build phase (declare on `.installed` files)
- [x] Add proper ordering within phases (binutils → gcc → glibc, bootstrap: + libstdc++)
- [x] Test dependency resolution for different build scenarios

### Step 6: Simplify Phony Targets
- [x] Remove most phony aliases (gcc, binutils, glibc, bootstrap-*, linux-headers)
- [x] Keep only `toolchain` as the main user-facing phony target
- [x] Keep `download`, `clean`, `clean-bootstrap`, `clean-downloads`, `clean-sources` targets
- [x] Update `.PHONY:` declarations to match new target structure

### Step 7: Update Clean Targets
- [x] Update clean targets to work with new unified directory structure
- [x] Test that clean operations work correctly for different BUILD/HOST/TARGET combinations

### Step 8: Add ld-linux-shim Build
- [x] Create `mk/ld-linux-shim.mk` that builds ld-linux-shim without recursive make
- [x] Use target toolchain (TARGET_PREFIX) to compile ld-linux-shim
- [x] Install to `$(TARGET_PREFIX)/libexec/ld-linux-shim`
- [x] Keep existing `ld-linux-shim/Makefile` for compatibility with old script build system
- [x] Make ld-linux-shim depend on `.gcc.installed`
- [x] Use git commit timestamp for SOURCE_DATE_EPOCH (not tarball timestamp)

### Step 9: Add Toolchain Target with Relocation
- [x] Add `.toolchain` file target that runs `make-reloc.sh` on the target toolchain
- [x] `.toolchain` depends on `.gcc.installed`, `.glibc.installed`, and `.ld-linux-shim.installed` files
- [x] Add `toolchain` phony target as alias to `.toolchain` file
- [x] Make `toolchain` the default target

### Step 10: Testing and Validation
- [x] Test `make toolchain` builds everything correctly (native aarch64 build works)
- [x] Verify all generated paths and toolchain names are correct
- [x] Test parallel builds work correctly
- [x] Test ld-linux-shim builds correctly with target toolchain
- [x] Test relocatable toolchain works from different locations
- [x] Test `make toolchain TARGET=linux/x86_64` for cross-compilation
- [x] Verify reproducibility flags are still applied correctly
  - All binaries now have zero path leaks (Dec 2024)
  - Used `-g0` for glibc and libgcc to eliminate debug info paths
  - Used `-ffile-prefix-map` and `SOURCE_DATE_EPOCH` throughout
- [ ] Test build reproducibility: build from two different directories and verify identical outputs
  - Path leaks are fixed, but need to verify byte-for-byte identical builds

Both native (BUILD=HOST=TARGET) and cross-compilation (aarch64→x86_64) work correctly with zero path leaks.

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

When these are evaluated:
- `HOST_TRIPLE` on RHS = the **global** HOST_TRIPLE (x86_64-linux-gnu when HOST=x86_64)
- So `TARGET_TRIPLE` is set to x86_64-linux-gnu, which is correct

The problem might be elsewhere. Let me look at what CROSS vs TARGET means in Case 3.

### Investigation Plan

1. **Test native aarch64→aarch64 build** (baseline, should work)
2. **Test cross aarch64→x86_64 build** (HOST=linux/aarch64, TARGET=linux/x86_64)
3. **Test x86_64 native via full chain** (HOST=linux/x86_64, TARGET=linux/x86_64 from aarch64 build machine)
4. **Examine dependency graph with `make -d`** to understand why build stops
5. **Add debug output** to trace variable values during cross builds

### Build Paths to Test

All of these should produce a working x86_64→x86_64 native compiler:

| Path | Commands | What happens |
|------|----------|--------------|
| 3-step | `make HOST=linux/aarch64 TARGET=linux/aarch64`, then `make HOST=linux/aarch64 TARGET=linux/x86_64`, then `make HOST=linux/x86_64 TARGET=linux/x86_64` | Build native, cross, then target |
| 2-step (native+target) | `make HOST=linux/aarch64 TARGET=linux/aarch64`, then `make HOST=linux/x86_64 TARGET=linux/x86_64` | Build native, then target (should auto-build cross) |
| 2-step (cross+target) | `make HOST=linux/aarch64 TARGET=linux/x86_64`, then `make HOST=linux/x86_64 TARGET=linux/x86_64` | Build cross, then target |
| 1-step | `make HOST=linux/x86_64 TARGET=linux/x86_64` | Single command triggers all 3 |

### Step 11: Fix Cross-Compilation Support

Cross-compilation (HOST=BUILD, TARGET≠BUILD) requires multi-stage gcc/glibc builds. The sequence is:

```
Phase 1: Bootstrap (BUILD→BUILD)
  bootstrap-binutils → bootstrap-gcc → linux-headers → bootstrap-glibc → bootstrap-libstdc++

Phase 2: Native BUILD Toolchain
  BUILD binutils → BUILD gcc → BUILD glibc

Phase 3: Cross Toolchain (BUILD→TARGET)
  TARGET binutils → TARGET linux-headers → TARGET gcc-stage1 → TARGET glibc → TARGET gcc → ld-linux-shim → .toolchain
```

**Key insight**: TARGET gcc must be built in two stages:
1. **gcc-stage1**: Built with `--disable-shared --with-newlib` (like bootstrap), produces cross-compiler that can build glibc
2. **gcc**: Full gcc with libgcc_s.so, built after glibc is installed

#### Tasks:
- [x] Fix glibc.mk PATH for TARGET: Use `$(TARGET_PREFIX)/bin` (the stage1 cross-compiler), not `$(CROSS_PREFIX)/bin`
- [x] Add TARGET gcc-stage1 target in gcc.mk
  - Similar to bootstrap gcc: `--disable-shared --with-newlib --without-headers`
  - Depends on TARGET binutils and TARGET linux-headers
  - Installs to TARGET_PREFIX
- [x] Make TARGET glibc depend on gcc-stage1 instead of full gcc
- [x] Make TARGET gcc (full) depend on TARGET glibc
- [x] Update dependency chain in Makefile for Case 2 (BUILD=HOST≠TARGET):
  ```makefile
  $(TARGET_BUILD_DIR)/.gcc-stage1.installed: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
  $(TARGET_BUILD_DIR)/.glibc.configured: $(TARGET_BUILD_DIR)/.gcc-stage1.installed
  $(TARGET_BUILD_DIR)/.gcc.configured: $(TARGET_BUILD_DIR)/.glibc.installed
  ```
- [x] Test cross-compilation: `make toolchain TARGET=linux/x86_64`

#### Remaining Issues:
- ✅ Fixed: Cross-toolchain now has `host-sysroot` symlink pointing to BUILD native sysroot for ld-linux-shim

### Step 12: Reproducibility Improvements

Implemented file-prefix-map and debug info improvements to eliminate embedded paths:

- [x] Added `-ffile-prefix-map=$(BUILD_ROOT)=.` to gcc.mk, glibc.mk, binutils.mk
- [x] Verified libgcc.a has 0 path leaks after rebuild
- [x] Fixed ld-linux-shim to use BOOTSTRAP gcc (statically linked, no relocation needed)
- [x] Changed glibc to build with `-g0` instead of `-g` to eliminate debug info paths
- [x] Changed gcc-stage1 to build libgcc with `CFLAGS="-g0 -O2" LIBGCC2_DEBUG_CFLAGS=-g0`
- [x] Added CFLAGS/CXXFLAGS/SOURCE_DATE_EPOCH pattern rules for gcc-stage1 targets
- [x] Added deterministic archive creation flags:
  - gcc: `AR_CREATE_FOR_TARGET=$(AR_FOR_TARGET) Drc` for libgcc archives
  - glibc: `CREATE_ARFLAGS=Dcru` for glibc archives
  - binutils: `AR_FLAGS=Drc` for binutils archives
- [ ] Investigate `--with-sysroot-prefix-map` option for GCC/binutils - NOT AVAILABLE in GCC 15.1
- [ ] Test full byte-for-byte reproducibility from different build directories

#### Current Status (December 2024):
All binaries now have **zero path leaks**:
- libc.so.6: 0 path leaks ✅
- libgcc.a: 0 path leaks ✅
- gcc binary: 0 path leaks ✅
- g++ binary: 0 path leaks ✅
- ld binary: 0 path leaks ✅

Both native (aarch64→aarch64) and cross-compiler (aarch64→x86_64) toolchains are clean.

#### Archive Reproducibility:
- libc.so.6: ✅ Identical (ELF binary)
- gcc binary: ✅ Identical (ELF binary)
- ld binary: ✅ Identical (ELF binary)
- libgcc.a: Needs deterministic ar flags (timestamps differ)

### Summary of Reproducibility Work (December 2024)

#### Fixes Applied:
1. **glibc**: Changed from `-g` to `-g0` to eliminate debug info paths
2. **gcc-stage1**: Added `CFLAGS="-g0 -O2"` and `LIBGCC2_DEBUG_CFLAGS=-g0` to build libgcc without debug info
3. **Deterministic archives**:
   - gcc: `AR_CREATE_FOR_TARGET=$(AR_FOR_TARGET) Drc`
   - glibc: `CREATE_ARFLAGS=Dcru`
   - binutils: `AR_FLAGS=Drc`

#### Results:
- **All ELF binaries** (libc.so.6, gcc, g++, ld) are **byte-for-byte identical** when built from different directories
- **All binaries** have **zero path leaks** (verified with `strings | grep`)
- **Archive files** (.a) need the deterministic ar flags to have epoch-0 timestamps

#### Remaining:
- Full clean build from two different directories to verify everything works together with the archive reproducibility fixes
- The `--with-sysroot-prefix-map` option is not available in GCC 15.1

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
