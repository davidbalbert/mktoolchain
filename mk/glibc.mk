GLIBC_BASE_FLAGS := -O2 -g -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=.
%/.glibc.installed: SOURCE_DATE_EPOCH = $(shell cat $(SRC_DIR)/glibc-$(GLIBC_VERSION)/.timestamp 2>/dev/null || echo 1)

$(TARGET_BUILD_DIR)/.glibc.installed: SYSROOT := $(TARGET_SYSROOT)
$(TARGET_BUILD_DIR)/.glibc.installed: PATH := $(TARGET_PREFIX)/bin:$(ORIG_PATH)
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

.PRECIOUS: %/.glibc.configured %/.glibc.compiled %/.glibc.installed %/.glibc-headers.installed

# Install just glibc headers (needed before building gcc with libgcc in Canadian Cross)
# Uses the bootstrap-style cross-gcc (without libgcc) to configure glibc and install headers
$(TARGET_BUILD_DIR)/.glibc-headers.installed: SYSROOT := $(TARGET_SYSROOT)
$(TARGET_BUILD_DIR)/.glibc-headers.installed: PATH := $(TARGET_PREFIX)/bin:$(CROSS_PREFIX)/bin:$(ORIG_PATH)
$(TARGET_BUILD_DIR)/.glibc-headers.installed: $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(TARGET_BUILD_DIR)/.linux-headers.installed $(TARGET_BUILD_DIR)/.bootstrap-gcc.installed
	mkdir -p $(TARGET_BUILD_DIR)/glibc-headers/build $(SYSROOT)/usr/include
	ln -sfn $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(TARGET_BUILD_DIR)/glibc-headers/src
	cd $(TARGET_BUILD_DIR)/glibc-headers/build && \
		../src/configure $(GLIBC_CONFIG)
	cd $(TARGET_BUILD_DIR)/glibc-headers/build && $(MAKE) install-headers DESTDIR=$(SYSROOT)
	touch $(SYSROOT)/usr/include/gnu/stubs.h
	touch $@

$(BOOTSTRAP_BUILD_DIR)/.glibc.configured: $(BOOTSTRAP_BUILD_DIR)/.gcc.installed
# BUILD, CROSS, and TARGET glibc dependencies are set conditionally in Makefile based on build type
# (In Case 1, all three are equal and use bootstrap gcc instead of build gcc)

%/.glibc.configured: $(SRC_DIR)/glibc-$(GLIBC_VERSION)
	mkdir -p $*/glibc/build $(SYSROOT)
	ln -sfn $(SRC_DIR)/glibc-$(GLIBC_VERSION) $*/glibc/src
	cd $*/glibc/build && \
		CFLAGS="$(GLIBC_BASE_FLAGS) -ffile-prefix-map=$*/glibc=." \
		CXXFLAGS="$(GLIBC_BASE_FLAGS) -ffile-prefix-map=$*/glibc=." \
		SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		../src/configure $(GLIBC_CONFIG)
	touch $@

# Bootstrap glibc needs CXX= to force glibc to build links-dso-program-c (C version)
# instead of links-dso-program (C++ version). The C++ version requires -lgcc_s which
# doesn't exist with bootstrap GCC (built with --disable-shared).
$(BOOTSTRAP_BUILD_DIR)/.glibc.compiled: $(BOOTSTRAP_BUILD_DIR)/.glibc.configured
	cd $(BOOTSTRAP_BUILD_DIR)/glibc/build && $(MAKE) CXX=
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
