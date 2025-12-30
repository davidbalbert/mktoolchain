# ld-linux-shim build rules
# The shim must run on the same architecture as the toolchain binaries,
# not the target architecture. For native toolchains they're the same,
# but for cross-compilers they differ.

LD_LINUX_SHIM_SRC := $(PROJECT_ROOT)/ld-linux-shim
LD_LINUX_SHIM_SOURCE_DATE_EPOCH = $(shell git -C $(LD_LINUX_SHIM_SRC) log -1 --format=%ct 2>/dev/null || echo 1)

# NATIVE/CROSS shim: runs on BUILD, built by BOOTSTRAP
NATIVE_LD_LINUX_SHIM_BUILD := $(NATIVE_BUILD_DIR)/ld-linux-shim
NATIVE_LD_LINUX_SHIM_BIN := $(NATIVE_LD_LINUX_SHIM_BUILD)/ld-linux-shim
NATIVE_LD_LINUX_SHIM_PATH := $(BOOTSTRAP_PREFIX)/bin:$(ORIG_PATH)
NATIVE_LD_LINUX_SHIM_CC := $(BUILD_TRIPLE)-gcc
NATIVE_LD_LINUX_SHIM_CFLAGS = -Os -g0 -ffreestanding -fno-stack-protector -fno-builtin -Wall -Wextra -Werror -ffile-prefix-map=$(LD_LINUX_SHIM_SRC)=. -ffile-prefix-map=$(NATIVE_LD_LINUX_SHIM_BUILD)=. -nostdinc -isystem $(shell PATH=$(NATIVE_LD_LINUX_SHIM_PATH) $(NATIVE_LD_LINUX_SHIM_CC) -print-file-name=include)
NATIVE_LD_LINUX_SHIM_LDFLAGS = -static -nostdlib -nodefaultlibs

$(NATIVE_LD_LINUX_SHIM_BUILD)/ld-linux-shim.o: $(LD_LINUX_SHIM_SRC)/ld-linux-shim.c $(LD_LINUX_SHIM_SRC)/syscall.h $(BOOTSTRAP_BUILD_DIR)/.gcc.installed
	mkdir -p $(NATIVE_LD_LINUX_SHIM_BUILD)
	PATH=$(NATIVE_LD_LINUX_SHIM_PATH) $(NATIVE_LD_LINUX_SHIM_CC) $(NATIVE_LD_LINUX_SHIM_CFLAGS) -c -o $@ $<

$(NATIVE_LD_LINUX_SHIM_BUILD)/start_$(BUILD_ARCH).o: $(LD_LINUX_SHIM_SRC)/start_$(BUILD_ARCH).S $(BOOTSTRAP_BUILD_DIR)/.gcc.installed
	mkdir -p $(NATIVE_LD_LINUX_SHIM_BUILD)
	PATH=$(NATIVE_LD_LINUX_SHIM_PATH) $(NATIVE_LD_LINUX_SHIM_CC) -c -o $@ $<

$(NATIVE_LD_LINUX_SHIM_BIN): $(NATIVE_LD_LINUX_SHIM_BUILD)/start_$(BUILD_ARCH).o $(NATIVE_LD_LINUX_SHIM_BUILD)/ld-linux-shim.o
	PATH=$(NATIVE_LD_LINUX_SHIM_PATH) $(NATIVE_LD_LINUX_SHIM_CC) $(NATIVE_LD_LINUX_SHIM_LDFLAGS) -o $@ $^

$(NATIVE_BUILD_DIR)/.ld-linux-shim.installed: PREFIX := $(NATIVE_PREFIX)
$(NATIVE_BUILD_DIR)/.ld-linux-shim.installed: SOURCE_DATE_EPOCH := $(LD_LINUX_SHIM_SOURCE_DATE_EPOCH)
$(NATIVE_BUILD_DIR)/.ld-linux-shim.installed: $(NATIVE_LD_LINUX_SHIM_BIN)
	mkdir -p $(PREFIX)/libexec
	cp $< $(PREFIX)/libexec/
	touch -h -d "@$(SOURCE_DATE_EPOCH)" $(PREFIX)/libexec/ld-linux-shim
	touch $@

# CROSS shim: same binary as NATIVE (both run on BUILD)
ifneq ($(HOST),$(BUILD))
$(CROSS_BUILD_DIR)/.ld-linux-shim.installed: PREFIX := $(CROSS_PREFIX)
$(CROSS_BUILD_DIR)/.ld-linux-shim.installed: SOURCE_DATE_EPOCH := $(LD_LINUX_SHIM_SOURCE_DATE_EPOCH)
$(CROSS_BUILD_DIR)/.ld-linux-shim.installed: $(NATIVE_LD_LINUX_SHIM_BIN)
	mkdir -p $(PREFIX)/libexec
	cp $< $(PREFIX)/libexec/
	touch -h -d "@$(SOURCE_DATE_EPOCH)" $(PREFIX)/libexec/ld-linux-shim
	touch $@
endif

# FINAL shim: runs on HOST
# When HOST == BUILD, reuse the NATIVE shim binary
# When HOST != BUILD, need to build with CROSS compiler
ifeq ($(BUILD_TRIPLE),$(HOST_TRIPLE))
# HOST == BUILD: reuse NATIVE shim
ifneq ($(FINAL_BUILD_DIR),$(NATIVE_BUILD_DIR))
$(FINAL_BUILD_DIR)/.ld-linux-shim.installed: PREFIX := $(FINAL_PREFIX)
$(FINAL_BUILD_DIR)/.ld-linux-shim.installed: SOURCE_DATE_EPOCH := $(LD_LINUX_SHIM_SOURCE_DATE_EPOCH)
$(FINAL_BUILD_DIR)/.ld-linux-shim.installed: $(NATIVE_LD_LINUX_SHIM_BIN)
	mkdir -p $(PREFIX)/libexec
	cp $< $(PREFIX)/libexec/
	touch -h -d "@$(SOURCE_DATE_EPOCH)" $(PREFIX)/libexec/ld-linux-shim
	touch $@
endif
else
# HOST != BUILD: build shim for HOST using CROSS compiler
FINAL_LD_LINUX_SHIM_BUILD := $(FINAL_BUILD_DIR)/ld-linux-shim
FINAL_LD_LINUX_SHIM_BIN := $(FINAL_LD_LINUX_SHIM_BUILD)/ld-linux-shim
FINAL_LD_LINUX_SHIM_PATH := $(CROSS_PREFIX)/bin:$(NATIVE_PREFIX)/bin:$(ORIG_PATH)
FINAL_LD_LINUX_SHIM_CC := $(HOST_TRIPLE)-gcc
FINAL_LD_LINUX_SHIM_CFLAGS = -Os -g0 -ffreestanding -fno-stack-protector -fno-builtin -Wall -Wextra -Werror -ffile-prefix-map=$(LD_LINUX_SHIM_SRC)=. -ffile-prefix-map=$(FINAL_LD_LINUX_SHIM_BUILD)=. -nostdinc -isystem $(shell PATH=$(FINAL_LD_LINUX_SHIM_PATH) $(FINAL_LD_LINUX_SHIM_CC) -print-file-name=include)
FINAL_LD_LINUX_SHIM_LDFLAGS = -static -nostdlib -nodefaultlibs

$(FINAL_LD_LINUX_SHIM_BUILD)/ld-linux-shim.o: $(LD_LINUX_SHIM_SRC)/ld-linux-shim.c $(LD_LINUX_SHIM_SRC)/syscall.h $(CROSS_BUILD_DIR)/.gcc.installed
	mkdir -p $(FINAL_LD_LINUX_SHIM_BUILD)
	PATH=$(FINAL_LD_LINUX_SHIM_PATH) $(FINAL_LD_LINUX_SHIM_CC) $(FINAL_LD_LINUX_SHIM_CFLAGS) -c -o $@ $<

$(FINAL_LD_LINUX_SHIM_BUILD)/start_$(HOST_ARCH).o: $(LD_LINUX_SHIM_SRC)/start_$(HOST_ARCH).S $(CROSS_BUILD_DIR)/.gcc.installed
	mkdir -p $(FINAL_LD_LINUX_SHIM_BUILD)
	PATH=$(FINAL_LD_LINUX_SHIM_PATH) $(FINAL_LD_LINUX_SHIM_CC) -c -o $@ $<

$(FINAL_LD_LINUX_SHIM_BIN): $(FINAL_LD_LINUX_SHIM_BUILD)/start_$(HOST_ARCH).o $(FINAL_LD_LINUX_SHIM_BUILD)/ld-linux-shim.o
	PATH=$(FINAL_LD_LINUX_SHIM_PATH) $(FINAL_LD_LINUX_SHIM_CC) $(FINAL_LD_LINUX_SHIM_LDFLAGS) -o $@ $^

$(FINAL_BUILD_DIR)/.ld-linux-shim.installed: PREFIX := $(FINAL_PREFIX)
$(FINAL_BUILD_DIR)/.ld-linux-shim.installed: SOURCE_DATE_EPOCH := $(LD_LINUX_SHIM_SOURCE_DATE_EPOCH)
$(FINAL_BUILD_DIR)/.ld-linux-shim.installed: $(FINAL_LD_LINUX_SHIM_BIN)
	mkdir -p $(PREFIX)/libexec
	cp $< $(PREFIX)/libexec/
	touch -h -d "@$(SOURCE_DATE_EPOCH)" $(PREFIX)/libexec/ld-linux-shim
	touch $@
endif
