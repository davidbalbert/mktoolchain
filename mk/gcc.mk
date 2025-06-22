bootstrap-gcc: $(BOOTSTRAP_BUILD_DIR)/.gcc.installed
gcc: $(TARGET_BUILD_DIR)/.gcc.installed

%/.gcc.installed: CFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$*=.
%/.gcc.installed: CXXFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$*=.
%/.gcc.installed: SOURCE_DATE_EPOCH = $(shell cat $(SRC_DIR)/gcc-$(GCC_VERSION)/.timestamp 2>/dev/null || echo 1)

%/.gcc.installed: SYSROOT_SYMLINK = ../sysroot
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: SYSROOT_SYMLINK := ../../../../$(BUILD)/$(BUILD_TOOLCHAIN_NAME)/sysroot

%/.gcc.installed: DYNAMIC_LINKER = $(shell find $(SYSROOT)/usr/lib -name "ld-linux-*.so.*" -type f -printf "%f\n" | head -n 1 || (echo "Error: No dynamic linker found in $(SYSROOT)/usr/lib" >&2; exit 1))
%/.gcc.installed: LDFLAGS = -L$(SYSROOT)/usr/lib -Wl,-rpath=$(SYSROOT)/usr/lib -Wl,--dynamic-linker=$(SYSROOT)/usr/lib/$(DYNAMIC_LINKER)
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: LDFLAGS :=

$(TARGET_BUILD_DIR)/.gcc.installed: PREFIX := $(TARGET_PREFIX)
$(TARGET_BUILD_DIR)/.gcc.installed: SYSROOT := $(SYSROOT)
$(TARGET_BUILD_DIR)/.gcc.installed: PATH := $(CROSS_PREFIX)/bin:$(BUILD_PREFIX)/bin:$(ORIG_PATH)
$(TARGET_BUILD_DIR)/.gcc.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG)

$(CROSS_BUILD_DIR)/.gcc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.gcc.installed: TARGET_TRIPLE := $(HOST_TRIPLE)
$(CROSS_BUILD_DIR)/.gcc.installed: PREFIX := $(CROSS_PREFIX)
$(CROSS_BUILD_DIR)/.gcc.installed: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.gcc.installed: PATH := $(BUILD_PREFIX)/bin:$(ORIG_PATH)
$(CROSS_BUILD_DIR)/.gcc.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG)

$(BUILD_BUILD_DIR)/.gcc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BUILD_BUILD_DIR)/.gcc.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(BUILD_BUILD_DIR)/.gcc.installed: PREFIX := $(BUILD_PREFIX)
$(BUILD_BUILD_DIR)/.gcc.installed: SYSROOT := $(BUILD_SYSROOT)
$(BUILD_BUILD_DIR)/.gcc.installed: PATH := $(BUILD_PREFIX)/bin:$(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
# If we're using the BOOTSTRAP compiler, make sure we still use BUILD binutils.
$(BUILD_BUILD_DIR)/.gcc.installed: BUILD_TIME_TOOLS := $(if $(wildcard $(BUILD_PREFIX)/bin/$(TARGET_TRIPLE)-gcc),,--with-build-time-tools=$(BUILD_PREFIX)/$(TARGET_TRIPLE)/bin)
$(BUILD_BUILD_DIR)/.gcc.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_FINAL_CONFIG) $(BUILD_TIME_TOOLS)

$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: PREFIX := $(BOOTSTRAP_PREFIX)
# there's no bootstrap sysroot
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: SYSROOT := $(BUILD_SYSROOT)
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
$(BOOTSTRAP_BUILD_DIR)/.gcc.installed: GCC_CONFIG = $(GCC_BASE_CONFIG) $(GCC_BOOTSTRAP_CONFIG)


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

.PRECIOUS: %/.gcc.configured %/.gcc.compiled

%/.gcc.configured: $(SRC_DIR)/gcc-$(GCC_VERSION) %/.binutils.installed
	mkdir -p $*/gcc/build $(PREFIX) $(SYSROOT)
	ln -sfn $(SRC_DIR)/gcc-$(GCC_VERSION) $*/gcc/src
	ln -sfn $(SYSROOT_SYMLINK) $(PREFIX)/sysroot
	cd $*/gcc/build && \
		CFLAGS="$(CFLAGS)" \
		CXXFLAGS="$(CXXFLAGS)" \
		LDFLAGS="$(LDFLAGS)" \
		SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		../src/configure $(GCC_CONFIG)
	touch $@

%/.gcc.compiled: %/.gcc.configured
	cd $*/gcc/build && \
		$(MAKE) configure-gcc && \
		sed -i 's/ --with-build-sysroot=[^ ]*//' gcc/configargs.h && \
		$(MAKE)
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
