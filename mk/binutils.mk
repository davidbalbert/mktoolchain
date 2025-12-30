%/.binutils.installed: CFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=. -frandom-seed=0
%/.binutils.installed: CXXFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=. -frandom-seed=0
%/.binutils.installed: SOURCE_DATE_EPOCH = $(shell cat $(SRC_DIR)/binutils-$(BINUTILS_VERSION)/.timestamp 2>/dev/null || echo 1)

# LDFLAGS for bootstrap - disable build-id to ensure reproducibility
$(BOOTSTRAP_BUILD_DIR)/.binutils.installed: LDFLAGS := -Wl,--build-id=none
$(BOOTSTRAP_BUILD_DIR)/.binutils.compiled: LDFLAGS := -Wl,--build-id=none

# LDFLAGS only for native builds (BUILD=HOST=TARGET) to link against our sysroot
# Cross-compilers don't need this as build tools must run on build machine
%/.binutils.installed: LDFLAGS :=
%/.binutils.compiled: LDFLAGS :=
$(NATIVE_BUILD_DIR)/.binutils.installed: LDFLAGS = -L$(SYSROOT)/usr/lib -Wl,-rpath=$(RPATH_PLACEHOLDER) -Wl,--dynamic-linker=$(INTERP_SYMLINK)
$(NATIVE_BUILD_DIR)/.binutils.compiled: LDFLAGS = -L$(SYSROOT)/usr/lib -Wl,-rpath=$(RPATH_PLACEHOLDER) -Wl,--dynamic-linker=$(INTERP_SYMLINK)

$(FINAL_BUILD_DIR)/.binutils.installed: HOST_TRIPLE := $(HOST_TRIPLE)
$(FINAL_BUILD_DIR)/.binutils.installed: TARGET_TRIPLE := $(TARGET_TRIPLE)
$(FINAL_BUILD_DIR)/.binutils.installed: PREFIX := $(FINAL_PREFIX)
$(FINAL_BUILD_DIR)/.binutils.installed: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.binutils.installed: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)

# CROSS binutils target-specific variables (runs on BUILD, targets HOST)
$(CROSS_BUILD_DIR)/.binutils.configured: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.binutils.configured: TARGET_TRIPLE := $(call os_arch_to_triple,$(HOST))
$(CROSS_BUILD_DIR)/.binutils.configured: PREFIX := $(CROSS_PREFIX)
$(CROSS_BUILD_DIR)/.binutils.configured: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.binutils.configured: PATH := $(NATIVE_PREFIX)/bin:$(ORIG_PATH)

$(CROSS_BUILD_DIR)/.binutils.compiled: PATH := $(NATIVE_PREFIX)/bin:$(ORIG_PATH)

$(CROSS_BUILD_DIR)/.binutils.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.binutils.installed: TARGET_TRIPLE := $(call os_arch_to_triple,$(HOST))
$(CROSS_BUILD_DIR)/.binutils.installed: PREFIX := $(CROSS_PREFIX)
$(CROSS_BUILD_DIR)/.binutils.installed: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.binutils.installed: PATH := $(NATIVE_PREFIX)/bin:$(ORIG_PATH)

$(NATIVE_BUILD_DIR)/.binutils.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.binutils.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.binutils.installed: PREFIX := $(NATIVE_PREFIX)
$(NATIVE_BUILD_DIR)/.binutils.installed: SYSROOT := $(NATIVE_SYSROOT)
$(NATIVE_BUILD_DIR)/.binutils.installed: PATH := $(NATIVE_PREFIX)/bin:$(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)

$(NATIVE_BUILD_DIR)/.binutils.compiled: SYSROOT := $(NATIVE_SYSROOT)
$(NATIVE_BUILD_DIR)/.binutils.compiled: PATH := $(NATIVE_PREFIX)/bin:$(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)

$(BOOTSTRAP_BUILD_DIR)/.binutils.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.binutils.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.binutils.installed: PREFIX := $(BOOTSTRAP_PREFIX)
# there's no bootstrap sysroot
$(BOOTSTRAP_BUILD_DIR)/.binutils.installed: SYSROOT := $(NATIVE_SYSROOT)
$(BOOTSTRAP_BUILD_DIR)/.binutils.installed: PATH := $(ORIG_PATH)

BINUTILS_CONFIG = \
	--host=$(HOST_TRIPLE) \
	--target=$(TARGET_TRIPLE) \
	--prefix= \
	--with-sysroot=/sysroot \
	--program-prefix=$(TARGET_TRIPLE)- \
	--disable-shared \
	--enable-new-dtags \
	--enable-deterministic-archives \
	--disable-werror \
	--disable-gprofng \
	MAKEINFO=true

.PRECIOUS: %/.binutils.configured %/.binutils.compiled %/.binutils.installed

%/.binutils.configured: $(SRC_DIR)/binutils-$(BINUTILS_VERSION)
	mkdir -p $*/binutils/build
	ln -sfn $(SRC_DIR)/binutils-$(BINUTILS_VERSION) $*/binutils/src
	cd $*/binutils/build && \
		CFLAGS="$(CFLAGS)" \
		CXXFLAGS="$(CXXFLAGS)" \
		SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		../src/configure $(BINUTILS_CONFIG)
	touch $@

%/.binutils.compiled: %/.binutils.configured
	cd $*/binutils/build && $(MAKE) MAKEINFO=true LDFLAGS="$(LDFLAGS)"
	touch $@

%/.binutils.installed: %/.binutils.compiled
	cd $*/binutils/build && \
		TMPDIR=$$(mktemp -d) && \
		$(MAKE) DESTDIR="$$TMPDIR" install && \
		find "$$TMPDIR" -exec touch -h -d "@$(SOURCE_DATE_EPOCH)" {} \; && \
		$(PROJECT_ROOT)/script/replace-binutils-hardlinks.sh "$$TMPDIR" "$(TARGET_TRIPLE)" && \
		find "$$TMPDIR" -name "*.la" -type f -delete && \
		mkdir -p $(PREFIX) && \
		cp -a "$$TMPDIR"/* $(PREFIX)/ && \
		rm -rf "$$TMPDIR"
	touch $@
