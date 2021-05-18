%include "config.asm"

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
    push    cs
    pop     es
    mov     bx, ax
    mov     ax, 20
    mov     cx, buf
    int     0x80
    
    mov     ax, 6
    int     0x80

    mov     di, flags
    mov     al, '@'
    mov     bx, 0x80
rp_flags:
    test    bx, [buf+file_flags]
    jnz     flag
    mov     [di], al
flag:
    inc     di
    shr     bx, 1
    jnz     rp_flags

    push    word [buf+file_mtime]
    push    word [buf+file_mtime+2]
    push    word [buf+file_ctime]
    push    word [buf+file_ctime+2]
    push    word [buf+file_block]
    push    word [buf+file_count]
    push    word flags
    push    word buf+file_name
    mov     si, fmt
    call    print
    mov     word [code], 0
exit:
    mov     ax, 1
    mov     bx, [code]
    int     0x80                        ; exit

buf         resb 32
fmt         db "name    #15s", 13, 10, "flags   #s", 13, 10, "size    #d", 13, 10, "block   #d", 13, 10, "ctime   #x#4x", 13, 10, "mtime   #x#4x", 13, 10, 0
flags       dw "pdhl-rwx", 0
code        dw -1

%include "tools/print.asm"
