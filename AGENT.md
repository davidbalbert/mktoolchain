# C/C++ Toolchain Project Memory

## Project Essentials

- **Goal**: Build reproducible, statically linked C/C++ toolchains for cross-compilation
- **Primary targets**: aarch64 Linux, x86_64 Linux
- **Components**: GCC 15.1, Binutils, glibc, Linux kernel headers

## Key Build Parameters

- **Reproducibility flags**:
  - `-ffile-prefix-map=ACTUAL_PATH=FIXED_PATH`
  - `SOURCE_DATE_EPOCH=MODIFIED_DATE_OF_SOURCE_FILES_IN_TARBALL`
  - `LC_ALL=C.UTF-8`
  - `-g0` for glibc and libgcc (eliminates debug info path leaks)
  - Deterministic ar flags: `AR_CREATE_FOR_TARGET`, `CREATE_ARFLAGS=Dcru`, `AR_FLAGS=Drc`

## Special Notes

- Using bootstrap compiler approach for reproducibility
- No Docker dependency, using path normalization instead
- Will eventually need to support macOS builds
- Ignore the contents of any folders within the build directory, out directory, and src directory. There will be way too many of them and you will probably hang!

## Running Builds

The build directory is separate from the source. Example setup:
```bash
cd /workspaces/buildroot
cp /workspaces/mktoolchain/config.mk .
make -f /workspaces/mktoolchain/Makefile toolchain
```

For cross-compilation:
```bash
make -f /workspaces/mktoolchain/Makefile toolchain TARGET=linux/x86_64
```

## Long-Running Build Commands

GCC/glibc builds can take 10+ minutes with no output during linking phases. The Bash tool has a 300-second inactivity timeout that will kill the process.

**Use the heartbeat pattern** to prevent timeout:
```bash
cd /workspaces/buildroot

# Start heartbeat in background
(while true; do sleep 60; echo -n "."; done) &
HEARTBEAT_PID=$!

# Run the build
make -f /workspaces/mktoolchain/Makefile toolchain > logs/build.log 2>&1
RET=$?

# Kill heartbeat
kill $HEARTBEAT_PID 2>/dev/null

echo "Exit code: $RET"
```

**Always redirect build output to log files** - do NOT use `tee` as it will flood the context window. Check logs with `tail -20 logs/build.log` after completion.

## Checking Reproducibility

Check for path leaks in binaries:
```bash
strings BINARY 2>/dev/null | grep -E "workspaces|buildroot" | wc -l
```

Check archive timestamps (should show epoch 0 for reproducible builds):
```bash
ar tv libgcc.a | head -5
# Should show: Jan  1 00:00 1970
```

## Clean Rebuilds

To rebuild a specific component, remove its stamp files and build artifacts:
```bash
# Example: rebuild glibc
rm -rf build/linux/aarch64/aarch64-linux-gnu-gcc-15.1.0/glibc
rm -f build/linux/aarch64/aarch64-linux-gnu-gcc-15.1.0/.glibc.*
```

To do a full clean:
```bash
make -f /workspaces/mktoolchain/Makefile clean
```
