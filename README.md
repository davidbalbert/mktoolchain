# mktoolchain

Build reproducable, relocatable, (mostly) static C/C++ toolchains and sysroots.

## Building

```bash
$ script/download.sh --build-root=/path/to/buildroot

$ script/build-binutils.sh --build-root=/path/to/buildroot --bootstrap
$ script/build-gcc.sh --build-root=/path/to/buildroot --bootstrap
$ script/build-linux-headers.sh --build-root=/path/to/buildroot
$ script/build-glibc.sh --build-root=/path/to/buildroot
$ script/build-libstdc++.sh --build-root=/path/to/buildroot

$ script/build-binutils.sh --build-root=/path/to/buildroot
$ script/build-gcc.sh --build-root=/path/to/buildroot
$ script/build-glibc.sh --build-root=/path/to/buildroot --clean
$ script/build-gcc.sh --build-root=/path/to/buildroot --clean

$ script/make-reloc.sh /path/to/buildroot/out/$(uname -m)-linux-gnu/$(uname -m)-linux-gnu-gcc-15.1.0/toolchain
```

## Requirements

- gawk
- make
- patchelf
- python

## License

mktoolchain is copyright David Albert and released under the terms of the MIT License. See LICENSE.txt for details.
