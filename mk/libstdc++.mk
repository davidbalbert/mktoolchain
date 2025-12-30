# libstdc++ is only built independently for the bootstrap toolchain.
$(BOOTSTRAP_BUILD_DIR)/.libstdc++.%: PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
$(BOOTSTRAP_BUILD_DIR)/.libstdc++.%: CFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BOOTSTRAP_BUILD_DIR)=. -frandom-seed=0
$(BOOTSTRAP_BUILD_DIR)/.libstdc++.%: CXXFLAGS := -g0 -O2 -ffile-prefix-map=$(SRC_DIR)=. -ffile-prefix-map=$(BOOTSTRAP_BUILD_DIR)=. -frandom-seed=0
$(BOOTSTRAP_BUILD_DIR)/.libstdc++.%: SOURCE_DATE_EPOCH = $(shell cat $(SRC_DIR)/gcc-$(GCC_VERSION)/.timestamp 2>/dev/null || echo 1)

LIBSTDCXX_CONFIG = \
	--prefix=/usr \
	--host=$(BUILD_TRIPLE) \
	--disable-multilib \
	--disable-nls \
	--disable-libstdcxx-pch \
	--with-gxx-include-dir=/usr/include/c++/$(GCC_VERSION)

.PRECIOUS: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.configured $(BOOTSTRAP_BUILD_DIR)/.libstdc++.compiled

$(BOOTSTRAP_BUILD_DIR)/.libstdc++.configured: $(SRC_DIR)/gcc-$(GCC_VERSION) $(BOOTSTRAP_BUILD_DIR)/.gcc.installed $(BOOTSTRAP_BUILD_DIR)/.glibc.installed
	mkdir -p $(BOOTSTRAP_BUILD_DIR)/libstdc++/build $(NATIVE_SYSROOT)
	ln -sfn $(SRC_DIR)/gcc-$(GCC_VERSION)/libstdc++-v3 $(BOOTSTRAP_BUILD_DIR)/libstdc++/src
	cd $(BOOTSTRAP_BUILD_DIR)/libstdc++/build && \
		CFLAGS="$(CFLAGS)" \
		CXXFLAGS="$(CXXFLAGS)" \
		SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		../src/configure $(LIBSTDCXX_CONFIG)
	touch $@

$(BOOTSTRAP_BUILD_DIR)/.libstdc++.compiled: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.configured
	cd $(BOOTSTRAP_BUILD_DIR)/libstdc++/build && $(MAKE)
	touch $@

$(BOOTSTRAP_BUILD_DIR)/.libstdc++.installed: $(BOOTSTRAP_BUILD_DIR)/.libstdc++.compiled
	cd $(BOOTSTRAP_BUILD_DIR)/libstdc++/build && \
		TMPDIR=$$(mktemp -d) && \
		$(MAKE) DESTDIR="$$TMPDIR" install && \
		find "$$TMPDIR" -exec touch -h -d "@$(SOURCE_DATE_EPOCH)" {} \; && \
		cp -a "$$TMPDIR"/* $(NATIVE_SYSROOT)/ && \
		rm -rf "$$TMPDIR"
	touch $@
