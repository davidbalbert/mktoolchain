# ld-linux-shim build rules
# The shim must run on the same architecture as the toolchain binaries (HOST_ARCH),
# not the target architecture. For native toolchains HOST_ARCH == TARGET_ARCH,
# but for cross-compilers they differ.

LD_LINUX_SHIM_SRC := $(PROJECT_ROOT)/ld-linux-shim
LD_LINUX_SHIM_BUILD := $(TARGET_BUILD_DIR)/ld-linux-shim
LD_LINUX_SHIM_BIN := $(LD_LINUX_SHIM_BUILD)/ld-linux-shim
LD_LINUX_SHIM_SOURCE_DATE_EPOCH = $(shell git -C $(LD_LINUX_SHIM_SRC) log -1 --format=%ct 2>/dev/null || echo 1)

# The shim must be built for HOST_ARCH (where the toolchain runs), not TARGET_ARCH
# Use BOOTSTRAP gcc for native builds since it doesn't require relocation
# For Case 3 (BUILD ≠ HOST), we need the CROSS compiler (runs on BUILD, produces for HOST)
ifeq ($(BUILD_TRIPLE),$(HOST_TRIPLE))
LD_LINUX_SHIM_PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
LD_LINUX_SHIM_CC_DEP := $(BOOTSTRAP_BUILD_DIR)/.gcc.installed
else
LD_LINUX_SHIM_PATH := $(CROSS_PREFIX)/bin:$(BUILD_PREFIX)/bin:$(ORIG_PATH)
LD_LINUX_SHIM_CC_DEP := $(CROSS_BUILD_DIR)/.gcc.installed
endif
LD_LINUX_SHIM_CC := $(HOST_TRIPLE)-gcc
LD_LINUX_SHIM_CFLAGS = -Os -g0 -ffreestanding -fno-stack-protector -fno-builtin -Wall -Wextra -Werror -ffile-prefix-map=$(LD_LINUX_SHIM_SRC)=. -ffile-prefix-map=$(LD_LINUX_SHIM_BUILD)=. -nostdinc -isystem $(shell PATH=$(LD_LINUX_SHIM_PATH) $(LD_LINUX_SHIM_CC) -print-file-name=include)
LD_LINUX_SHIM_LDFLAGS = -static -nostdlib -nodefaultlibs

$(TARGET_BUILD_DIR)/.ld-linux-shim.installed: PREFIX := $(TARGET_PREFIX)
$(TARGET_BUILD_DIR)/.ld-linux-shim.installed: SOURCE_DATE_EPOCH := $(LD_LINUX_SHIM_SOURCE_DATE_EPOCH)

$(LD_LINUX_SHIM_BUILD)/ld-linux-shim.o: $(LD_LINUX_SHIM_SRC)/ld-linux-shim.c $(LD_LINUX_SHIM_SRC)/syscall.h $(LD_LINUX_SHIM_CC_DEP)
	mkdir -p $(LD_LINUX_SHIM_BUILD)
	PATH=$(LD_LINUX_SHIM_PATH) $(LD_LINUX_SHIM_CC) $(LD_LINUX_SHIM_CFLAGS) -c -o $@ $<

$(LD_LINUX_SHIM_BUILD)/start_$(HOST_ARCH).o: $(LD_LINUX_SHIM_SRC)/start_$(HOST_ARCH).S $(LD_LINUX_SHIM_CC_DEP)
	mkdir -p $(LD_LINUX_SHIM_BUILD)
	PATH=$(LD_LINUX_SHIM_PATH) $(LD_LINUX_SHIM_CC) -c -o $@ $<

$(LD_LINUX_SHIM_BIN): $(LD_LINUX_SHIM_BUILD)/start_$(HOST_ARCH).o $(LD_LINUX_SHIM_BUILD)/ld-linux-shim.o
	PATH=$(LD_LINUX_SHIM_PATH) $(LD_LINUX_SHIM_CC) $(LD_LINUX_SHIM_LDFLAGS) -o $@ $^

$(TARGET_BUILD_DIR)/.ld-linux-shim.installed: $(LD_LINUX_SHIM_BIN)
	mkdir -p $(PREFIX)/libexec
	cp $< $(PREFIX)/libexec/
	touch -h -d "@$(SOURCE_DATE_EPOCH)" $(PREFIX)/libexec/ld-linux-shim
	touch $@
