%/.gcc.installed: CFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=.
%/.gcc.installed: CXXFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=.
%/.gcc.installed: SOURCE_DATE_EPOCH = $(shell cat $(SRC_DIR)/gcc-$(GCC_VERSION)/.timestamp 2>/dev/null || echo 1)

%/.gcc.installed: SYSROOT_SYMLINK = ../sysroot
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: SYSROOT_SYMLINK := ../../../../$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/sysroot

# LDFLAGS only for native builds (BUILD=HOST=TARGET) to link against our sysroot
# Cross-compilers don't need this as build tools must run on build machine
%/.gcc.installed: LDFLAGS :=
%/.gcc.compiled: LDFLAGS :=
$(BUILD_BUILD_DIR)/.gcc.installed: DYNAMIC_LINKER = $(shell find $(SYSROOT)/usr/lib -name "ld-linux-*.so.*" -type f -printf "%f\n" | head -n 1)
$(BUILD_BUILD_DIR)/.gcc.installed: LDFLAGS = -L$(SYSROOT)/usr/lib -Wl,-rpath=$(SYSROOT)/usr/lib -Wl,--dynamic-linker=$(SYSROOT)/usr/lib/$(DYNAMIC_LINKER)
$(BUILD_BUILD_DIR)/.gcc.compiled: DYNAMIC_LINKER = $(shell find $(SYSROOT)/usr/lib -name "ld-linux-*.so.*" -type f -printf "%f\n" | head -n 1)
$(BUILD_BUILD_DIR)/.gcc.compiled: LDFLAGS = -L$(SYSROOT)/usr/lib -Wl,-rpath=$(SYSROOT)/usr/lib -Wl,--dynamic-linker=$(SYSROOT)/usr/lib/$(DYNAMIC_LINKER)

# TARGET gcc: runs on BUILD, targets TARGET (cross-compiler)
$(TARGET_BUILD_DIR)/.gcc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(TARGET_BUILD_DIR)/.gcc.installed: PREFIX := $(TARGET_PREFIX)
$(TARGET_BUILD_DIR)/.gcc.installed: SYSROOT := $(TARGET_SYSROOT)
$(TARGET_BUILD_DIR)/.gcc.installed: PATH := $(BUILD_PREFIX)/bin:$(ORIG_PATH)
# When cross-compiling (HOST_ARCH != TARGET_ARCH), need to specify where target binutils are
$(TARGET_BUILD_DIR)/.gcc.installed: TARGET_BUILD_TIME_TOOLS := $(if $(filter-out $(HOST_ARCH),$(TARGET_ARCH)),--with-build-time-tools=$(TARGET_PREFIX)/$(TARGET_TRIPLE)/bin)
$(TARGET_BUILD_DIR)/.gcc.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG) $(TARGET_BUILD_TIME_TOOLS)

# Bootstrap-style gcc for TARGET (used to install glibc headers before building full gcc)
# Only needed when cross-compiling (HOST_ARCH != TARGET_ARCH)
$(TARGET_BUILD_DIR)/.bootstrap-gcc.installed: PREFIX := $(TARGET_PREFIX)
$(TARGET_BUILD_DIR)/.bootstrap-gcc.installed: SYSROOT := $(TARGET_SYSROOT)
$(TARGET_BUILD_DIR)/.bootstrap-gcc.installed: PATH := $(CROSS_PREFIX)/bin:$(BUILD_PREFIX)/bin:$(ORIG_PATH)
$(TARGET_BUILD_DIR)/.bootstrap-gcc.installed: TARGET_BUILD_TIME_TOOLS := $(if $(filter-out $(HOST_ARCH),$(TARGET_ARCH)),--with-build-time-tools=$(TARGET_PREFIX)/$(TARGET_TRIPLE)/bin)
$(TARGET_BUILD_DIR)/.bootstrap-gcc.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_BOOTSTRAP_CONFIG) $(TARGET_BUILD_TIME_TOOLS)

$(CROSS_BUILD_DIR)/.gcc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.gcc.installed: TARGET_TRIPLE := $(HOST_TRIPLE)
$(CROSS_BUILD_DIR)/.gcc.installed: PREFIX := $(CROSS_PREFIX)
$(CROSS_BUILD_DIR)/.gcc.installed: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.gcc.installed: PATH := $(BUILD_PREFIX)/bin:$(ORIG_PATH)
# Canadian Cross needs target binutils from CROSS_PREFIX (already built by binutils.mk)
$(CROSS_BUILD_DIR)/.gcc.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG) \
	--with-build-time-tools=$(CROSS_PREFIX)/$(HOST_TRIPLE)/bin

$(BUILD_BUILD_DIR)/.gcc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BUILD_BUILD_DIR)/.gcc.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(BUILD_BUILD_DIR)/.gcc.installed: PREFIX := $(BUILD_PREFIX)
$(BUILD_BUILD_DIR)/.gcc.installed: SYSROOT := $(BUILD_SYSROOT)
$(BUILD_BUILD_DIR)/.gcc.installed: PATH := $(BUILD_PREFIX)/bin:$(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
# If we're using the BOOTSTRAP compiler, make sure we still use BUILD binutils.
$(BUILD_BUILD_DIR)/.gcc.installed: BUILD_TIME_TOOLS := $(if $(wildcard $(BUILD_PREFIX)/bin/$(TARGET_TRIPLE)-gcc),,--with-build-time-tools=$(BUILD_PREFIX)/$(TARGET_TRIPLE)/bin)
$(BUILD_BUILD_DIR)/.gcc.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG) $(BUILD_TIME_TOOLS)

$(BUILD_BUILD_DIR)/.gcc.compiled: SYSROOT := $(BUILD_SYSROOT)
$(BUILD_BUILD_DIR)/.gcc.compiled: PATH := $(BUILD_PREFIX)/bin:$(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)

$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: PREFIX := $(BOOTSTRAP_PREFIX)
# there's no bootstrap sysroot
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: SYSROOT := $(BUILD_SYSROOT)
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_BOOTSTRAP_CONFIG)

# gcc-stage1: Bootstrap-style gcc for TARGET architecture (used to build glibc before full gcc)
$(TARGET_BUILD_DIR)/.gcc-stage1.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(TARGET_BUILD_DIR)/.gcc-stage1.installed: PREFIX := $(TARGET_PREFIX)
$(TARGET_BUILD_DIR)/.gcc-stage1.installed: SYSROOT := $(TARGET_SYSROOT)
$(TARGET_BUILD_DIR)/.gcc-stage1.installed: PATH := $(TARGET_PREFIX)/bin:$(BUILD_PREFIX)/bin:$(ORIG_PATH)
$(TARGET_BUILD_DIR)/.gcc-stage1.installed: LDFLAGS :=
# When cross-compiling (HOST_ARCH != TARGET_ARCH), need to specify where target binutils are
$(TARGET_BUILD_DIR)/.gcc-stage1.installed: TARGET_BUILD_TIME_TOOLS := $(if $(filter-out $(HOST_ARCH),$(TARGET_ARCH)),--with-build-time-tools=$(TARGET_PREFIX)/$(TARGET_TRIPLE)/bin)
$(TARGET_BUILD_DIR)/.gcc-stage1.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_BOOTSTRAP_CONFIG) $(TARGET_BUILD_TIME_TOOLS)
$(TARGET_BUILD_DIR)/.gcc-stage1.installed: SYSROOT_SYMLINK = ../sysroot


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
	--disable-fixincludes

.PRECIOUS: %/.gcc.configured %/.gcc.compiled %/.gcc.installed

# When cross-compiling (HOST != TARGET), TARGET gcc needs glibc headers installed first
ifneq ($(HOST_ARCH),$(TARGET_ARCH))
$(TARGET_BUILD_DIR)/.gcc.configured: $(TARGET_BUILD_DIR)/.glibc-headers.installed
endif

# Full TARGET gcc needs glibc installed to build libgcc_s.so
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
		$(MAKE) configure-gcc && \
		sed -i 's/ --with-build-sysroot=[^"]*//; s/ --with-build-time-tools=[^"]*//' gcc/configargs.h && \
		$(MAKE) LDFLAGS="$(LDFLAGS)" LIBGCC2_DEBUG_CFLAGS=-g0 'AR_CREATE_FOR_TARGET=$$(AR_FOR_TARGET) Drc'
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
%/.gcc-stage1.installed: CFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=.
%/.gcc-stage1.installed: CXXFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=.
%/.gcc-stage1.installed: SOURCE_DATE_EPOCH = $(shell cat $(SRC_DIR)/gcc-$(GCC_VERSION)/.timestamp 2>/dev/null || echo 1)

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
		$(MAKE) all-gcc && \
		$(MAKE) -C $(TARGET_TRIPLE)/libgcc CFLAGS="-g0 -O2" LIBGCC2_DEBUG_CFLAGS=-g0 'AR_CREATE_FOR_TARGET=$$(AR_FOR_TARGET) Drc'
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
