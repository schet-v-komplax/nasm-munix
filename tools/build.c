/*
 * build.c
 * make image from root directory
 */

#include "tools.h"

#define LAST_BLOCK              0x001
#define SYSTEM_BLOCK            0x002
#define BAD_BLOCK               0x003

#define FIRST_BLOCK             4

static u_int8_t MBT[BLOCK * 3];

#define F_PRESENT               0x80
#define F_DIR                   0x40
#define F_HIDDEN                0x20
#define F_LINEAR                0x10
#define F_READ                  0x04
#define F_WRITE                 0x02
#define F_EXEC                  0x01

struct file
{
    u_int8_t flags;
    char name[15];
    u_int16_t block;
    u_int16_t count;
    char pad[4];
    u_int32_t c_time;
    u_int32_t m_time;
} __attribute__((packed));

static struct ifile
{
    struct file file;
    struct ifile * parent;
    char path[128];                 // path within current filesystem

    u_int8_t buf[BLOCK];
    u_int16_t block;
    u_int16_t pos;
    int fd;
} * current_dir;

#define MBR_SRC_SIZE    446 - sizeof(struct MBR_header)
#define skip_entry(x)   (!strcmp(x + strlen(x) - 4, ".asm"))    // skip source files

static struct
{
    struct MBR_header {
        u_int16_t jmp;
        u_int8_t sign[10];
        u_int16_t munix_sys;
        u_int16_t init_sys;
    } __attribute__((packed)) header;
    u_int8_t src[MBR_SRC_SIZE];    
    struct
    {
        u_int8_t status;
        u_int8_t start_head;
        u_int8_t start_sec;
        u_int8_t start_cyl;
        u_int8_t type;
        u_int8_t last_head;
        u_int8_t last_sec;
        u_int8_t last_cyl;
        u_int32_t start_lba;
        u_int32_t size;
    } __attribute__((packed)) gpt[4];
    u_int16_t sign;
} __attribute__((packed)) MBR = { {}, "", { { 0x80, 0, 1, 0, 0x7f, 0, 1, 0, 0, 0x4000 } }, 0xaa55 };

static u_int32_t root_dir_len;
u_int16_t munix_sys, init_sys;

// raw 00 11 22 33 44 55 66 77 88
// fat 00 10 11 22 32 33 44 54 55

static void set_mbt_entry(u_int16_t n, u_int16_t v)
{
    if(n > 0xfff || v > 0xfff) return;
    u_int16_t * x = (u_int16_t *)(MBT + n * 3 / 2);
    if(n % 2 == 0) *x = *x & 0xf000 | v;
    else *x = *x & 0x000f | (v << 4);
}

static u_int16_t get_mbt_entry(u_int16_t n)
{
    if(n > 0xfff) return LAST_BLOCK;
    u_int16_t x = *(u_int16_t *)(MBT + n * 3 / 2);
    if(n % 2 == 0) return x & 0x0fff;
    else return (x >> 4);
}

static u_int16_t find_free_block()
{
    u_int16_t n = 0, e;
    while(e = get_mbt_entry(n)) {
        if(e == LAST_BLOCK) die("not enough space on disk");
        n++;
    }
    set_mbt_entry(n, 0xfff);
    return n;
}

// allocate n-block file
static u_int16_t alloc_blocks(u_int16_t n)
{
    if(!n) return 0;
    u_int16_t r = find_free_block();
    u_int16_t p = r;
    u_int16_t t;
    while(--n) {
        t = find_free_block();
        set_mbt_entry(p, t);
        p = t;
    }
    return r;
}

static void write_block(u_int16_t n, u_int8_t * buf)
{
    do_write(1, buf, n * BLOCK, BLOCK);
}

static u_int16_t get_dir_size(struct ifile * i)
{
    struct dirent * e;
    u_int16_t size = 0;
    DIR * d = opendir(i->path);
    if(!d) die("%s: %s", i->path, strerror(errno));
    while(e = readdir(d)) {
        if(skip_entry(e->d_name)) continue;
        size += sizeof(struct file);
    }
    closedir(d);
    return size;
}

static void iflush(struct ifile * i)
{
    while(i->pos < BLOCK) i->buf[i->pos++] = '\0';
    write_block(i->block, i->buf);
    i->pos = 0;
    i->block = get_mbt_entry(i->block);
}

// open file within current dir
static void iopen(struct ifile * i, const char * name)
{
    memset(i->file.name, '\0', 15);
    if(current_dir) {
        strcpy(i->path, current_dir->path);
        strcat(i->path, "/");
    }
    strcat(i->path, name);
    strcpy(i->file.name, name);
    i->fd = open(i->path, O_RDONLY);
    if(!i->fd) die("%s: %s", i->fd, strerror(errno));

    i->parent = current_dir;
    i->file.flags = F_PRESENT;
    struct stat s;
    fstat(i->fd, &s);
    if(S_ISDIR(s.st_mode)) i->file.flags |= F_DIR;
    if(s.st_mode & S_IREAD) i->file.flags |= F_READ;
    if(s.st_mode & S_IWRITE) i->file.flags |= F_WRITE;
    if(s.st_mode & S_IEXEC && !(i->file.flags & F_DIR)) i->file.flags |= F_EXEC;
    if(i->file.flags & F_DIR) i->file.count = get_dir_size(i);
    else i->file.count = s.st_size;
    i->file.block = alloc_blocks((i->file.count + BLOCK - 1) / BLOCK);
    if(!strncmp(i->file.name, "hd", 2)) {
        i->file.flags |= F_LINEAR;
        i->file.count = 0xffff;
        i->file.block = (i->file.name[2] - '0') * 32;
    }
    else if(!strcmp(i->path + root_dir_len, "/boot/masterboot.sys")) {
        i->file.flags |= F_LINEAR;
        i->file.count = 512;
        i->file.block = 0;
    }
    i->block = i->file.block;
    i->pos = 0;
    i->file.c_time = s.st_ctime;
    i->file.m_time = s.st_mtime;
}

static void iclose(struct ifile * i)
{
    iflush(i);
    close(i->fd);
}

static void iwrite(struct ifile * i, const void * buf, u_int16_t n)
{
    if(i->pos == BLOCK)
        iflush(i);
    memcpy(i->buf + i->pos, buf, n);
    i->pos += n;
}

static void install_dir();

static void install_file(const char * name)
{
    struct ifile i;
    iopen(&i, name);

    iwrite(current_dir, &i.file, sizeof(struct file));

    if(i.file.flags & F_DIR) {
        current_dir = &i;
        install_dir();
        current_dir = i.parent;
    }
    else {
        u_int16_t j;
        while(i.pos = read(i.fd, i.buf, BLOCK))
            iflush(&i);
    }
    
    if(!strcmp(i.path + root_dir_len, "/boot/munix.sys"))
        munix_sys = i.file.block;
    else if(!strcmp(i.path + root_dir_len, "/boot/init.sys"))
        init_sys = i.file.block;

    iclose(&i);
}

// install current_dir
static void install_dir()
{
    struct file tmp;    // for "." and ".."
    struct dirent * e;
    DIR * d = opendir(current_dir->path);
    if(!d) die("%s: %s", current_dir->path, strerror(errno));

    memcpy(&tmp, &current_dir->file, sizeof(struct file));
    memset(tmp.name, '\0', 15);
    tmp.flags |= F_HIDDEN;
    tmp.name[0] = '.';
    iwrite(current_dir, &tmp, sizeof(struct file));

    if(current_dir->parent) { 
        memcpy(&tmp, &current_dir->parent->file, sizeof(struct file));
        memset(tmp.name, '\0', 15);
    }
    else {
        memset(&tmp, '\0', sizeof(struct file));
        tmp.flags = F_PRESENT;
        tmp.block = SYSTEM_BLOCK;
    }
    tmp.name[0] = '.';
    tmp.name[1] = '.';
    tmp.flags |= F_HIDDEN;
    iwrite(current_dir, &tmp, sizeof(struct file));

    while(e = readdir(d)) {
        if(skip_entry(e->d_name)) continue;
        if(!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        install_file(e->d_name);
    }
    closedir(d);
}

static void masterboot(const char * s)
{
    int fd = open(s, O_RDONLY);
    if(fd < 0) die("%s: %s", s, strerror(errno));

    if(read(fd, &MBR, sizeof(MBR)) > 466)
        die("%s: code exceeds 446 bytes", s);
    close(fd);
    if(!munix_sys) die("/boot/munix.sys not found");
    if(!init_sys) die("/boot/init.sys not found");
    
    MBR.header.jmp = 0xeb | ((sizeof(MBR.header) - 2) << 8);
    MBR.header.munix_sys = munix_sys;
    MBR.header.init_sys = init_sys;
    memcpy(MBR.header.sign, "Munix 0.04", 10);
    do_write(1, &MBR, 0, sizeof(MBR));
}

static void usage()
{
    die("usage: %s options... [> image]\n"
        "  r        [=filesystem root directory]\n"
        "  b        [=masterboot]", progname);
}

int main(int argc, char * argv[])
{
    progname = argv[0];

    struct ifile root = { 0 };
    const char * mbr;
    const char * root_path;

    for(int i = 1; i < argc; i++) {
        if(argv[i][0] == 'r')
            root_path = argv[i] + 2;
        else if(argv[i][0] == 'b')
            mbr = argv[i] + 2;
    }
    root_dir_len = strlen(root_path);
    
    // theese values are reserved for system
    for(u_int32_t i = 0; i < FIRST_BLOCK; i++)
        set_mbt_entry(i, SYSTEM_BLOCK);

    iopen(&root, root_path);
    current_dir = &root;
    install_dir();
    iclose(&root);
    set_mbt_entry(0xfff, LAST_BLOCK);

    do_write(1, MBT, BLOCK, sizeof(MBT));
    masterboot(mbr);
    return 0;
}
