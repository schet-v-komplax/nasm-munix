/*
 * install.c
 *
 * copy Image to disk/file
 */

#include "tools.h"

static void usage()
{
    die("usage: %s <src> <dst>\n"
        "  copy <src> file/device to <dst>\n"
        "  root rights are required", progname);
}

int main(int argc, char * argv[])
{
    int fda, fdb, i = 0;
    progname = argv[0];
    char buf[4096];
    if(argc != 3)
        usage();

    fda = open(argv[1], O_RDONLY);
    fdb = open(argv[2], O_WRONLY);
    if(fda < 0 || fdb < 0)
        die("bad input: %s", argv[1], argv[2], strerror(errno));
    while(read(fda, buf, 4096)) {
        write(fdb, buf, 4096);
        i += 4096;
        fprintf(stderr, "written %d bytes...\r", i);
    }
    fprintf(stderr, "\n");
    close(fda);
    close(fdb);
    return 0;
}
