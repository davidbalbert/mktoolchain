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

include $(PROJECT_ROOT)/mk/*.mk

# Conditional dependency chains based on build scenario

# Phase dependency chains
# Case 1: Native build (BUILD = HOST = TARGET)
ifeq ($(BUILD)_$(HOST)_$(TARGET),$(BUILD)_$(BUILD)_$(BUILD))
  $(TARGET_BUILD_DIR)/.binutils.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
# Case 2: Cross-compiler for build system (BUILD = HOST ≠ TARGET)
else ifeq ($(HOST),$(BUILD))
  $(BUILD_BUILD_DIR)/.binutils.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
  $(TARGET_BUILD_DIR)/.binutils.configured: $(BUILD_BUILD_DIR)/.glibc.installed
# Case 3: Native or cross-compilation to different host (BUILD ≠ HOST)
else
  $(BUILD_BUILD_DIR)/.binutils.configured: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed
  $(CROSS_BUILD_DIR)/.binutils.configured: $(BUILD_BUILD_DIR)/.glibc.installed
  $(TARGET_BUILD_DIR)/.binutils.configured: $(CROSS_BUILD_DIR)/.glibc.installed
endif

.PHONY: download clean test-parallel bootstrap-binutils bootstrap-gcc bootstrap-glibc bootstrap-libstdc++ linux-headers binutils gcc glibc

clean:
	rm -rf $(BUILD_DIR) $(OUT_DIR)

clean-bootstrap:
	rm -rf $(BUILD_DIR)/bootstrap $(OUT_DIR)/bootstrap

clean-downloads:
	rm -rf $(DL_DIR)

clean-sources:
	rm -rf $(SRC_DIR)
