// Shim to load the Linux dynamic linker from a path relative to the
// current executable. To use:
//
// 1. Install in $ROOT/libexec/ld-linux-shim
// 2. mv $ROOT/bin/foo $ROOT/bin/foo.real
// 3. ln -s ../libexec/ld-linux-shim $ROOT/bin/foo
//
// Your dynamic linker (ld-linux-x86_64.so.2, etc.) should be installed
// in $ROOT/host-sysroot/usr/lib.


#include <stddef.h>
#include <stdnoreturn.h>

#include "syscall.h"

#define PATH_MAX 4096

#ifdef __x86_64__
typedef long ssize_t;

#define LD_LINUX "ld-linux-x86-64.so.2"
#endif

#ifdef __aarch64__
typedef long ssize_t;

#define LD_LINUX "ld-linux-aarch64.so.1"
#endif

extern char **environ;
extern unsigned long *auxv;

extern long syscall1(long num, long arg1);
extern long syscall3(long num, long arg1, long arg2, long arg3);
extern long syscall4(long num, long arg1, long arg2, long arg3, long arg4);

#define AT_FDCWD -100

static ssize_t
readlink(const char *pathname, char *buf, size_t bufsiz) {
    return syscall4(SYS_readlinkat, AT_FDCWD, (long)pathname, (long)buf, bufsiz);
}

static ssize_t
write(int fd, const void *buf, size_t count) {
    return syscall3(SYS_write, fd, (long)buf, count);
}

static int
execve(const char *pathname, char *const argv[], char *const envp[]) {
    return syscall3(SYS_execve, (long)pathname, (long)argv, (long)envp);
}

static noreturn void
exit(int status) {
    syscall1(SYS_exit, status);
    __builtin_unreachable();
}

// From linux/auxvec.h
#define AT_NULL   0  /* end of vector */
#define AT_EXECFN 31 /* filename of program */

// Get auxiliary vector value
static unsigned long
getauxval(unsigned long type) {
    if (!auxv) {
        return 0;
    }

    for (unsigned long *p = auxv; p[0] != AT_NULL; p += 2) {
        if (p[0] == type) {
            return p[1];
        }
    }

    return 0;
}

// String length
static size_t
strlen(const char *s) {
    size_t len = 0;
    while (s[len]) {
        len++;
    }
    return len;
}

// strlcpy: copy string with size limit
// Always null-terminates (if size > 0)
// Returns total length of src (for truncation detection)
static size_t
strlcpy(char *dst, const char *src, size_t sz) {
    size_t src_len = strlen(src);
    if (sz > 0) {
        size_t copy_len = (src_len >= sz) ? sz - 1 : src_len;
        size_t i;
        for (i = 0; i < copy_len; i++) {
            dst[i] = src[i];
        }
        dst[copy_len] = '\0';
    }
    return src_len;
}

// strlcat: concatenate string with sz limit
// Always null-terminates (if sz > 0)
// Returns total length of string it tried to create
static size_t
strlcat(char *dst, const char *src, size_t sz) {
    size_t dst_len = strlen(dst);
    size_t src_len = strlen(src);
    if (dst_len >= sz) {
        return dst_len + src_len;  // dst already too long
    }
    return dst_len + strlcpy(dst + dst_len, src, sz - dst_len);
}

// Find last occurrence of character
static char *
strrchr(const char *s, int c) {
    const char *last = NULL;
    while (*s) {
        if (*s == c) {
            last = s;
        }
        s++;
    }
    return (char*)last;
}

// dirname implementation - returns directory part of path
static char *
dirname(char *path) {
    char *p;

    if (!path || !*path) {
        return ".";
    }

    // Remove trailing slashes
    p = path + strlen(path) - 1;
    while (p > path && *p == '/') {
        *p-- = '\0';
    }

    // If no slashes, return "."
    p = strrchr(path, '/');
    if (!p) {
        return ".";
    }

    // If only "/" at start, return "/"
    if (p == path) {
        *(p + 1) = '\0';
        return path;
    }

    // Truncate at last slash
    *p = '\0';
    return path;
}

static noreturn void
panic(char *s) {
    write(2, s, strlen(s));
    write(2, "\n", 1);
    exit(1);
}

int
main(int argc, char *argv[]) {
    char ld_path[PATH_MAX];
    char bin_path[PATH_MAX];

    // Get absolute path of $TOOLCHAIN/libexec/ld-linux-shim then build ld_path
    ssize_t shim_len = readlink("/proc/self/exe", ld_path, PATH_MAX - 1);
    if (shim_len < 0) {
        panic("failed to read /proc/self/exe");
    }
    if (shim_len >= PATH_MAX - 1) {
        panic("path too long\n");
    }
    ld_path[shim_len] = '\0';

    // Find toolchain root by getting dirname twice from ld_path
    dirname(ld_path);  // Remove "ld-linux-shim"
    dirname(ld_path);  // Remove "libexec"

    // Get AT_EXECFN for the original path we were execed with
    char *execfn = (char *)getauxval(AT_EXECFN);
    if (!execfn) {
        panic("AT_EXECFN not found");
    }

    if (strlcat(ld_path, "/host-sysroot/usr/lib/" LD_LINUX, PATH_MAX) >= PATH_MAX ||
        strlcpy(bin_path, execfn, PATH_MAX) >= PATH_MAX ||
        strlcat(bin_path, ".real", PATH_MAX) >= PATH_MAX) {
        panic("path too long");
    }

    char *new_argv[argc + 2];
    new_argv[0] = ld_path;
    new_argv[1] = bin_path;
    for (int i = 1; i < argc; i++) {
        new_argv[i + 1] = argv[i];
    }
    new_argv[argc + 1] = NULL;

    execve(ld_path, new_argv, environ);
    panic("execve failed");
}
