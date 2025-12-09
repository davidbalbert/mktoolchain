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

## Special Notes

- Using bootstrap compiler approach for reproducibility
- No Docker dependency, using path normalization instead
- Will eventually need to support macOS builds
- Ignore the contents of any folders within the build directory, out directory, and src directory. There will be way to many of them and you will probably hang!

## Makefile migration

I'm in the process of migrating from shell scripts in the script directory to a Makefile.

To run the shell scripts, cd into /home/david/buildroot-old and run the scripts in
/Users/david/Developer/mktoolchain/script. To run the Makefile, cd into /home/david/buildroot
and run make with `-f /Users/david/Developer/mktoolchain/Makefile`.

Before running the Makefile, copy config.mk into the build directory:
`cp /Users/david/Developer/mktoolchain/config.mk /home/david/buildroot/`

When running the scripts, please use --clean to remove the build directory and start from scratch.
The makefile build output has to be cleaned manually. Before you run make, delete
buildroot/build/bootstrap/aarch64-linux-gnu-gcc-15.1.0/gcc as well as
buildroot/build/bootstrap/aarch64-linux-gnu-gcc-15.1.0/.gcc.*
