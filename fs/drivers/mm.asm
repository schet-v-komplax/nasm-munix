;
; mm is used to manage 188K memory block at [0x01000-0x30000]
;

struc node
        n_size  resw 1                  ; number of 16-byte blocks (up to 0x7fff, 0 if unused), high bit is set if memory is not free
        n_prev  resb 1                  ; index of previous node
        n_next  resb 1                  ; index of next node
endstruc

LOW     equ     0x0100
HIGH    equ     0x3000

header  resb    16
        section .code
init:   push    word 0
        pop     ds
        mov     word [0x22*4], mm_int
        mov     word [0x22*4+2], cs
        xor     ah, ah
        retf

; ah=0: alloc
; ah=1: free
; ah=2: get_max_size
; ah=3: get_free_space
; ah=4: get_nodes
mm_int:
        cmp     ah, 4
        ja      .ret
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    bx
        mov     bx, cs
        mov     ds, bx
        mov     es, bx
        mov     bl, ah
        xor     bh, bh
        shl     bx, 1
        mov     si, bx
        pop     bx
        call    [si+inttab]
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
.ret:   iret

; input: cx=size
; output: ax:0=address, 0:0 if not enough memory
alloc:
        test    cx, cx
        jz      .err
        test    cx, 0x8000
        jne     .err
        mov     bx, [head]
        mov     ax, LOW                 ; ax:0=address
.1:     mov     dx, [bx+nodes+n_size]
        test    dx, 0x8000
        jnz     .2
        cmp     dx, cx
        jae     .3                      ; node with correct size found
.2:     and     dx, 0x7fff
        add     ax, dx
        mov     bl, [bx+nodes+n_next]
        xor     bh, bh
        test    bx, bx
        jz      .err                    ; not enough space
        shl     bx, 2
        jmp     .1
.3:     cmp     cx, [bx+nodes+n_size]   ; check if node has exactly same size
        jne     .4
.nice:  or      word [bx+nodes+n_size], 0x8000
        ret
.4:     mov     si, [head]              ; o/w, we need to divide current node to nodes (cx) and (n_size-cx) sizes
.5:     test    word [si+nodes+n_size], 0xffff
        jz      .6
        add     si, node_size
        cmp     si, node_size*256
        je      .nice                   ; no free nodes - then return full node
        jmp     .5
.6:     mov     dx, [bx+nodes+n_size]
        sub     dx, cx
        or      cx, 0x8000
        mov     [bx+nodes+n_size], cx
        mov     [si+nodes+n_size], dx
        mov     cl, [bx+nodes+n_next]
        mov     [si+nodes+n_next], cl
        mov     cx, si
        shr     cx, 2
        mov     [bx+nodes+n_next], cl
        shr     bx, 2
        mov     [si+nodes+n_prev], bl
        jmp     .ret
.err:   xor     ax, ax
.ret:   ret

; input: bx:0=address
; output: ax=error
free:
        mov     ax, LOW
        mov     si, [head]
.1:     cmp     ax, bx                  ; find node to be freed
        je      .2
        mov     dx, [si+nodes+n_size]
        and     dx, 0x7fff
        add     ax, dx
        mov     dl, [si+nodes+n_next]
        xor     dh, dh
        test    dx, dx
        jz      .err
        shl     dx, 2
        mov     si, dx
        jmp     .1
.2:     and     word [si+nodes+n_size], 0x7fff
        mov     bl, [si+nodes+n_next]   ; if next node is also free, merge them
        test    bl, bl
        jz      .3
        xor     bh, bh
        shl     bx, 2
        mov     cx, [bx+nodes+n_size]
        test    cx, 0x8000
        jnz     .3
        add     [si+nodes+n_size], cx
        mov     word [bx+nodes+n_size], 0
        mov     cl, [bx+nodes+n_next]
        mov     [si+nodes+n_next], cl
.3:     mov     bl, [si+nodes+n_prev]   ; if prev node is free, merge them
        test    bl, bl
        jz      .4
        xor     bh, bh
        shl     bx, 2
        test    word [bx+nodes+n_size], 0x8000
        jnz     .4
        mov     cx, [si+nodes+n_size]
        add     [bx+nodes+n_size], cx
        mov     word [si+nodes+n_size], 0
        mov     cl, [si+nodes+n_next]
        mov     [bx+nodes+n_next], cl
.4:     xor     ax, ax
        jmp     .ret
.err:   mov     ax, -1
.ret:   ret

; output: ax=max size of chunk of memory available for allocation (block_t)
get_max_size:
        mov     bx, [head]
        xor     ax, ax
.1:     mov     cx, [bx+nodes+n_size]
        test    cx, 0x8000
        jnz     .2
        cmp     ax, cx
        jae     .2
        mov     ax, cx
.2:     mov     bl, [bx+nodes+n_next]
        xor     bh, bh
        shl     bx, 2
        test    bx, bx
        jnz     .1
        ret

; output: ax=tatal free space within LOW...HIGH block
get_free_space:
        xor     ax, ax
        mov     bx, [head]
.1:     test    word [bx+nodes+n_size], 0x8000
        jnz     .2
        add     ax, [bx+nodes+n_size]
.2:     mov     bl, [bx+nodes+n_next]
        xor     bh, bh
        shl     bx, 2
        test    bx, bx
        jnz     .1
        ret

; output: ax=number of free nodes (up to 254)
get_nodes:
        xor     ax, ax
        xor     bx, bx
.1:     test    word [bx+nodes+n_size], 0xffff
        jnz     .2
        inc     ax
.2:     add     bx, node_size
        cmp     bx, node_size*256
        jne     .1
        ret

        section .data
inttab  dw      alloc, free, get_max_size, get_free_space, get_nodes
head    dw      4                       ; offset of first valid node
nodes   dd      0xffffffff              ; nodes[0] is reserved
        dw      HIGH-LOW
        db      0
        db      0
        resb    node_size*255
