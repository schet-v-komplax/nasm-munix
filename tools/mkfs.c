#include "tools.h"

#define DRV_MAX         16
#define NAME_LEN        15

struct file
{
    u_int8_t    f_flags;
    u_int8_t    f_name[NAME_LEN];
    u_int16_t   f_block;
    u_int32_t   f_size;
    u_int16_t   f_unused;
    u_int32_t   f_ctime;
    u_int32_t   f_mtime;
} __attribute__((__packed__));

struct sys_header
{
    u_int16_t   s_magic;
    u_int8_t    s_name[NAME_LEN - 4];
    u_int8_t    s_blocks;
    u_int16_t   s_block;
} __attribute__((__packed__));

static struct
{
    u_int16_t   jmp;
    u_int8_t    sign[6];
    u_int8_t    version[4];
    u_int16_t   munix_block;
    u_int16_t   drivers_count;
    u_int16_t   drivers[DRV_MAX];
} __attribute__((__packed__)) masterboot = { 0xeb + ((sizeof(masterboot) - 2) << 8), "Munix ", "", 0, 0 };

struct ifile
{
    struct file file;
    struct ifile * parent;
    int in, out;
    u_int32_t pos;
    char path[64];
};


static u_int32_t core_path_len;

static const char * drivers[DRV_MAX];
static u_int8_t drv_ints[DRV_MAX];

#define skip_entry(x)   (!strcmp(x + strlen(x) - 4, ".asm"))    // skip source files

static u_int8_t MBT[BLOCK * 3];

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

static u_int16_t get_free_block()
{
    u_int16_t n = 0, t;
    while(t = get_mbt_entry(n)) {
        if(t == LAST_BLOCK) die("Not enough space on disk");
        n++;
    }
    set_mbt_entry(n, 0xfff);
    return n;
}

static u_int16_t alloc_blocks(u_int16_t n)
{
    u_int16_t r = 0, p = 0, c;
    while(n--) {
        c = get_free_block();
        if(p) set_mbt_entry(p, c);
        else r = c;
        p = c;
    }
    return r;
}

static u_int32_t get_dir_size(struct ifile * i)
{
    u_int32_t r = 0;
    struct dirent * d;
    DIR * dir = opendir(i->path);
    if(!dir) die("%s: %s", i->path, strerror(errno));
    while(d = readdir(dir))
        if(!skip_entry(d->d_name)) 
            r += sizeof(struct file);
    closedir(dir);
    return r;
}

static struct ifile * iopen(const char * name, struct ifile * parent)
{
    struct stat s;
    struct ifile * i = calloc(1, sizeof(struct ifile));

    if(parent) {
        strcpy(i->path, parent->path);
        strcat(i->path, "/");
    }
    strcat(i->path, name);
    strcpy(i->file.f_name, name);
    i->in = open(i->path, O_RDONLY);
    if(i->in < 0) die("%s: %s", i->path, strerror(errno));
    i->out = 1;
    fstat(i->in, &s);
    i->parent = parent;
    i->file.f_flags |= F_PRESENT;
    if(S_ISDIR(s.st_mode)) i->file.f_flags |= F_DIR;
    if(s.st_mode & S_IREAD) i->file.f_flags |= F_READ;
    if(s.st_mode & S_IWRITE) i->file.f_flags |= F_WRITE;
    if(s.st_mode & S_IEXEC && !(i->file.f_flags & F_DIR)) i->file.f_flags |= F_EXEC;
    if(i->file.f_flags & F_DIR) i->file.f_size = get_dir_size(i);
    else i->file.f_size = s.st_size;
    if(i->file.f_flags & F_EXEC && i->file.f_size > 64 * 0x400) die("%s: size exceeded 64K", i->path);
    i->file.f_block = alloc_blocks((i->file.f_size + BLOCK - 1) / BLOCK);
    i->file.f_ctime = s.st_ctime;
    i->file.f_mtime = s.st_mtime;
    return i;
}

static void iclose(struct ifile * i)
{
    close(i->in);
    free(i);
}

static void iwrite(struct ifile * i, const void * buf, u_int32_t size)
{
    do_write(1, buf, i->file.f_block * BLOCK + i->pos, size);
    i->pos += size;
}

static void install_sys(struct ifile * i, u_int16_t magic)
{
    struct sys_header h = { 0 };
    h.s_magic = magic;
    memcpy(&h.s_name, i->file.f_name, strnlen(i->file.f_name, NAME_LEN) - 4);
    h.s_blocks = (i->file.f_size + BLOCK - 1) / BLOCK;
    h.s_block = i->parent->file.f_block;
    i->pos = 0;
    iwrite(i, &h, sizeof(struct sys_header));
}

static void install_dir(struct ifile * i);

static void install_file(const char * name, struct ifile * parent)
{
    struct ifile * i = iopen(name, parent);
    iwrite(parent, &i->file, sizeof(struct file));

    if(i->file.f_flags & F_DIR)
        install_dir(i);
    else if(!(i->file.f_flags & F_LINEAR)) {
        u_int8_t * buf = malloc(i->file.f_size);
        if(read(i->in, buf, i->file.f_size) != i->file.f_size)
            die("%s: %s", i->path, strerror(errno));
        iwrite(i, buf, i->file.f_size);
    }

    if(!strcmp(i->path + core_path_len, "/boot/munix.sys")) {
        masterboot.munix_block = i->file.f_block;
        install_sys(i, 0x7f7f);
    }
    for(int j = 0; j < masterboot.drivers_count; j++)
        if(drivers[j] && !strcmp(i->path + core_path_len, drivers[j])) {
            if(i->file.f_size > 0x1000) die("%s size exceeded 4K");
            masterboot.drivers[j] = i->file.f_block;
            drivers[j] = 0;
            install_sys(i, 0x007f | (drv_ints[j] << 8));
        }
    iclose(i);
}

static void install_dir(struct ifile * i)
{
    struct file tmp;
    struct dirent * d;
    DIR * dir = opendir(i->path);
    if(!dir) die("%s: %s", i->path, strerror(errno));
    
    // this dir
    memcpy(&tmp, &i->file, sizeof(struct file));
    tmp.f_name[0] = '.';
    memset(tmp.f_name + 1, '\0', 14);
    iwrite(i, &tmp, sizeof(struct file));

    // parent dir
    if(i->parent) {
        memcpy(&tmp, &i->parent->file, sizeof(struct file));
        memset(tmp.f_name + 2, '\0', 13);
    }
    else {
        memset(&tmp, '\0', sizeof(struct file));
        tmp.f_flags = F_PRESENT;
    }
    tmp.f_name[0] = '.';
    tmp.f_name[1] = '.';
    iwrite(i, &tmp, sizeof(struct file));

    while(d = readdir(dir)) {
        if(skip_entry(d->d_name)) continue;
        if(!strcmp(d->d_name, ".") || !strcmp(d->d_name, "..")) continue;
        install_file(d->d_name, i);
    }

    closedir(dir);
}

static void install_boot(const char * path)
{
    u_int8_t buf[512];
    int i = 0;

    if(path) {
    int fd = open(path, O_RDONLY);
    if(fd < 0) die("%s: %s", path, strerror(errno));
    if((i = read(fd, buf, 512)) > 446)
        die("%s is too large", path);
    if(i < 48) die("%s: bad header", path);
    close(fd);
    memcpy(buf, &masterboot, sizeof(masterboot));

    if(!masterboot.munix_block) die("/boot/munix.sys not found");
    for(int j = 0; j < DRV_MAX; j++)
        if(drivers[j]) die("%s not found", drivers[j]);
    }
    while(i < 510) buf[i++] = '\0';
    
    *(u_int16_t *)(buf + 510) = 0xaa55;
    do_write(1, buf, 0, 512);
}

static void usage()
{
    die("usage: %s options... [> image]\n"
        "options:\n"
        "  v        [=version (4 characters)]\n"
        "  s        [=disk size (up to 8M)]\n"
        "  c        [=core directory]\n"
        "  d        [=drivers, e.g. [drv1:int1,...], max count=8]\n"
        "  b        [=boot]", progname);
}

u_int32_t parse_size(const char * s)
{
    u_int32_t r = 0;
    while(isdigit(*s)) r = r * 10 + *s++ - '0';
    switch(*s) {
        case 'M': return r * 0x100000;
        case 'K': return r * 0x400;
        default:  return r;
    }
}

void parse_drv_names(char * names)
{
    int k = 3;
    
    drivers[0] = names + k;
    while(true) {
        if(!names[k]) usage();
        if(names[k] == ',' || names[k] == ']') {
            masterboot.drivers_count++;
            if(masterboot.drivers_count == DRV_MAX) break;
            if(names[k] == ']') break;
            drivers[masterboot.drivers_count] = names + k + 1;
        }

        if(names[k] == ':') {
            names[k++] = '\0';
            while(isdigit(names[k]))
                drv_ints[masterboot.drivers_count] = drv_ints[masterboot.drivers_count] * 10 + names[k++] - '0';
        }
        else k++;
    }
    names[k] = '\0';
}

int main(int argc, char * argv[])
{
    u_int32_t size = 0x800000;
    const char * boot = 0;
    const char * core_path = 0;

    progname = argv[0];

    for(int i = 1; i < argc; i++) {
        switch(argv[i][0]) {
            case 'v': strncpy(masterboot.version, argv[i] + 2, 4); break;
            case 's': size = parse_size(argv[i] + 2);
            case 'c': core_path = argv[i] + 2; break;
            case 'd': parse_drv_names(argv[i]); break;
            case 'b': boot = argv[i] + 2; break;
            default: usage(); break;
        }
    }
    if(!core_path) usage();
    if(size > 0x800000) usage();

    set_mbt_entry(0, SYSTEM_BLOCK);
    set_mbt_entry(1, SYSTEM_BLOCK);
    set_mbt_entry(2, SYSTEM_BLOCK);
    set_mbt_entry(3, SYSTEM_BLOCK);
    for(u_int16_t i = (u_int16_t)(size / BLOCK) - 1; i < 4096; i++)
        set_mbt_entry(i, LAST_BLOCK);

    core_path_len = strlen(core_path);
    struct ifile * core = iopen(core_path, NULL);
    install_dir(core);
    iclose(core);

    do_write(1, MBT, BLOCK, 3 * BLOCK);
    install_boot(boot);
    lseek(1, size - BLOCK, L_SET);
    write(1, "$.\0\0", 4);
    return 0;
}
