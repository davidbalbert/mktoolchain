CONFIG ?= config.mk

PROJECT_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

ifneq ($(filter $(PROJECT_ROOT) $(PROJECT_ROOT)/%,$(CURDIR)),)
$(error In-tree builds are not supported. Please run from a separate build directory using: make -f $(PROJECT_ROOT)/Makefile)
endif

export LC_ALL := C.UTF-8

ifeq ($(filter -j%,$(MAKEFLAGS)),)
  MAKEFLAGS += -j$(shell nproc)
endif

include $(CONFIG)

BUILD := $(shell uname -s | tr A-Z a-z)/$(shell uname -m)
HOST ?= $(BUILD)
TARGET ?= $(HOST)

ORIG_PATH := $(PATH)

# Convert os/arch to GNU triple (e.g., linux/aarch64 -> aarch64-linux-gnu)
os_arch_to_triple = $(word 2,$(subst /, ,$(1)))-$(word 1,$(subst /, ,$(1)))-gnu
BUILD_TRIPLE := $(call os_arch_to_triple,$(BUILD))
HOST_TRIPLE := $(call os_arch_to_triple,$(HOST))
TARGET_TRIPLE := $(call os_arch_to_triple,$(TARGET))

BUILD_ROOT ?= .
BUILD_ROOT := $(abspath $(BUILD_ROOT))
BUILD_DIR := $(BUILD_ROOT)/build
OUT_DIR := $(BUILD_ROOT)/out
DL_DIR := $(BUILD_ROOT)/dl
SRC_DIR := $(BUILD_ROOT)/src

# Extract architecture from os/arch format
BUILD_ARCH := $(word 2,$(subst /, ,$(BUILD)))
HOST_ARCH := $(word 2,$(subst /, ,$(HOST)))
TARGET_ARCH := $(word 2,$(subst /, ,$(TARGET)))

# Computed toolchain names following $(TARGET_TRIPLE)-$(TOOLCHAIN_NAME) pattern
BUILD_TOOLCHAIN_NAME := $(BUILD_TRIPLE)-$(TOOLCHAIN_NAME)
CROSS_TOOLCHAIN_NAME := $(HOST_TRIPLE)-$(TOOLCHAIN_NAME)
TARGET_TOOLCHAIN_NAME := $(TARGET_TRIPLE)-$(TOOLCHAIN_NAME)

# Computed build directories
BOOTSTRAP_BUILD_DIR := $(BUILD_DIR)/bootstrap/$(BUILD_ARCH)/$(BUILD_TOOLCHAIN_NAME)
BUILD_BUILD_DIR := $(BUILD_DIR)/linux/$(BUILD_ARCH)/$(BUILD_TOOLCHAIN_NAME)
CROSS_BUILD_DIR := $(BUILD_DIR)/linux/$(BUILD_ARCH)/$(CROSS_TOOLCHAIN_NAME)
TARGET_BUILD_DIR := $(BUILD_DIR)/linux/$(HOST_ARCH)/$(TARGET_TOOLCHAIN_NAME)

# Computed output directories
BOOTSTRAP_OUT_DIR := $(OUT_DIR)/bootstrap/$(BUILD_ARCH)/$(BUILD_TOOLCHAIN_NAME)
BUILD_OUT_DIR := $(OUT_DIR)/linux/$(BUILD_ARCH)/$(BUILD_TOOLCHAIN_NAME)
CROSS_OUT_DIR := $(OUT_DIR)/linux/$(BUILD_ARCH)/$(CROSS_TOOLCHAIN_NAME)
TARGET_OUT_DIR := $(OUT_DIR)/linux/$(HOST_ARCH)/$(TARGET_TOOLCHAIN_NAME)

# Computed prefixes
BOOTSTRAP_PREFIX := $(BOOTSTRAP_OUT_DIR)/toolchain
BUILD_PREFIX := $(BUILD_OUT_DIR)/toolchain
CROSS_PREFIX := $(CROSS_OUT_DIR)/toolchain
TARGET_PREFIX := $(TARGET_OUT_DIR)/toolchain

# Computed sysroots
BUILD_SYSROOT := $(BUILD_OUT_DIR)/sysroot
CROSS_SYSROOT := $(CROSS_OUT_DIR)/sysroot
TARGET_SYSROOT := $(TARGET_OUT_DIR)/sysroot

# Fixed-length placeholder rpath for reproducibility (patchelf will replace with $ORIGIN-relative path)
RPATH_PLACEHOLDER := /XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Fixed-length symlink path for dynamic linker - ensures identical ELF section sizes regardless of build directory
# The actual symlink is created before building native toolchain and points to the real ld-linux
INTERP_SYMLINK := /tmp/ld-shim-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Rule to create the interpreter symlink (used only for BUILD=HOST=TARGET native builds)
# This creates a fixed-length path that points to the real dynamic linker
$(BUILD_BUILD_DIR)/.interp-symlink.installed: $(BUILD_BUILD_DIR)/.glibc.installed
	@REAL_INTERP=$$(find $(BUILD_SYSROOT)/usr/lib -name "ld-linux-*.so.*" -type f | head -n 1); \
	if [ -n "$$REAL_INTERP" ]; then \
		ln -sfn "$$REAL_INTERP" "$(INTERP_SYMLINK)"; \
		echo "Created interpreter symlink: $(INTERP_SYMLINK) -> $$REAL_INTERP"; \
	fi
	touch $@

include $(PROJECT_ROOT)/mk/*.mk

# Conditional dependency chains based on build scenario

# Phase dependency chains
# Case 1: Native build (BUILD = HOST = TARGET)
# No gcc-stage1 needed - bootstrap gcc can compile glibc directly
ifeq ($(BUILD)_$(HOST)_$(TARGET),$(BUILD)_$(BUILD)_$(BUILD))
  $(TARGET_BUILD_DIR)/.binutils.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
  # binutils.compiled needs glibc installed and the interpreter symlink created
  $(TARGET_BUILD_DIR)/.binutils.compiled: $(TARGET_BUILD_DIR)/.interp-symlink.installed
  $(TARGET_BUILD_DIR)/.glibc.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
  $(TARGET_BUILD_DIR)/.glibc.configured: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
  $(TARGET_BUILD_DIR)/.glibc.compiled: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
  # Bootstrap GCC has no libgcc_s, so force C version of links-dso-program
  $(TARGET_BUILD_DIR)/.glibc.compiled: $(TARGET_BUILD_DIR)/.glibc.configured
	cd $(TARGET_BUILD_DIR)/glibc/build && $(MAKE) CXX=
	touch $@
  $(TARGET_BUILD_DIR)/.glibc.installed: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
  $(TARGET_BUILD_DIR)/.gcc.configured: $(TARGET_BUILD_DIR)/.glibc.installed
# Case 2: Cross-compiler for build system (BUILD = HOST ≠ TARGET)
# gcc-stage1 provides cross-compiler for building TARGET glibc
else ifeq ($(HOST),$(BUILD))
  # BUILD native toolchain - same as Case 1, use bootstrap gcc for glibc
  $(BUILD_BUILD_DIR)/.binutils.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
  $(BUILD_BUILD_DIR)/.binutils.compiled: $(BUILD_BUILD_DIR)/.interp-symlink.installed
  $(BUILD_BUILD_DIR)/.glibc.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
  $(BUILD_BUILD_DIR)/.glibc.configured: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
  $(BUILD_BUILD_DIR)/.glibc.compiled: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
  $(BUILD_BUILD_DIR)/.glibc.compiled: $(BUILD_BUILD_DIR)/.glibc.configured
	cd $(BUILD_BUILD_DIR)/glibc/build && $(MAKE) CXX=
	touch $@
  $(BUILD_BUILD_DIR)/.glibc.installed: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
  $(BUILD_BUILD_DIR)/.gcc.configured: $(BUILD_BUILD_DIR)/.glibc.installed
  # TARGET cross-compiler
  $(TARGET_BUILD_DIR)/.binutils.installed: $(BUILD_BUILD_DIR)/.glibc.installed
  $(TARGET_BUILD_DIR)/.gcc-stage1.configured: $(BUILD_BUILD_DIR)/.glibc.installed
  # gcc-stage1 builds libgcc which needs glibc headers in TARGET sysroot
  $(TARGET_BUILD_DIR)/.gcc-stage1.compiled: $(TARGET_BUILD_DIR)/.glibc-headers.installed
  $(TARGET_BUILD_DIR)/.glibc.configured: $(TARGET_BUILD_DIR)/.gcc-stage1.installed
  $(TARGET_BUILD_DIR)/.gcc.configured: $(TARGET_BUILD_DIR)/.glibc.installed
# Case 3: Native or cross-compilation to different host (BUILD ≠ HOST)
else
  # BUILD native toolchain - same as Case 1 & 2, use bootstrap gcc for glibc
  $(BUILD_BUILD_DIR)/.binutils.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
  $(BUILD_BUILD_DIR)/.binutils.compiled: $(BUILD_BUILD_DIR)/.interp-symlink.installed
  $(BUILD_BUILD_DIR)/.glibc.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
  $(BUILD_BUILD_DIR)/.glibc.configured: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
  $(BUILD_BUILD_DIR)/.glibc.compiled: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
  $(BUILD_BUILD_DIR)/.glibc.compiled: $(BUILD_BUILD_DIR)/.glibc.configured
	cd $(BUILD_BUILD_DIR)/glibc/build && $(MAKE) CXX=
	touch $@
  $(BUILD_BUILD_DIR)/.glibc.installed: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
  $(BUILD_BUILD_DIR)/.gcc.configured: $(BUILD_BUILD_DIR)/.glibc.installed
  # CROSS toolchain (BUILD→HOST)
  $(CROSS_BUILD_DIR)/.binutils.installed: $(BUILD_BUILD_DIR)/.glibc.installed
  $(CROSS_BUILD_DIR)/.gcc-stage1.configured: $(BUILD_BUILD_DIR)/.glibc.installed
  $(CROSS_BUILD_DIR)/.glibc.configured: $(CROSS_BUILD_DIR)/.gcc-stage1.installed
  $(CROSS_BUILD_DIR)/.gcc.configured: $(CROSS_BUILD_DIR)/.glibc.installed
  # TARGET toolchain (HOST→TARGET, built using CROSS compiler)
  $(TARGET_BUILD_DIR)/.binutils.installed: $(CROSS_BUILD_DIR)/.glibc.installed
  $(TARGET_BUILD_DIR)/.gcc-stage1.configured: $(CROSS_BUILD_DIR)/.glibc.installed
  $(TARGET_BUILD_DIR)/.glibc.configured: $(TARGET_BUILD_DIR)/.gcc-stage1.installed
  $(TARGET_BUILD_DIR)/.gcc.configured: $(TARGET_BUILD_DIR)/.glibc.installed
endif

# Host-sysroot symlink for ALL toolchains
# For native compilers (HOST == TARGET): host-sysroot → sysroot
# For cross-compilers (HOST != TARGET): host-sysroot → ../../$(BUILD_TOOLCHAIN_NAME)/sysroot
# This allows ld-linux-shim to always use host-sysroot to find the HOST glibc
ifeq ($(HOST_TRIPLE),$(TARGET_TRIPLE))
$(TARGET_BUILD_DIR)/.host-sysroot.installed: $(TARGET_BUILD_DIR)/.gcc.installed
	ln -sfn sysroot $(TARGET_PREFIX)/host-sysroot
	touch $@
else
$(TARGET_BUILD_DIR)/.host-sysroot.installed: $(BUILD_BUILD_DIR)/.glibc.installed $(TARGET_BUILD_DIR)/.gcc.installed
	ln -sfn ../../$(BUILD_TOOLCHAIN_NAME)/sysroot $(TARGET_PREFIX)/host-sysroot
	touch $@
endif

TOOLCHAIN_DEPS := $(TARGET_BUILD_DIR)/.gcc.installed $(TARGET_BUILD_DIR)/.glibc.installed $(TARGET_BUILD_DIR)/.ld-linux-shim.installed $(TARGET_BUILD_DIR)/.host-sysroot.installed

.DEFAULT_GOAL := toolchain

.PHONY: toolchain download clean test-parallel

toolchain: $(TARGET_BUILD_DIR)/.toolchain

$(TARGET_BUILD_DIR)/.toolchain: $(TOOLCHAIN_DEPS)
	$(PROJECT_ROOT)/script/make-reloc.sh $(TARGET_PREFIX)
	touch $@

clean:
	rm -rf $(BUILD_DIR) $(OUT_DIR)

clean-bootstrap:
	rm -rf $(BUILD_DIR)/bootstrap $(OUT_DIR)/bootstrap

clean-downloads:
	rm -rf $(DL_DIR)

clean-sources:
	rm -rf $(SRC_DIR)
