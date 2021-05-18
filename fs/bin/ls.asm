%include "config.asm"

    push    cs
    pop     ds
    
    cmp     cx, 1
    je      ls_current
    inc     cx
    xor     bx, bx
    jb      ls_current
    call    skip_opt
next_opt:
    call    get_opt
    or      al, al
    je      parse_end
    cmp     al, 'h'
    jne     opt_h
    inc     byte [h]
opt_h:
    xor     bx, bx
    loop    next_opt
parse_end:
    or      bx, bx
    jnz     do_ls
ls_current:
    mov     bx, current
    push    cs
    pop     es
do_ls:
    mov     ax, 5
    mov     cx, 4
    int     0x80                        ; open
    cmp     ax, -1
    je      exit
    mov     bx, ax
    push    cs
    pop     es
rp_ls:
    mov     ax, 3
    mov     cx, buf
    mov     dx, 32
    int     0x80
    or      ax, ax
    jz      rp_ok

    cmp     byte [h], 1
    je      ls_hidden
    test    byte [buf+file_flags], F_HIDDEN
    jnz     rp_ls
ls_hidden:
    push    word buf+file_name
    mov     si, fmt
    call    print
    jmp     rp_ls
rp_ok:
    mov     ax, 6
    int     0x80                        ; close fd
    mov     word [code], 0
exit:
    mov     ax, 1
    mov     bx, [code]
    int     0x80                        ; exit

%include "tools/opt.asm"
%include "tools/print.asm"

h           db 0
current     db ".", 0
fmt         db "#s", 13, 10, 0
buf         resb 32
code        dw -1
