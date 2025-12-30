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
DIST_DIR := $(BUILD_ROOT)/dist
DL_DIR := $(BUILD_ROOT)/dl
SRC_DIR := $(BUILD_ROOT)/src

# Extract architecture from os/arch format
BUILD_ARCH := $(word 2,$(subst /, ,$(BUILD)))
HOST_ARCH := $(word 2,$(subst /, ,$(HOST)))
TARGET_ARCH := $(word 2,$(subst /, ,$(TARGET)))

NATIVE_TOOLCHAIN_NAME := $(BUILD_TRIPLE)-$(TOOLCHAIN_NAME)

# NATIVE: runs on BUILD, targets BUILD (built by BOOTSTRAP)
# CROSS: runs on BUILD, targets HOST (built by NATIVE) - collapses to NATIVE when HOST=BUILD
# FINAL: runs on HOST, targets TARGET (built by CROSS) - collapses to NATIVE when BUILD=HOST=TARGET

BOOTSTRAP_BUILD_DIR := $(BUILD_DIR)/bootstrap/$(BUILD_ARCH)/$(NATIVE_TOOLCHAIN_NAME)
BOOTSTRAP_OUT_DIR := $(OUT_DIR)/bootstrap/$(BUILD_ARCH)/$(NATIVE_TOOLCHAIN_NAME)

NATIVE_BUILD_DIR := $(BUILD_DIR)/linux/$(BUILD_ARCH)/$(NATIVE_TOOLCHAIN_NAME)
NATIVE_OUT_DIR := $(OUT_DIR)/linux/$(BUILD_ARCH)/$(NATIVE_TOOLCHAIN_NAME)

ifeq ($(HOST),$(BUILD))
  CROSS_BUILD_DIR := $(NATIVE_BUILD_DIR)
  CROSS_OUT_DIR := $(NATIVE_OUT_DIR)
else
  CROSS_BUILD_DIR := $(BUILD_DIR)/linux/$(BUILD_ARCH)/$(HOST_TRIPLE)-$(TOOLCHAIN_NAME)
  CROSS_OUT_DIR := $(OUT_DIR)/linux/$(BUILD_ARCH)/$(HOST_TRIPLE)-$(TOOLCHAIN_NAME)
endif

ifeq ($(HOST)_$(TARGET),$(BUILD)_$(BUILD))
  FINAL_BUILD_DIR := $(NATIVE_BUILD_DIR)
  FINAL_OUT_DIR := $(NATIVE_OUT_DIR)
else
  FINAL_BUILD_DIR := $(BUILD_DIR)/linux/$(HOST_ARCH)/$(TARGET_TRIPLE)-$(TOOLCHAIN_NAME)
  FINAL_OUT_DIR := $(OUT_DIR)/linux/$(HOST_ARCH)/$(TARGET_TRIPLE)-$(TOOLCHAIN_NAME)
endif

BOOTSTRAP_PREFIX := $(BOOTSTRAP_OUT_DIR)/toolchain
NATIVE_PREFIX := $(NATIVE_OUT_DIR)/toolchain
CROSS_PREFIX := $(CROSS_OUT_DIR)/toolchain
FINAL_PREFIX := $(FINAL_OUT_DIR)/toolchain

NATIVE_SYSROOT := $(NATIVE_OUT_DIR)/sysroot
CROSS_SYSROOT := $(CROSS_OUT_DIR)/sysroot
FINAL_SYSROOT := $(FINAL_OUT_DIR)/sysroot

# Fixed-length placeholder rpath for reproducibility (patchelf will replace with $ORIGIN-relative path)
RPATH_PLACEHOLDER := /XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Fixed-length symlink path for dynamic linker - ensures identical ELF section sizes regardless of build directory
# The actual symlink is created before building native toolchain and points to the real ld-linux
INTERP_SYMLINK := /tmp/ld-shim-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

# Rule to create the interpreter symlink (used for NATIVE toolchain)
# This creates a fixed-length path that points to the real dynamic linker
$(NATIVE_BUILD_DIR)/.interp-symlink.installed: $(NATIVE_BUILD_DIR)/.glibc.installed
	@REAL_INTERP=$$(find $(NATIVE_SYSROOT)/usr/lib -name "ld-linux-*.so.*" -type f | head -n 1); \
	if [ -n "$$REAL_INTERP" ]; then \
		ln -sfn "$$REAL_INTERP" "$(INTERP_SYMLINK)"; \
		echo "Created interpreter symlink: $(INTERP_SYMLINK) -> $$REAL_INTERP"; \
	fi
	touch $@

include $(PROJECT_ROOT)/mk/*.mk

# Static dependency chain using semantic stages
# Aliasing causes edges to collapse when stages are equivalent:
# - Case 1 (native): FINAL=CROSS=NATIVE → chain: NATIVE→BOOTSTRAP
# - Case 2 (cross):  CROSS=NATIVE       → chain: FINAL→NATIVE→BOOTSTRAP
# - Case 3 (Canadian): all distinct     → chain: FINAL→CROSS→NATIVE→BOOTSTRAP

# NATIVE stage: built by BOOTSTRAP (always applies)
$(NATIVE_BUILD_DIR)/.binutils.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
$(NATIVE_BUILD_DIR)/.binutils.compiled: $(NATIVE_BUILD_DIR)/.interp-symlink.installed
$(NATIVE_BUILD_DIR)/.glibc.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed

$(NATIVE_BUILD_DIR)/.gcc.configured: $(NATIVE_BUILD_DIR)/.glibc.installed

# CROSS stage: built by NATIVE (only when CROSS != NATIVE, i.e., HOST != BUILD)
ifneq ($(HOST),$(BUILD))
$(CROSS_BUILD_DIR)/.binutils.configured: $(NATIVE_BUILD_DIR)/.gcc.installed
$(CROSS_BUILD_DIR)/.gcc-stage1.configured: $(NATIVE_BUILD_DIR)/.gcc.installed
$(CROSS_BUILD_DIR)/.glibc.configured: $(CROSS_BUILD_DIR)/.gcc-stage1.installed
$(CROSS_BUILD_DIR)/.gcc.configured: $(CROSS_BUILD_DIR)/.glibc.installed
endif

# FINAL stage: built by CROSS (only when FINAL_BUILD_DIR != CROSS_BUILD_DIR)
ifneq ($(FINAL_BUILD_DIR),$(CROSS_BUILD_DIR))
$(FINAL_BUILD_DIR)/.binutils.configured: $(CROSS_BUILD_DIR)/.gcc.installed
$(FINAL_BUILD_DIR)/.gcc.configured: $(FINAL_BUILD_DIR)/.glibc.installed

# When HOST==TARGET (native compiler for HOST), use CROSS gcc to build FINAL glibc
# since CROSS gcc targets HOST which equals TARGET. No need for gcc-stage1.
# When HOST!=TARGET (cross-compiler), need gcc-stage1 that targets TARGET.
ifeq ($(HOST),$(TARGET))
$(FINAL_BUILD_DIR)/.glibc.configured: $(CROSS_BUILD_DIR)/.gcc.installed
else
$(FINAL_BUILD_DIR)/.gcc-stage1.configured: $(CROSS_BUILD_DIR)/.gcc.installed
$(FINAL_BUILD_DIR)/.gcc-stage1.compiled: $(FINAL_BUILD_DIR)/.glibc-headers.installed
$(FINAL_BUILD_DIR)/.glibc.configured: $(FINAL_BUILD_DIR)/.gcc-stage1.installed
endif
endif

# Host-sysroot symlink for ALL toolchains
# For native compilers (HOST == TARGET): host-sysroot → sysroot
# For cross-compilers (HOST != TARGET): host-sysroot → ../../$(NATIVE_TOOLCHAIN_NAME)/sysroot
# This allows ld-linux-shim to always use host-sysroot to find the HOST glibc
ifeq ($(HOST_TRIPLE),$(TARGET_TRIPLE))
$(FINAL_BUILD_DIR)/.host-sysroot.installed: $(FINAL_BUILD_DIR)/.gcc.installed
	ln -sfn sysroot $(FINAL_PREFIX)/host-sysroot
	touch $@
else
$(FINAL_BUILD_DIR)/.host-sysroot.installed: $(NATIVE_BUILD_DIR)/.glibc.installed $(FINAL_BUILD_DIR)/.gcc.installed
	ln -sfn ../../$(NATIVE_TOOLCHAIN_NAME)/sysroot $(FINAL_PREFIX)/host-sysroot
	touch $@
endif

TOOLCHAIN_DEPS := $(FINAL_BUILD_DIR)/.gcc.installed $(FINAL_BUILD_DIR)/.glibc.installed $(FINAL_BUILD_DIR)/.binutils.installed $(FINAL_BUILD_DIR)/.ld-linux-shim.installed $(FINAL_BUILD_DIR)/.host-sysroot.installed

# Archive naming: <host-os-arch>-<target-triple>-<toolchain-name>.tar.gz
# e.g., aarch64-linux-x86_64-linux-gnu-gcc-15.1.0.tar.gz (runs on aarch64-linux, targets x86_64-linux-gnu)
# Sysroot: <target-triple>-<toolchain-name>-sysroot.tar.gz

# Helper: convert os/arch to arch-os (e.g., linux/aarch64 -> aarch64-linux)
os_arch_to_os_arch = $(word 2,$(subst /, ,$(1)))-$(word 1,$(subst /, ,$(1)))
BUILD_OS_ARCH := $(call os_arch_to_os_arch,$(BUILD))
HOST_OS_ARCH := $(call os_arch_to_os_arch,$(HOST))

# NATIVE: runs on BUILD, targets BUILD
NATIVE_TOOLCHAIN_TARBALL := $(DIST_DIR)/$(BUILD_OS_ARCH)-$(BUILD_TRIPLE)-$(TOOLCHAIN_NAME).tar.gz
NATIVE_SYSROOT_TARBALL := $(DIST_DIR)/$(BUILD_TRIPLE)-$(TOOLCHAIN_NAME)-sysroot.tar.gz

# CROSS: runs on BUILD, targets HOST (only when HOST != BUILD)
CROSS_TOOLCHAIN_TARBALL := $(DIST_DIR)/$(BUILD_OS_ARCH)-$(HOST_TRIPLE)-$(TOOLCHAIN_NAME).tar.gz
CROSS_SYSROOT_TARBALL := $(DIST_DIR)/$(HOST_TRIPLE)-$(TOOLCHAIN_NAME)-sysroot.tar.gz

# FINAL: runs on HOST, targets TARGET
FINAL_TOOLCHAIN_TARBALL := $(DIST_DIR)/$(HOST_OS_ARCH)-$(TARGET_TRIPLE)-$(TOOLCHAIN_NAME).tar.gz
FINAL_SYSROOT_TARBALL := $(DIST_DIR)/$(TARGET_TRIPLE)-$(TOOLCHAIN_NAME)-sysroot.tar.gz

# Collect all tarballs to build (avoid duplicates when stages collapse)
ALL_TARBALLS := $(NATIVE_TOOLCHAIN_TARBALL) $(NATIVE_SYSROOT_TARBALL)
ifneq ($(HOST),$(BUILD))
ALL_TARBALLS += $(CROSS_TOOLCHAIN_TARBALL)
ifneq ($(HOST_TRIPLE),$(BUILD_TRIPLE))
ALL_TARBALLS += $(CROSS_SYSROOT_TARBALL)
endif
endif
ifneq ($(FINAL_BUILD_DIR),$(CROSS_BUILD_DIR))
ALL_TARBALLS += $(FINAL_TOOLCHAIN_TARBALL)
ifneq ($(TARGET_TRIPLE),$(HOST_TRIPLE))
ALL_TARBALLS += $(FINAL_SYSROOT_TARBALL)
endif
endif

.DEFAULT_GOAL := all

.PHONY: all toolchain download clean test-parallel

all: $(ALL_TARBALLS)

toolchain: $(FINAL_BUILD_DIR)/.toolchain

$(FINAL_BUILD_DIR)/.toolchain: $(TOOLCHAIN_DEPS)
	$(PROJECT_ROOT)/script/make-reloc.sh $(FINAL_PREFIX)
	touch $@

# NATIVE host-sysroot symlink (native compiler, so host-sysroot → sysroot)
$(NATIVE_BUILD_DIR)/.host-sysroot.installed: $(NATIVE_BUILD_DIR)/.gcc.installed
	ln -sfn sysroot $(NATIVE_PREFIX)/host-sysroot
	touch $@

# NATIVE tarballs
$(NATIVE_BUILD_DIR)/.toolchain: $(NATIVE_BUILD_DIR)/.gcc.installed $(NATIVE_BUILD_DIR)/.glibc.installed $(NATIVE_BUILD_DIR)/.binutils.installed $(NATIVE_BUILD_DIR)/.ld-linux-shim.installed $(NATIVE_BUILD_DIR)/.host-sysroot.installed
	$(PROJECT_ROOT)/script/make-reloc.sh $(NATIVE_PREFIX)
	touch $@

$(NATIVE_TOOLCHAIN_TARBALL): $(NATIVE_BUILD_DIR)/.toolchain | $(DIST_DIR)
	tar -czf $@ -C $(dir $(NATIVE_PREFIX)) $(notdir $(NATIVE_PREFIX))

$(NATIVE_SYSROOT_TARBALL): $(NATIVE_BUILD_DIR)/.toolchain | $(DIST_DIR)
	tar -czf $@ -C $(dir $(NATIVE_SYSROOT)) $(notdir $(NATIVE_SYSROOT))

# CROSS tarballs (only when HOST != BUILD)
ifneq ($(HOST),$(BUILD))
# CROSS is a cross-compiler (runs on BUILD, targets HOST)
# host-sysroot → NATIVE sysroot (where the BUILD glibc lives)
$(CROSS_BUILD_DIR)/.host-sysroot.installed: $(NATIVE_BUILD_DIR)/.glibc.installed $(CROSS_BUILD_DIR)/.gcc.installed
	ln -sfn ../../$(NATIVE_TOOLCHAIN_NAME)/sysroot $(CROSS_PREFIX)/host-sysroot
	touch $@

$(CROSS_BUILD_DIR)/.toolchain: $(CROSS_BUILD_DIR)/.gcc.installed $(CROSS_BUILD_DIR)/.glibc.installed $(CROSS_BUILD_DIR)/.binutils.installed $(CROSS_BUILD_DIR)/.ld-linux-shim.installed $(CROSS_BUILD_DIR)/.host-sysroot.installed
	$(PROJECT_ROOT)/script/make-reloc.sh $(CROSS_PREFIX)
	touch $@

$(CROSS_TOOLCHAIN_TARBALL): $(CROSS_BUILD_DIR)/.toolchain | $(DIST_DIR)
	tar -czf $@ -C $(dir $(CROSS_PREFIX)) $(notdir $(CROSS_PREFIX))

$(CROSS_SYSROOT_TARBALL): $(CROSS_BUILD_DIR)/.toolchain | $(DIST_DIR)
	tar -czf $@ -C $(dir $(CROSS_SYSROOT)) $(notdir $(CROSS_SYSROOT))
endif

# FINAL tarballs (only when FINAL != CROSS)
ifneq ($(FINAL_BUILD_DIR),$(CROSS_BUILD_DIR))
$(FINAL_TOOLCHAIN_TARBALL): $(FINAL_BUILD_DIR)/.toolchain | $(DIST_DIR)
	tar -czf $@ -C $(dir $(FINAL_PREFIX)) $(notdir $(FINAL_PREFIX))

# Only define FINAL sysroot rule if it differs from CROSS sysroot (avoid duplicate rules)
ifneq ($(TARGET_TRIPLE),$(HOST_TRIPLE))
$(FINAL_SYSROOT_TARBALL): $(FINAL_BUILD_DIR)/.toolchain | $(DIST_DIR)
	tar -czf $@ -C $(dir $(FINAL_SYSROOT)) $(notdir $(FINAL_SYSROOT))
endif
endif

$(DIST_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR) $(OUT_DIR)

clean-bootstrap:
	rm -rf $(BUILD_DIR)/bootstrap $(OUT_DIR)/bootstrap

clean-downloads:
	rm -rf $(DL_DIR)

clean-sources:
	rm -rf $(SRC_DIR)
