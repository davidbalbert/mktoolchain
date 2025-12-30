GLIBC_BASE_FLAGS := -O2 -g0 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BUILD_ROOT)=. -frandom-seed=0
%/.glibc.installed: SOURCE_DATE_EPOCH = $(shell cat $(SRC_DIR)/glibc-$(GLIBC_VERSION)/.timestamp 2>/dev/null || echo 1)

# FINAL glibc target-specific variables
# When HOST==TARGET (native compiler), use CROSS gcc to build FINAL glibc since
# CROSS gcc runs on BUILD and targets HOST which equals TARGET
# When HOST!=TARGET, use FINAL gcc-stage1 which runs on BUILD and targets TARGET
ifeq ($(HOST),$(TARGET))
$(FINAL_BUILD_DIR)/.glibc.configured: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.glibc.configured: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.glibc.compiled: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.glibc.installed: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.glibc.installed: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.glibc.installed: $(FINAL_BUILD_DIR)/.linux-headers.installed
else
$(FINAL_BUILD_DIR)/.glibc.configured: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.glibc.configured: PATH := $(FINAL_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.glibc.installed: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.glibc.installed: PATH := $(FINAL_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.glibc.installed: $(FINAL_BUILD_DIR)/.linux-headers.installed
endif

# CROSS glibc target-specific variables (runs on BUILD, targets HOST)
$(CROSS_BUILD_DIR)/.glibc.configured: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.glibc.configured: TARGET_TRIPLE := $(call os_arch_to_triple,$(HOST))
$(CROSS_BUILD_DIR)/.glibc.configured: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.glibc.configured: PATH := $(CROSS_PREFIX)/bin:$(ORIG_PATH)
$(CROSS_BUILD_DIR)/.glibc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(CROSS_BUILD_DIR)/.glibc.installed: TARGET_TRIPLE := $(call os_arch_to_triple,$(HOST))
$(CROSS_BUILD_DIR)/.glibc.installed: SYSROOT := $(CROSS_SYSROOT)
$(CROSS_BUILD_DIR)/.glibc.installed: PATH := $(CROSS_PREFIX)/bin:$(ORIG_PATH)
$(CROSS_BUILD_DIR)/.glibc.installed: $(CROSS_BUILD_DIR)/.linux-headers.installed

# NATIVE glibc target-specific variables
$(NATIVE_BUILD_DIR)/.glibc.configured: HOST_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.glibc.configured: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.glibc.configured: SYSROOT := $(NATIVE_SYSROOT)
$(NATIVE_BUILD_DIR)/.glibc.configured: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
$(NATIVE_BUILD_DIR)/.glibc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.glibc.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(NATIVE_BUILD_DIR)/.glibc.installed: SYSROOT := $(NATIVE_SYSROOT)
$(NATIVE_BUILD_DIR)/.glibc.installed: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
$(NATIVE_BUILD_DIR)/.glibc.installed: $(NATIVE_BUILD_DIR)/.linux-headers.installed

# BOOTSTRAP glibc target-specific variables
$(BOOTSTRAP_BUILD_DIR)/.glibc.configured: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.glibc.configured: TARGET_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.glibc.configured: SYSROOT := $(NATIVE_SYSROOT)
$(BOOTSTRAP_BUILD_DIR)/.glibc.configured: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: HOST_TRIPLE := $(BUILD_TRIPLE)
$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: TARGET_TRIPLE := $(BUILD_TRIPLE)
# there's no bootstrap sysroot
$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: SYSROOT := $(NATIVE_SYSROOT)
$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
# BOOTSTRAP glibc gets installed in NATIVE sysroot so we don't have to build a separate
# set of kernel headers for build.
$(BOOTSTRAP_BUILD_DIR)/.glibc.installed: $(NATIVE_BUILD_DIR)/.linux-headers.installed

GLIBC_CONFIG = \
	--prefix=/usr \
	--host=$(TARGET_TRIPLE) \
	--enable-kernel=$(GLIBC_KERNEL_VERSION) \
	--with-headers=$(SYSROOT)/usr/include \
	libc_cv_slibdir=/usr/lib

.PRECIOUS: %/.glibc.configured %/.glibc.compiled %/.glibc.installed %/.glibc-headers.installed

# Install just glibc headers (needed before building gcc with libgcc in Canadian Cross)
# Uses the bootstrap-style cross-gcc (without libgcc) to configure glibc and install headers
# When HOST==TARGET (native compiler), use CROSS gcc which already targets HOST
# When HOST!=TARGET (cross-compiler), need bootstrap-gcc that targets TARGET
ifeq ($(HOST),$(TARGET))
$(FINAL_BUILD_DIR)/.glibc-headers.installed: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.glibc-headers.installed: PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.glibc-headers.installed: $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(FINAL_BUILD_DIR)/.linux-headers.installed $(CROSS_BUILD_DIR)/.gcc.installed
	mkdir -p $(FINAL_BUILD_DIR)/glibc-headers/build $(SYSROOT)/usr/include
	ln -sfn $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(FINAL_BUILD_DIR)/glibc-headers/src
	cd $(FINAL_BUILD_DIR)/glibc-headers/build && \
		../src/configure $(GLIBC_CONFIG)
	cd $(FINAL_BUILD_DIR)/glibc-headers/build && $(MAKE) install-headers DESTDIR=$(SYSROOT)
	touch $(SYSROOT)/usr/include/gnu/stubs.h
	touch $@
else
$(FINAL_BUILD_DIR)/.glibc-headers.installed: SYSROOT := $(FINAL_SYSROOT)
$(FINAL_BUILD_DIR)/.glibc-headers.installed: PATH := $(FINAL_PREFIX)/bin:$(CROSS_PREFIX)/bin:$(ORIG_PATH)
$(FINAL_BUILD_DIR)/.glibc-headers.installed: $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(FINAL_BUILD_DIR)/.linux-headers.installed $(FINAL_BUILD_DIR)/.bootstrap-gcc.installed
	mkdir -p $(FINAL_BUILD_DIR)/glibc-headers/build $(SYSROOT)/usr/include
	ln -sfn $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(FINAL_BUILD_DIR)/glibc-headers/src
	cd $(FINAL_BUILD_DIR)/glibc-headers/build && \
		../src/configure $(GLIBC_CONFIG)
	cd $(FINAL_BUILD_DIR)/glibc-headers/build && $(MAKE) install-headers DESTDIR=$(SYSROOT)
	touch $(SYSROOT)/usr/include/gnu/stubs.h
	touch $@
endif

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

# BOOTSTRAP and NATIVE glibc need CXX= to force glibc to build links-dso-program-c
# (C version) instead of links-dso-program (C++ version). The C++ version requires
# -lgcc_s which doesn't exist with bootstrap GCC (built with --disable-shared).
$(BOOTSTRAP_BUILD_DIR)/.glibc.compiled: $(BOOTSTRAP_BUILD_DIR)/.glibc.configured
	cd $(BOOTSTRAP_BUILD_DIR)/glibc/build && $(MAKE) CXX=
	touch $@

$(NATIVE_BUILD_DIR)/.glibc.compiled: $(NATIVE_BUILD_DIR)/.glibc.configured
	cd $(NATIVE_BUILD_DIR)/glibc/build && $(MAKE) CXX=
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
