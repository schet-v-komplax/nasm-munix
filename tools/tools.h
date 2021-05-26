/*
 * here is some common code for munix tools
 */

#pragma once

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stdbool.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <sys/stat.h>
#include <stdnoreturn.h>
#include <ctype.h>

#define BLOCK           2048
#define LAST_BLOCK      0x001
#define SYSTEM_BLOCK    0x002
#define BAD_BLOCK       0x003

#define F_PRESENT       0x80
#define F_DIR           0x40
#define F_HIDDEN        0x20
#define F_LINEAR        0x10
#define F_READ          0x4
#define F_WRITE         0x2
#define F_EXEC          0x1

typedef u_int16_t block_t;

static const char * progname;

static noreturn void die(const char * fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "%s: ", progname);
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    exit(1);
}

static void do_write(int fd, const void * buf, off_t pos, size_t size)
{
    lseek(fd, pos, L_SET);
    write(fd, buf, size);
}

static void usage();
