    push    cs
    pop     ds

    cmp     cx, 2
    jb      exit
arg2:
    es lodsb
    or      al, al
    jnz     arg2
    
    mov     ax, 5
    mov     bx, si
    mov     cx, 6
    mov     dx, 0
    int     0x80
    cmp     ax, -1
    je      exit
    mov     bx, ax
    push    cs
    pop     es
rp_cat:
    mov     ax, 11
    int     0x80
    cmp     al, -1
    je      rp_ok
    int     0x24
    cmp     al, 10
    jne     rp_cat
    mov     al, 13
    int     0x24
    jmp     rp_cat
rp_ok:
    mov     ax, 6
    int     0x80
    mov     word [code], 0
exit:
    mov     ax, 1
    mov     bx, [code]
    int     0x80                        ; exit

code        dw -1
