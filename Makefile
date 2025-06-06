CONFIG ?= config.mk

MKTOOLCHAIN_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

export LC_ALL := C.UTF-8

ifeq ($(filter -j%,$(MAKEFLAGS)),)
  MAKEFLAGS += -j$(shell nproc)
endif

include $(CONFIG)


BUILD := $(shell uname -s | tr A-Z a-z)/$(shell uname -m)
HOST ?= $(BUILD)
TARGET ?= $(HOST)

# Convert os/arch to GNU triple (e.g., linux/aarch64 -> aarch64-linux-gnu)
os_arch_to_triple = $(word 2,$(subst /, ,$(1)))-$(word 1,$(subst /, ,$(1)))-gnu
BUILD_TRIPLE := $(call os_arch_to_triple,$(BUILD))
HOST_TRIPLE := $(call os_arch_to_triple,$(HOST))
TARGET_TRIPLE := $(call os_arch_to_triple,$(TARGET))

BUILD_ROOT ?= .
BUILD_DIR := $(BUILD_ROOT)/build
OUT_DIR := $(BUILD_ROOT)/out
DL_DIR := $(BUILD_ROOT)/dl
SRC_DIR := $(BUILD_ROOT)/src

IS_NATIVE := $(and $(filter $(HOST),$(BUILD)),$(filter $(TARGET),$(BUILD)))

# BB = bootstrap build, B = target build
BB := $(BUILD_DIR)/bootstrap/$(TOOLCHAIN_NAME)
B := $(BUILD_DIR)/$(HOST)/$(TOOLCHAIN_NAME)

# BO = bootstrap out, O = target out
BO := $(OUT_DIR)/bootstrap/$(TOOLCHAIN_NAME)
O := $(OUT_DIR)/$(HOST)/$(TOOLCHAIN_NAME)

$(DL_DIR) $(SRC_DIR):
	mkdir -p $@

$(BB) $(B):
	mkdir -p $@

$(BO)/toolchain $(O)/toolchain $(O)/sysroot:
	mkdir -p $@

$(BO)/toolchain/sysroot: $(O)/sysroot $(BO)/toolchain
	ln -sfn ../../../$(HOST)/$(TOOLCHAIN_NAME)/sysroot $@

$(O)/toolchain/sysroot: $(O)/sysroot
	ln -sfn ../sysroot $@

.DEFAULT_GOAL := toolchain

.PHONY: toolchain bootstrap download clean test-parallel bootstrap-binutils bootstrap-binutils-configure bootstrap-binutils-build

toolchain: $(O)/.toolchain.done

bootstrap: $(BO)/.bootstrap.done

# Test target for parallel builds
test-parallel: $(DL_DIR) $(SRC_DIR) $(BUILD_DIR) $(OUT_DIR)
	@echo "Testing parallel infrastructure..."
	@echo "Build system: $(BUILD)"
	@echo "Build triple: $(BUILD_TRIPLE)"
	@echo "Host: $(HOST)"
	@echo "Target: $(TARGET)"
	@echo "Is native: $(IS_NATIVE)"
	@echo "Bootstrap build dir: $(BB)"
	@echo "Target build dir: $(B)"
	@echo "Config: $(CONFIG)"
	@echo "GCC Version: $(GCC_VERSION)"

$(BO)/.bootstrap.done: $(BO)/.libstdc++.installed | $(BO)
	@echo "Bootstrap toolchain complete"
	@touch $@

$(O)/.toolchain.done: $(O)/.glibc.installed $(O)/.sysroot.done | $(O)
	@echo "Target toolchain complete"
	@touch $@


bootstrap-binutils: $(BB)/.binutils.installed
bootstrap-binutils: CFLAGS := -g0 -O2 -ffile-prefix-map=$(abspath $(SRC_DIR))=. -ffile-prefix-map=$(abspath $(BB))=.
bootstrap-binutils: CXXFLAGS := -g0 -O2 -ffile-prefix-map=$(abspath $(SRC_DIR))=. -ffile-prefix-map=$(abspath $(BB))=.
bootstrap-binutils: SOURCE_DATE_EPOCH := $(shell cat $(BB)/binutils/src/.timestamp 2>/dev/null || echo 1)

BINUTILS_CONFIG := \
	--host=$(BUILD_TRIPLE) \
	--target=$(BUILD_TRIPLE) \
	--prefix= \
	--with-sysroot=/sysroot \
	--program-prefix=$(BUILD_TRIPLE)- \
	--disable-shared \
	--enable-new-dtags \
	--disable-werror

$(BB)/binutils/src: $(BB)/.binutils.linked
$(BB)/binutils/build:
	mkdir -p $@

$(BB)/.binutils.linked: $(SRC_DIR)/binutils-$(BINUTILS_VERSION) $(BB)/binutils
	ln -sfn $(abspath $<) $(BB)/binutils/src
	touch $@

$(BB)/.binutils.configured: $(BB)/binutils/src $(BB)/binutils/build $(BO)/toolchain/sysroot
	@echo "Configuring bootstrap binutils..."
	cd $(BB)/binutils/build && \
		CFLAGS="$(CFLAGS)" \
		CXXFLAGS="$(CXXFLAGS)" \
		SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		../src/configure $(BINUTILS_CONFIG)
	touch $@

$(BB)/.binutils.compiled: $(BB)/.binutils.configured
	@echo "Building bootstrap binutils..."
	cd $(BB)/binutils/build && $(MAKE)
	touch $@

$(BB)/.binutils.installed: $(BB)/.binutils.compiled
	@echo "Installing bootstrap binutils..."
	cd $(BB)/binutils/build && \
		TMPDIR=$$(mktemp -d) && \
		$(MAKE) DESTDIR="$$TMPDIR" install && \
		find "$$TMPDIR" -exec touch -h -d "@$(SOURCE_DATE_EPOCH)" {} \; && \
		$(MKTOOLCHAIN_ROOT)script/replace-binutils-hardlinks.sh "$$TMPDIR" "$(BUILD_TRIPLE)" && \
		cp -a "$$TMPDIR"/* $(abspath $(BO))/toolchain/ && \
		rm -rf "$$TMPDIR"
	touch $@

$(BB)/.gcc.installed: $(BB)/.binutils.installed | $(BB)
	@echo "Building bootstrap GCC..."
	@sleep 2  # Simulate build time
	@touch $@

$(BB)/.linux-headers.installed: | $(BB)
	@echo "Installing Linux headers..."
	@sleep 1  # Simulate build time
	@touch $@

$(BB)/.glibc.installed: $(BB)/.gcc.installed $(BB)/.linux-headers.installed | $(BB)
	@echo "Building bootstrap glibc..."
	@sleep 2  # Simulate build time
	@touch $@

$(BO)/.libstdc++.installed: $(BB)/.glibc.installed | $(BO)
	@echo "Building bootstrap libstdc++..."
	@sleep 1  # Simulate build time
	@touch $@

$(B)/.binutils.installed: $(BO)/.bootstrap.done | $(B)
	@echo "Building target binutils..."
	@sleep 1  # Simulate build time
	@touch $@

$(B)/.gcc.installed: $(B)/.binutils.installed $(BO)/.bootstrap.done | $(B)
	@echo "Building target GCC..."
	@sleep 2  # Simulate build time
	@touch $@

$(O)/.glibc.installed: $(B)/.gcc.installed | $(O)
	@echo "Building target glibc..."
	@sleep 2  # Simulate build time
	@touch $@

$(O)/.sysroot.done: $(O)/.glibc.installed $(B)/.linux-headers.installed | $(O)
	@echo "Assembling sysroot..."
	@sleep 1  # Simulate sysroot assembly
	@touch $@

$(B)/.linux-headers.installed: | $(B)
	@echo "Installing Linux headers for target..."
	@sleep 1  # Simulate build time
	@touch $@

download: $(SRC_DIR)/gcc-$(GCC_VERSION) $(SRC_DIR)/binutils-$(BINUTILS_VERSION) $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(SRC_DIR)/linux-$(LINUX_VERSION)

GNU_BASE_URL := https://ftp.gnu.org/gnu
GCC_URL := $(GNU_BASE_URL)/gcc/gcc-$(GCC_VERSION)/gcc-$(GCC_VERSION).tar.gz
BINUTILS_URL := $(GNU_BASE_URL)/binutils/binutils-$(BINUTILS_VERSION).tar.gz
GLIBC_URL := $(GNU_BASE_URL)/glibc/glibc-$(GLIBC_VERSION).tar.gz

LINUX_MAJOR := $(shell echo $(LINUX_VERSION) | cut -d. -f1)
LINUX_URL := https://cdn.kernel.org/pub/linux/kernel/v$(LINUX_MAJOR).x/linux-$(LINUX_VERSION).tar.gz

$(SRC_DIR)/gcc-$(GCC_VERSION) $(SRC_DIR)/binutils-$(BINUTILS_VERSION) $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(SRC_DIR)/linux-$(LINUX_VERSION): | $(SRC_DIR) $(DL_DIR)
	$(eval PACKAGE_LC := $(shell echo $(notdir $@) | sed 's/\([^-]*\)-.*/\1/'))
	$(eval PACKAGE := $(shell echo $(PACKAGE_LC) | tr a-z A-Z))
	$(eval URL := $($(PACKAGE)_URL))
	$(eval SHA256 := $($(PACKAGE)_SHA256))
	$(eval TARBALL := $(DL_DIR)/$(notdir $@).tar.gz)
	@if ! [ -f "$(TARBALL)" ] || ! echo "$(SHA256) $(TARBALL)" | sha256sum -c - >/dev/null 2>&1; then \
		[ -f "$(TARBALL)" ] && rm -f "$(TARBALL)"; \
		echo "Downloading $(PACKAGE)..."; \
		curl -L "$(URL)" -o "$(TARBALL)" && \
		printf "Verifying $(PACKAGE) checksum... "; \
		echo "$(SHA256) $(TARBALL)" | sha256sum -c - >/dev/null && echo "verified"; \
	fi
	@echo "Extracting $(TARBALL)..."
	@tar -xf "$(TARBALL)" -C "$(SRC_DIR)"
	@timestamp=$$(tar -tvf "$(TARBALL)" | awk '{print $$4" "$$5}' | sort -r | head -1 | xargs -I {} date -d "{}" +%s 2>/dev/null || echo 1); \
	echo "$$timestamp" > "$@/.timestamp"
	@if [ -d "$(MKTOOLCHAIN_ROOT)patches/$(notdir $@)" ]; then \
		for patch in $(MKTOOLCHAIN_ROOT)patches/$(notdir $@)/*; do \
			[ -f "$$patch" ] && echo "Applying: $$(basename $$patch)" && (cd "$@" && patch -p1 < "$$patch"); \
		done; \
	fi
	@if echo "$(notdir $@)" | grep -q "^gcc-"; then \
		echo "Downloading GCC dependencies..."; \
		(cd "$@" && ./contrib/download_prerequisites); \
	fi

clean:
	rm -rf $(BUILD_DIR) $(OUT_DIR)

clean-bootstrap:
	rm -rf $(BUILD_DIR)/bootstrap $(OUT_DIR)/bootstrap

clean-downloads:
	rm -rf $(DL_DIR)

clean-sources:
	rm -rf $(SRC_DIR)
