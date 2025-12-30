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

# FINAL stage: built by CROSS (only when FINAL != CROSS, i.e., HOST != TARGET)
ifneq ($(HOST),$(TARGET))
$(FINAL_BUILD_DIR)/.binutils.configured: $(CROSS_BUILD_DIR)/.gcc.installed
$(FINAL_BUILD_DIR)/.gcc-stage1.configured: $(CROSS_BUILD_DIR)/.gcc.installed
$(FINAL_BUILD_DIR)/.gcc-stage1.compiled: $(FINAL_BUILD_DIR)/.glibc-headers.installed
$(FINAL_BUILD_DIR)/.glibc.configured: $(FINAL_BUILD_DIR)/.gcc-stage1.installed
$(FINAL_BUILD_DIR)/.gcc.configured: $(FINAL_BUILD_DIR)/.glibc.installed
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

TOOLCHAIN_DEPS := $(FINAL_BUILD_DIR)/.gcc.installed $(FINAL_BUILD_DIR)/.glibc.installed $(FINAL_BUILD_DIR)/.ld-linux-shim.installed $(FINAL_BUILD_DIR)/.host-sysroot.installed

.DEFAULT_GOAL := toolchain

.PHONY: toolchain download clean test-parallel

toolchain: $(FINAL_BUILD_DIR)/.toolchain

$(FINAL_BUILD_DIR)/.toolchain: $(TOOLCHAIN_DEPS)
	$(PROJECT_ROOT)/script/make-reloc.sh $(FINAL_PREFIX)
	touch $@

clean:
	rm -rf $(BUILD_DIR) $(OUT_DIR)

clean-bootstrap:
	rm -rf $(BUILD_DIR)/bootstrap $(OUT_DIR)/bootstrap

clean-downloads:
	rm -rf $(DL_DIR)

clean-sources:
	rm -rf $(SRC_DIR)
