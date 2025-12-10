/* Linux syscall numbers */

#ifndef SYSCALL_H
#define SYSCALL_H

#ifdef __aarch64__
#define SYS_close 57
#define SYS_openat 56
#define SYS_write 64
#define SYS_readlinkat 78
#define SYS_exit 93
#define SYS_execve 221
#endif

#ifdef __x86_64__
#define SYS_write 1
#define SYS_close 3
#define SYS_openat 257
#define SYS_execve 59
#define SYS_exit 60
#define SYS_readlinkat 267
#endif

#endif /* SYSCALL_H */
