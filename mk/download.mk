download: $(SRC_DIR)/gcc-$(GCC_VERSION) $(SRC_DIR)/binutils-$(BINUTILS_VERSION) $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(SRC_DIR)/linux-$(LINUX_VERSION)

GNU_BASE_URL := https://ftp.gnu.org/gnu
GCC_URL := $(GNU_BASE_URL)/gcc/gcc-$(GCC_VERSION)/gcc-$(GCC_VERSION).tar.gz
BINUTILS_URL := $(GNU_BASE_URL)/binutils/binutils-$(BINUTILS_VERSION).tar.gz
GLIBC_URL := $(GNU_BASE_URL)/glibc/glibc-$(GLIBC_VERSION).tar.gz

LINUX_MAJOR := $(shell echo $(LINUX_VERSION) | cut -d. -f1)
LINUX_URL := https://cdn.kernel.org/pub/linux/kernel/v$(LINUX_MAJOR).x/linux-$(LINUX_VERSION).tar.gz

$(SRC_DIR)/gcc-$(GCC_VERSION) $(SRC_DIR)/binutils-$(BINUTILS_VERSION) $(SRC_DIR)/glibc-$(GLIBC_VERSION) $(SRC_DIR)/linux-$(LINUX_VERSION):
	$(eval PACKAGE_LC := $(shell echo $(notdir $@) | sed 's/\([^-]*\)-.*/\1/'))
	$(eval PACKAGE := $(shell echo $(PACKAGE_LC) | tr a-z A-Z))
	$(eval URL := $($(PACKAGE)_URL))
	$(eval SHA256 := $($(PACKAGE)_SHA256))
	$(eval TARBALL := $(DL_DIR)/$(notdir $@).tar.gz)
	@mkdir -p $(SRC_DIR) $(DL_DIR)
	@if ! [ -f "$(TARBALL)" ] || ! echo "$(SHA256) $(TARBALL)" | sha256sum -c - >/dev/null 2>&1; then \
		[ -f "$(TARBALL)" ] && rm -f "$(TARBALL)"; \
		echo "Downloading $(PACKAGE)..."; \
		curl -sSL "$(URL)" -o "$(TARBALL)" && \
		echo "$(SHA256) $(TARBALL)" | sha256sum -c - >/dev/null && echo "$(PACKAGE) verified"; \
	fi
	@echo "Extracting $(TARBALL)..."
	@tar -xf "$(TARBALL)" -C "$(SRC_DIR)"
	@timestamp=$$(tar -tvf "$(TARBALL)" | awk '{print $$4" "$$5}' | sort -r | head -1 | xargs -I {} date -d "{}" +%s 2>/dev/null || echo 1); \
	echo "$$timestamp" > "$@/.timestamp"
	@if [ -d "$(PROJECT_ROOT)/patches/$(notdir $@)" ]; then \
		for patch in $(PROJECT_ROOT)/patches/$(notdir $@)/*.patch; do \
			[ -f "$$patch" ] && echo "Applying: $$(basename $$patch)" && (cd "$@" && patch -p1 < "$$patch"); \
		done; \
	fi; true
	@if echo "$(notdir $@)" | grep -q "^gcc-"; then \
		echo "Downloading GCC dependencies..."; \
		(cd "$@" && ./contrib/download_prerequisites); \
	fi
