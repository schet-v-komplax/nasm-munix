/*
 * tmp/alloc.c
 *
 * this is /drivers/mm.sys implementation, but in c
 * it's now useless actually
 */

#include <stdlib.h>
#include <stdio.h>

char mem[1024 * 187];

#define is_free(n) (!((n)->size & 0x8000))
#define is_null(n) (!(n)->size)

struct node
{
    u_int16_t size; // size in segments, high bit=is_used
    struct node * prev;
    struct node * next;
};

struct node map[256] = { { 0x2ec0, 0, &map[1] }, { 0x8040, &map[0], 0 } };

struct node * head = map;

u_int16_t _alloc(u_int16_t size)
{
    struct node * p = head;
    struct node * n = head;
    u_int16_t addr = 0x0100;

    size >>= 4;

    if(size > 0x7fff) return 0; 

    while(!is_free(n) || n->size < size) {
        addr += n->size & 0x7fff;
        n = n->next;
        if(!n) return 0;
    }

    while(!is_null(p)) p++;
    p->next = n->next;
    p->prev = n;
    p->next->prev = p;
    n->next = p;
    p->size = n->size - size;
    n->size = size | 0x8000;

    fprintf(stderr, "allocated block at %04x:0\n", addr);
    return addr;
}

void _free(u_int16_t p)
{
    struct node * n = head;
    u_int16_t addr = 0x100;

    if(p > 0x7fff) return;
    
    while(!is_null(n)) {
        if(addr == p) {
            n->size &= 0x7fff;
            fprintf(stderr, "freed block at %04x:0\n", addr);
            if(n->next && is_free(n->next)) {
                n->size += n->next->size;
                n->next->size = 0;
                n->next = n->next->next;
            }
            if(n->prev && is_free(n->prev)) {
                n = n->prev;
                n->size += n->next->size;
                n->next->size = 0;
                n->next = n->next->next;
            }
        }
        if(addr > p) return;
        addr += n->size & 0x7fff;
        n = n->next;
    }
}

void stat()
{
    struct node * n = head;
    u_int16_t addr = 0x100;
    while(n) {
        fprintf(stderr, "(%s) node at %04x:0, %d\n", is_free(n) ? "free" : "used", addr, n->size & 0x7fff);
        addr += n->size & 0x7fff;
        n = n->next;
    }
}

int main()
{
    u_int16_t p1 = _alloc(16);
    u_int16_t p2 = _alloc(11930);
    u_int16_t p3 = _alloc(11930);
    _free(p1);
    _free(p2);
    stat();
    return 0;
}
