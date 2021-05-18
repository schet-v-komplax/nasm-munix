    mov     ax, cs
    mov     ds, ax
    mov     es, ax
    
    mov     bx, 1
    int     0x20
    push    32
    push    ax

    xor     cx, cx
    xor     dx, dx
check_block:
    mov     ax, dx
    call    next_block
    or      ax, ax
    jnz     not_free
    inc     cx
not_free:
    inc     dx
    cmp     ax, 0x01
    jne     check_block
    mov     ax, cx
    shl     ax, 1
    push    ax
    push    dx
    push    cx
    mov     si, fmt
    call    print
exit:
    mov     ax, 1
    xor     bx, bx
    int     0x80

next_block:
    push    bx
    push    ax
    mov     bx, ax
    shr     bx, 1
    add     bx, ax                      ; bx=ax*1.5
    mov     ax, [fs:bx]
    pop     bx
    test    bx, 1
    jnz     next_odd
    and     ax, 0xfff
    jmp     do_ret
next_odd:
    shr     ax, 4
do_ret:
    pop     bx
    ret

%include "tools/print.asm"

fmt         db "#d/#d blocks (#dK free), #d/#d buffers", 13, 10, 0
