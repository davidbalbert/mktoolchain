bootstrap-glibc: $(BOOTSTRAP_BUILD_DIR)/.glibc.installed
glibc: $(TARGET_BUILD_DIR)/.glibc.installed

%/.glibc.installed: CFLAGS := -O2 -g -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$*=.
%/.glibc.installed: CXXFLAGS := -O2 -g -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$*=.
%/.glibc.installed: SOURCE_DATE_EPOCH = $(shell cat $(SRC_DIR)/glibc-$(GLIBC_VERSION)/.timestamp 2>/dev/null || echo 1)

$(TARGET_BUILD_DIR)/.glibc.installed: SYSROOT := $(TARGET_SYSROOT)
$(TARGET_BUILD_DIR)/.glibc.installed: PATH := $(CROSS_PREFIX)/bin:$(ORIG_PATH)
$(TARGET_BUILD_DIR)/.glibc.installed: $(TARGET_BUILD_DIR)/.linux-headers.installed

$(CROSS_BUILD_DIR)/.glibc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.glibc.installed: TARGET_TRIPLE := $(HOST_TRIPLE)
$(CROSS_BUILD_DIR)/.glibc.installed: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.glibc.installed: PATH := $(CROSS_PREFIX)/bin:$(ORIG_PATH)
$(CROSS_BUILD_DIR)/.glibc.installed: $(CROSS_BUILD_DIR)/.linux-headers.installed

$(BUILD_BUILD_DIR)/.glibc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BUILD_BUILD_DIR)/.glibc.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(BUILD_BUILD_DIR)/.glibc.installed: SYSROOT := $(BUILD_SYSROOT)
$(BUILD_BUILD_DIR)/.glibc.installed: PATH := $(BUILD_PREFIX)/bin:$(ORIG_PATH)
$(BUILD_BUILD_DIR)/.glibc.installed: $(BUILD_BUILD_DIR)/.linux-headers.installed

$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
# there's no bootstrap sysroot
$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: SYSROOT := $(BUILD_SYSROOT)
$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
# BOOTSTRAP glibc gets installed in BUILD sysroot so we don't have to build a separate
# set of kernel headers for build.
$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: $(BUILD_BUILD_DIR)/.linux-headers.installed

GLIBC_CONFIG = \
	--prefix=/usr \
	--host=$(TARGET_TRIPLE) \
	--enable-kernel=$(GLIBC_KERNEL_VERSION) \
	--with-headers=$(SYSROOT)/usr/include \
	libc_cv_slibdir=/usr/lib

.PRECIOUS: %/.glibc.configured %/.glibc.compiled

%/.glibc.configured: $(SRC_DIR)/glibc-$(GLIBC_VERSION) %/.gcc.installed
	mkdir -p $*/glibc/build $(SYSROOT)
	ln -sfn $(SRC_DIR)/glibc-$(GLIBC_VERSION) $*/glibc/src
	cd $*/glibc/build && \
		CFLAGS="$(CFLAGS)" \
		CXXFLAGS="$(CXXFLAGS)" \
		SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		../src/configure $(GLIBC_CONFIG)
	touch $@

%/.glibc.compiled: %/.glibc.configured
	cd $*/glibc/build && $(MAKE)
	touch $@

%/.glibc.installed: %/.glibc.compiled
	cd $*/glibc/build && \
		TMPDIR=$$(mktemp -d) && \
		$(MAKE) DESTDIR="$$TMPDIR" install && \
		find "$$TMPDIR" -exec touch -h -d "@$(SOURCE_DATE_EPOCH)" {} \; && \
		cp -a "$$TMPDIR"/* $(SYSROOT)/ && \
		rm -rf "$$TMPDIR"
	touch $@
