    cld
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
    mov     cx, 4
    int     0x80                        ; open
    cmp     ax, -1
    je      exit
    mov     [fd], ax
    push    cs
    pop     es

rp_dump:
    dec     word [iter]
    jnz     dump_cont
    mov     word [iter], 16
    int     0x23
    mov     al, 8
    int     0x24
dump_cont:
    mov     ax, 3
    mov     bx, [fd]
    mov     cx, buf
    mov     dx, 16
    int     0x80
    or      ax, ax
    jz      rp_ok

    mov     cx, 16
    sub     cx, ax
    mov     di, buf
    add     di, ax
    xor     al, al
    cld
    rep
    stosb
    mov     si, buf+15

    xor     ah, ah
    std

    mov     cx, 16
push_s:
    lodsb
    cmp     al, ' '
    jae     s1
    mov     al, '.'
s1:
    cmp     al, 127
    jbe     s2
    mov     al, '.'
s2:
    push    ax
    loop    push_s

    add     si, 16
    mov     cx, 16
push_i:
    lodsb
    push    ax
    loop    push_i

    push    word [pos]
    mov     si, fmt
    call    print
    add     word [pos], 16
    jmp     rp_dump
rp_ok:
    mov     ax, 6
    int     0x80                        ; close fd
    mov     word [code], 0
exit:
    mov     ax, 1
    mov     bx, [code]
    int     0x80                        ; exit

fd          dw 0
pos         dw 0
iter        dw 16
fmt         db "#4x  #2x #2x #2x #2x #2x #2x #2x #2x  #2x #2x #2x #2x #2x #2x #2x #2x  |#c#c#c#c#c#c#c#c#c#c#c#c#c#c#c#c|", 13, 10, 0
buf         resb 16
code        dw -1

%include "tools/print.asm"
