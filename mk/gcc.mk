define gcc_base_vars
$1: CFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=. -frandom-seed=0
$1: CXXFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=. -frandom-seed=0
$1: SOURCE_DATE_EPOCH = $$(shell cat $(SRC_DIR)/gcc-$(GCC_VERSION)/.timestamp 2>/dev/null || echo 1)
$1: SYSROOT_SYMLINK := ../sysroot
endef

# Full LDFLAGS for final toolchain gcc (not bootstrap/stage1)
define gcc_ldflags_vars
$1: LDFLAGS = --sysroot=$$(SYSROOT) -Wl,-rpath=$(RPATH_PLACEHOLDER) -Wl,--dynamic-linker=$(INTERP_SYMLINK) -Wl,--build-id=none
endef

$(eval $(call gcc_base_vars,$(BOOTSTRAP_BUILD_DIR)/.gcc.%))
$(eval $(call gcc_base_vars,$(NATIVE_BUILD_DIR)/.gcc.%))
$(eval $(call gcc_base_vars,$(CROSS_BUILD_DIR)/.gcc.%))
$(eval $(call gcc_base_vars,$(FINAL_BUILD_DIR)/.gcc.%))
$(eval $(call gcc_base_vars,$(FINAL_BUILD_DIR)/.bootstrap-gcc.%))
$(eval $(call gcc_base_vars,$(CROSS_BUILD_DIR)/.gcc-stage1.%))
$(eval $(call gcc_base_vars,$(FINAL_BUILD_DIR)/.gcc-stage1.%))

$(eval $(call gcc_ldflags_vars,$(NATIVE_BUILD_DIR)/.gcc.%))
$(eval $(call gcc_ldflags_vars,$(CROSS_BUILD_DIR)/.gcc.%))
$(eval $(call gcc_ldflags_vars,$(FINAL_BUILD_DIR)/.gcc.%))

$(BOOTSTRAP_BUILD_DIR)/.gcc.%: LDFLAGS :=
$(FINAL_BUILD_DIR)/.bootstrap-gcc.%: LDFLAGS :=
$(CROSS_BUILD_DIR)/.gcc-stage1.%: LDFLAGS :=
$(FINAL_BUILD_DIR)/.gcc-stage1.%: LDFLAGS :=

$(BOOTSTRAP_BUILD_DIR)/.gcc.%: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.gcc.%: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.gcc.%: PREFIX := $(BOOTSTRAP_PREFIX)
$(BOOTSTRAP_BUILD_DIR)/.gcc.%: SYSROOT := $(NATIVE_SYSROOT)
$(BOOTSTRAP_BUILD_DIR)/.gcc.%: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
$(BOOTSTRAP_BUILD_DIR)/.gcc.%: SYSROOT_SYMLINK := ../../../../$(BUILD)/$(NATIVE_TOOLCHAIN_NAME)/sysroot
$(BOOTSTRAP_BUILD_DIR)/.gcc.%: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_BOOTSTRAP_CONFIG)

$(NATIVE_BUILD_DIR)/.gcc.%: HOST_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.gcc.%: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.gcc.%: PREFIX := $(NATIVE_PREFIX)
$(NATIVE_BUILD_DIR)/.gcc.%: SYSROOT := $(NATIVE_SYSROOT)
$(NATIVE_BUILD_DIR)/.gcc.%: PATH := $(NATIVE_PREFIX)/bin:$(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
$(NATIVE_BUILD_DIR)/.gcc.%: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG) $(NATIVE_BUILD_TIME_TOOLS) \
	--with-build-time-tools=$(NATIVE_PREFIX)/$(TARGET_TRIPLE)/bin

$(CROSS_BUILD_DIR)/.gcc.%: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.gcc.%: TARGET_TRIPLE := $(HOST_TRIPLE)
$(CROSS_BUILD_DIR)/.gcc.%: PREFIX := $(CROSS_PREFIX)
$(CROSS_BUILD_DIR)/.gcc.%: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.gcc.%: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(CROSS_BUILD_DIR)/.gcc.%: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG) \
	--with-build-time-tools=$(CROSS_PREFIX)/$(HOST_TRIPLE)/bin

# FINAL gcc (runs on HOST, targets TARGET)
# When HOST==TARGET (Canadian Cross for native compiler):
#   - Use CROSS gcc to compile (produces HOST binaries)
#   - Use CROSS binutils during build
# When HOST!=TARGET (cross-compiler):
#   - Use NATIVE gcc to build (produces BUILD binaries that run on BUILD)
#   - HOST_TRIPLE must be BUILD_TRIPLE since the compiler runs on BUILD
$(FINAL_BUILD_DIR)/.gcc.%: PREFIX := $(FINAL_PREFIX)
$(FINAL_BUILD_DIR)/.gcc.%: SYSROOT := $(FINAL_SYSROOT)

ifeq ($(HOST),$(TARGET))
$(FINAL_BUILD_DIR)/.gcc.%: HOST_TRIPLE := $(HOST_TRIPLE)
$(FINAL_BUILD_DIR)/.gcc.%: TARGET_TRIPLE := $(TARGET_TRIPLE)
$(FINAL_BUILD_DIR)/.gcc.%: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.gcc.%: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG) \
	--with-build-time-tools=$(CROSS_PREFIX)/$(TARGET_TRIPLE)/bin
else
$(FINAL_BUILD_DIR)/.gcc.%: HOST_TRIPLE := $(BUILD_TRIPLE)
$(FINAL_BUILD_DIR)/.gcc.%: TARGET_TRIPLE := $(TARGET_TRIPLE)
$(FINAL_BUILD_DIR)/.gcc.%: PATH := $(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.gcc.%: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG) \
	--with-build-time-tools=$(FINAL_PREFIX)/$(TARGET_TRIPLE)/bin
endif

# Bootstrap-style gcc for FINAL (used to install glibc headers before building full gcc)
# Only needed when cross-compiling (HOST_ARCH != TARGET_ARCH)
$(FINAL_BUILD_DIR)/.bootstrap-gcc.%: PREFIX := $(FINAL_PREFIX)
$(FINAL_BUILD_DIR)/.bootstrap-gcc.%: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.bootstrap-gcc.%: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.bootstrap-gcc.%: FINAL_BUILD_TIME_TOOLS := $(if $(filter-out $(HOST_ARCH),$(TARGET_ARCH)),--with-build-time-tools=$(FINAL_PREFIX)/$(TARGET_TRIPLE)/bin)
$(FINAL_BUILD_DIR)/.bootstrap-gcc.%: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_BOOTSTRAP_CONFIG) $(FINAL_BUILD_TIME_TOOLS)

# CROSS gcc-stage1 (runs on BUILD, targets HOST)
$(CROSS_BUILD_DIR)/.gcc-stage1.%: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.gcc-stage1.%: TARGET_TRIPLE := $(HOST_TRIPLE)
$(CROSS_BUILD_DIR)/.gcc-stage1.%: PREFIX := $(CROSS_PREFIX)
$(CROSS_BUILD_DIR)/.gcc-stage1.%: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.gcc-stage1.%: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(CROSS_BUILD_DIR)/.gcc-stage1.%: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_BOOTSTRAP_CONFIG)

# FINAL gcc-stage1 (runs on BUILD, targets TARGET)
$(FINAL_BUILD_DIR)/.gcc-stage1.%: HOST_TRIPLE := $(BUILD_TRIPLE)
$(FINAL_BUILD_DIR)/.gcc-stage1.%: PREFIX := $(FINAL_PREFIX)
$(FINAL_BUILD_DIR)/.gcc-stage1.%: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.gcc-stage1.%: PATH := $(FINAL_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.gcc-stage1.%: FINAL_BUILD_TIME_TOOLS := $(if $(filter-out $(HOST_ARCH),$(TARGET_ARCH)),--with-build-time-tools=$(FINAL_PREFIX)/$(TARGET_TRIPLE)/bin)
$(FINAL_BUILD_DIR)/.gcc-stage1.%: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_BOOTSTRAP_CONFIG) $(FINAL_BUILD_TIME_TOOLS)

GCC_BASE_CONFIG = \
	--host=$(HOST_TRIPLE) \
	--target=$(TARGET_TRIPLE) \
	--prefix= \
	--with-sysroot=/sysroot \
	--with-build-sysroot=$(SYSROOT) \
	--enable-default-pie \
	--enable-default-ssp \
	--disable-multilib \
	--disable-bootstrap \
	--enable-languages=c,c++

GCC_BOOTSTRAP_CONFIG = \
	--with-glibc-version=$(GLIBC_VERSION) \
	--with-newlib \
	--disable-nls \
	--disable-shared \
	--disable-threads \
	--disable-libatomic \
	--disable-libgomp \
	--disable-libquadmath \
	--disable-libssp \
	--disable-libvtv \
	--disable-libstdcxx \
	--without-headers \
	--with-gxx-include-dir=/sysroot/usr/include/c++/$(GCC_VERSION)

GCC_FINAL_CONFIG = \
	--enable-host-pie \
	--disable-fixincludes \
	--disable-libcc1

.PRECIOUS: %/.gcc.configured %/.gcc.compiled %/.gcc.installed

# When cross-compiling (HOST != TARGET), FINAL gcc needs glibc headers installed first
ifneq ($(HOST_ARCH),$(TARGET_ARCH))
$(FINAL_BUILD_DIR)/.gcc.configured: $(FINAL_BUILD_DIR)/.glibc-headers.installed
endif

# Full FINAL gcc needs glibc installed to build libgcc_s.so
# This dependency is set conditionally in Makefile based on build type

%/.gcc.configured: $(SRC_DIR)/gcc-$(GCC_VERSION) %/.binutils.installed
	mkdir -p $*/gcc/build $(PREFIX) $(SYSROOT)
	ln -sfn $(SRC_DIR)/gcc-$(GCC_VERSION) $*/gcc/src
	ln -sfn $(SYSROOT_SYMLINK) $(PREFIX)/sysroot
	cd $*/gcc/build && \
		CFLAGS="$(CFLAGS)" \
		CXXFLAGS="$(CXXFLAGS)" \
		SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		../src/configure $(GCC_CONFIG)
	touch $@

%/.gcc.compiled: %/.gcc.configured
	cd $*/gcc/build && \
		$(MAKE) configure-gcc configure-target-libgcc && \
		sed -i 's/ --with-build-sysroot=[^"]*//; s/ --with-build-time-tools=[^"]*//' gcc/configargs.h && \
		sed -i '/^checksum-options:/,/move-if-change/{s|echo "\$$(LINKER).*"|echo "deterministic"|g}' gcc/Makefile && \
		rm -f gcc/checksum-options && \
		if [ -f libcc1/libtool ]; then sed -i 's/^hardcode_into_libs=yes$$/hardcode_into_libs=no/' libcc1/libtool; fi && \
		$(MAKE) LDFLAGS="$(LDFLAGS)" LIBGCC2_DEBUG_CFLAGS=-g0
	touch $@

%/.gcc.installed: %/.gcc.compiled
	cd $*/gcc/build && \
		TMPDIR=$$(mktemp -d) && \
		$(MAKE) DESTDIR="$$TMPDIR" install && \
		find "$$TMPDIR" -exec touch -h -d "@$(SOURCE_DATE_EPOCH)" {} \; && \
		mkdir -p $(PREFIX) && \
		cp -a "$$TMPDIR"/* $(PREFIX)/ && \
		rm -rf "$$TMPDIR"
	touch $@

# Bootstrap-style gcc rules (for installing glibc headers before building full gcc)
# Uses separate build directory to avoid conflicts with full gcc build
.PRECIOUS: %/.bootstrap-gcc.configured %/.bootstrap-gcc.compiled %/.bootstrap-gcc.installed

%/.bootstrap-gcc.configured: $(SRC_DIR)/gcc-$(GCC_VERSION) %/.binutils.installed
	mkdir -p $*/bootstrap-gcc/build $(PREFIX) $(SYSROOT)
	ln -sfn $(SRC_DIR)/gcc-$(GCC_VERSION) $*/bootstrap-gcc/src
	ln -sfn $(SYSROOT_SYMLINK) $(PREFIX)/sysroot
	cd $*/bootstrap-gcc/build && \
		CFLAGS="$(CFLAGS)" \
		CXXFLAGS="$(CXXFLAGS)" \
		SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		../src/configure $(GCC_CONFIG)
	touch $@

%/.bootstrap-gcc.compiled: %/.bootstrap-gcc.configured
	cd $*/bootstrap-gcc/build && \
		$(MAKE) configure-gcc && \
		sed -i 's/ --with-build-sysroot=[^"]*//; s/ --with-build-time-tools=[^"]*//' gcc/configargs.h && \
		$(MAKE) all-gcc LDFLAGS="$(LDFLAGS)"
	touch $@

%/.bootstrap-gcc.installed: %/.bootstrap-gcc.compiled
	cd $*/bootstrap-gcc/build && \
		TMPDIR=$$(mktemp -d) && \
		$(MAKE) DESTDIR="$$TMPDIR" install-gcc && \
		find "$$TMPDIR" -exec touch -h -d "@$(SOURCE_DATE_EPOCH)" {} \; && \
		mkdir -p $(PREFIX) && \
		cp -a "$$TMPDIR"/* $(PREFIX)/ && \
		rm -rf "$$TMPDIR"
	touch $@

# gcc-stage1 rules (bootstrap-style gcc for TARGET, builds gcc + libgcc only)
.PRECIOUS: %/.gcc-stage1.configured %/.gcc-stage1.compiled %/.gcc-stage1.installed

%/.gcc-stage1.configured: $(SRC_DIR)/gcc-$(GCC_VERSION) %/.binutils.installed
	mkdir -p $*/gcc-stage1/build $(PREFIX) $(SYSROOT)
	ln -sfn $(SRC_DIR)/gcc-$(GCC_VERSION) $*/gcc-stage1/src
	ln -sfn $(SYSROOT_SYMLINK) $(PREFIX)/sysroot
	cd $*/gcc-stage1/build && \
		CFLAGS="$(CFLAGS)" \
		CXXFLAGS="$(CXXFLAGS)" \
		SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		../src/configure $(GCC_CONFIG)
	touch $@

%/.gcc-stage1.compiled: %/.gcc-stage1.configured
	cd $*/gcc-stage1/build && \
		$(MAKE) configure-gcc && \
		sed -i 's/ --with-build-sysroot=[^"]*//; s/ --with-build-time-tools=[^"]*//' gcc/configargs.h && \
		$(MAKE) all-gcc configure-target-libgcc && \
		$(MAKE) -C $(TARGET_TRIPLE)/libgcc CFLAGS="-g0 -O2" LIBGCC2_DEBUG_CFLAGS=-g0
	touch $@

%/.gcc-stage1.installed: %/.gcc-stage1.compiled
	cd $*/gcc-stage1/build && \
		TMPDIR=$$(mktemp -d) && \
		$(MAKE) DESTDIR="$$TMPDIR" install-gcc install-target-libgcc && \
		find "$$TMPDIR" -exec touch -h -d "@$(SOURCE_DATE_EPOCH)" {} \; && \
		mkdir -p $(PREFIX) && \
		cp -a "$$TMPDIR"/* $(PREFIX)/ && \
		rm -rf "$$TMPDIR"
	touch $@
