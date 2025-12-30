define binutils_base_vars
$1: CFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=. -frandom-seed=0
$1: CXXFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=. -frandom-seed=0
$1: SOURCE_DATE_EPOCH = $$(shell cat $(SRC_DIR)/binutils-$(BINUTILS_VERSION)/.timestamp 2>/dev/null || echo 1)
endef

# Not used for bootstrap
define binutils_ldflags_vars
$1: LDFLAGS = --sysroot=$$(SYSROOT) -Wl,-rpath=$(RPATH_PLACEHOLDER) -Wl,--dynamic-linker=$(INTERP_SYMLINK) -Wl,--build-id=none
endef

$(eval $(call binutils_base_vars,$(BOOTSTRAP_BUILD_DIR)/.binutils.%))
$(eval $(call binutils_base_vars,$(NATIVE_BUILD_DIR)/.binutils.%))
$(eval $(call binutils_base_vars,$(CROSS_BUILD_DIR)/.binutils.%))
$(eval $(call binutils_base_vars,$(FINAL_BUILD_DIR)/.binutils.%))

$(eval $(call binutils_ldflags_vars,$(NATIVE_BUILD_DIR)/.binutils.%))
$(eval $(call binutils_ldflags_vars,$(CROSS_BUILD_DIR)/.binutils.%))
$(eval $(call binutils_ldflags_vars,$(FINAL_BUILD_DIR)/.binutils.%))

$(BOOTSTRAP_BUILD_DIR)/.binutils.%: LDFLAGS :=

$(BOOTSTRAP_BUILD_DIR)/.binutils.%: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.binutils.%: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.binutils.%: PREFIX := $(BOOTSTRAP_PREFIX)
$(BOOTSTRAP_BUILD_DIR)/.binutils.%: SYSROOT := $(NATIVE_SYSROOT)
$(BOOTSTRAP_BUILD_DIR)/.binutils.%: PATH := $(ORIG_PATH)

$(NATIVE_BUILD_DIR)/.binutils.%: HOST_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.binutils.%: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.binutils.%: PREFIX := $(NATIVE_PREFIX)
$(NATIVE_BUILD_DIR)/.binutils.%: SYSROOT := $(NATIVE_SYSROOT)
$(NATIVE_BUILD_DIR)/.binutils.%: PATH := $(NATIVE_PREFIX)/bin:$(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)

$(CROSS_BUILD_DIR)/.binutils.%: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.binutils.%: TARGET_TRIPLE := $(HOST_TRIPLE)
$(CROSS_BUILD_DIR)/.binutils.%: PREFIX := $(CROSS_PREFIX)
$(CROSS_BUILD_DIR)/.binutils.%: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.binutils.%: PATH := $(NATIVE_PREFIX)/bin:$(ORIG_PATH)

$(FINAL_BUILD_DIR)/.binutils.%: HOST_TRIPLE := $(HOST_TRIPLE)
$(FINAL_BUILD_DIR)/.binutils.%: TARGET_TRIPLE := $(TARGET_TRIPLE)
$(FINAL_BUILD_DIR)/.binutils.%: PREFIX := $(FINAL_PREFIX)
$(FINAL_BUILD_DIR)/.binutils.%: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.binutils.%: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)

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
