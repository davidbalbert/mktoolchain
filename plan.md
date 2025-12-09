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
# Build specific components (HOST and TARGET default to build system)
make gcc
make binutils
make glibc

# Build for different architectures
make gcc HOST=aarch64 TARGET=x86_64
make binutils HOST=x86_64 TARGET=x86_64
make glibc HOST=aarch64 TARGET=aarch64

# Use alternative config
make gcc HOST=x86_64 TARGET=x86_64 CONFIG=musl-toolchain.mk
```

### Alternative Targets
```bash
# Just download and verify sources
make download

# Bootstrap component targets
make bootstrap-gcc
make bootstrap-binutils
make bootstrap-glibc
make bootstrap-libstdc++

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

# User-facing phony targets (convenience aliases only)
gcc: build/linux/$(HOST)/$(TARGET_TOOLCHAIN_NAME)/.gcc.installed
binutils: build/linux/$(HOST)/$(TARGET_TOOLCHAIN_NAME)/.binutils.installed
glibc: build/linux/$(HOST)/$(TARGET_TOOLCHAIN_NAME)/.glibc.installed

bootstrap-gcc: build/bootstrap/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.gcc.installed
bootstrap-binutils: build/bootstrap/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.binutils.installed
bootstrap-glibc: build/bootstrap/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.glibc.installed
bootstrap-libstdc++: build/bootstrap/$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/.libstdc++.installed

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
- [ ] Test that pattern rules work for all toolchain paths

### Step 4: Move Target-Specific Variables to .installed Targets
- [x] Move variables from `bootstrap-component:` to `path/.component.installed:` in binutils.mk
- [x] Move variables from `component:` to `path/.component.installed:` in binutils.mk
- [x] Repeat for gcc.mk, glibc.mk, linux.mk, libstdc++.mk
- [x] Update hardcoded paths in variables like `SYSROOT_SYMLINK`, `SYSROOT_SYMLINK_DIR`
- [x] Ensure pattern rules can still inherit variables from `.installed` targets
- [ ] Test that variables are set correctly during builds

### Step 5: Update Dependencies and Prerequisites
- [x] Eliminate all order-only prerequisites (`| bootstrap-binutils`) throughout all .mk files
- [x] Make gcc dependencies conditional on build phase (declare on `.installed` files)
- [x] Make glibc dependencies conditional on build phase (declare on `.installed` files)
- [x] Make bootstrap-libstdc++ dependencies conditional on build phase (declare on `.installed` files)
- [x] Make linux-headers dependencies conditional on build phase (declare on `.installed` files)
- [x] Add proper ordering within phases (binutils → gcc → glibc, bootstrap: + libstdc++)
- [ ] Test dependency resolution for different build scenarios

### Step 6: Simplify Phony Targets
- [ ] Remove most phony aliases (gcc, binutils, glibc, bootstrap-*, linux-headers)
- [ ] Keep only `toolchain` as the main user-facing phony target
- [ ] Keep `download`, `clean`, `clean-bootstrap`, `clean-downloads`, `clean-sources` targets
- [ ] Update `.PHONY:` declarations to match new target structure

### Step 7: Update Clean Targets
- [x] Update clean targets to work with new unified directory structure
- [ ] Test that clean operations work correctly for different BUILD/HOST/TARGET combinations

### Step 8: Add ld-linux-shim Build
- [ ] Create `mk/ld-linux-shim.mk` that builds ld-linux-shim without recursive make
- [ ] Use target toolchain (TARGET_PREFIX) to compile ld-linux-shim
- [ ] Install to `$(TARGET_PREFIX)/libexec/ld-linux-shim`
- [ ] Keep existing `ld-linux-shim/Makefile` for compatibility with old script build system
- [ ] Make ld-linux-shim depend on `.gcc.installed`
- [ ] Use git commit timestamp for SOURCE_DATE_EPOCH (not tarball timestamp)

### Step 9: Add Toolchain Target with Relocation
- [ ] Add `.toolchain` file target that runs `make-reloc.sh` on the target toolchain
- [ ] `.toolchain` depends on `.gcc.installed`, `.glibc.installed`, and `.ld-linux-shim.installed` files
- [ ] Add `toolchain` phony target as alias to `.toolchain` file
- [ ] Make `toolchain` the default target

### Step 10: Testing and Validation
- [ ] Test `make toolchain` builds everything correctly
- [ ] Test `make toolchain HOST=x86_64 TARGET=aarch64` for cross-compilation
- [ ] Verify all generated paths and toolchain names are correct
- [ ] Verify reproducibility flags are still applied correctly
- [ ] Test parallel builds work correctly
- [ ] Test ld-linux-shim builds correctly with target toolchain
- [ ] Test relocatable toolchain works from different locations
- [ ] Test build reproducibility: build from two different directories and verify identical outputs (e.g., `diff -r` or compare checksums)
