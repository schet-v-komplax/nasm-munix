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

#define PAGE    0x800
#define BLOCK   0x800

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
