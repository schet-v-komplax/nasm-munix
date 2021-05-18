MAXINTLEN   equ 9

intstr      db "0123456789abcdef"
dump_fmt    db "#4x:#4x  #2x #2x #2x #2x #2x #2x #2x #2x  #2x #2x #2x #2x #2x #2x #2x #2x  |#c#c#c#c#c#c#c#c#c#c#c#c#c#c#c#c| ", 0
bp_msg      db 13, 10, "breakpoint ###d", 13, 10
            db "  ax      bx      cx      dx      si      di", 13, 10
            db "#4x    #4x    #4x    #4x    #4x    #4x", 13, 10
            db "  cs      ds      es      fs      gs", 13, 10
            db "#4x    #4x    #4x    #4x    #4x", 13, 10
            db "ss:sp #4x:#4x", 13, 10
            db "cs:ip #4x:#4x", 13, 10
            db "flags #4x", 13, 10, 0
intbuf      times MAXINTLEN db 0
bp_ip       dw 0
bp_cs       dw 0
bp_flags    dw 0
pr_reta     dw 0
pri_iter    dw 0
brks        dw 0

; input: si=str
; format: #o #d #x adjust word from stack (octal, decimal, hexadecimal), #s str, #c char [2-byte align]
printk:
    pop     word [pr_reta]
    cld
pr_fmt:
    xor     ax, ax
    mov     [pri_iter], ax
    lodsb
    or      al, al
    jz      pr_ret
    cmp     al, '#'
    jne     pr_out
    lodsb
    cmp     al, '0'
    jb      pr_fmt2
    cmp     al, '9'
    ja      pr_fmt2
    sub     al, '0'
    mov     [pri_iter], al
    lodsb
pr_fmt2:
    cmp     al, 'c'
    je      print_char
    cmp     al, 's'
    je      print_str
    cmp     al, 'o'
    je      print8
    cmp     al, 'd'
    je      print10
    cmp     al, 'x'
    je      print16
pr_out:
    int     0x24
    jmp     pr_fmt
pr_ret:
    jmp     [pr_reta]

print_char:
    pop     ax
    jmp     pr_out

print_str:
    pop     di
    xchg    di, si
prs_out:
    lodsb
    or      al, al
    jz      prs_ret
    int     0x24
    jmp     prs_out
prs_ret:
    mov     si, di
    jmp     pr_fmt

print8:
    mov     cx, 8
    jmp     print_int
print10:
    mov     cx, 10
    jmp     print_int
print16:
    mov     cx, 16
print_int:
    pop     ax
    std
    mov     di, intbuf+MAXINTLEN-2              ; intbuf[8]=0 always
pri_fmt:
    xor     dx, dx
    div     cx
    mov     bx, dx
    push    ax
    mov     al, intstr[bx]
    stosb
    pop     ax
    test    word [pri_iter], 0xffff
    jz      pri_ok
    dec     word [pri_iter]
    jnz     pri_fmt
pri_ok:
    or      ax, ax
    jnz     pri_fmt
    cld
    inc     di
    push    di
    jmp     print_str

nlcr:
    push    ax
    mov     al, 0x0a
    int     0x24
    mov     ax, 0x0d
    int     0x24
    pop     ax
    ret

breakpoint:
    pop     word [cs:bp_ip]
    pop     word [cs:bp_cs]
    pop     word [cs:bp_flags]
    push    ds
    push    es
    pusha
    push    word [cs:bp_flags]
    push    word [cs:bp_ip]
    push    word [cs:bp_cs]
    push    sp
    push    ss
    push    gs
    push    fs
    push    es
    push    ds
    push    cs
    push    di
    push    si
    push    dx
    push    cx
    push    bx
    push    ax
    inc     word [cs:brks]
    push    word [cs:brks]
    mov     si, bp_msg
    push    cs
    pop     es
    push    cs
    pop     ds
    call    printk
    xor     ah, ah
    int     0x16
    popa
    pop     es
    pop     ds
    push    word [cs:bp_flags]
    push    word [cs:bp_cs]
    push    word [cs:bp_ip]
    iret

; input: gs:bx address, dx number of lines to dump
memory_dump:
    pusha
    push    es
    push    ds
    pop     es
memory_dump1:
    push    dx
    push    cx
    push    bx
    mov     si, bx
    xor     ah, ah
    std

    add     si, 15
    mov     cx, 16
md_push_s:
 gs lodsb
    cmp     al, ' '
    jae     mds1
    mov     al, '.'
mds1:
    cmp     al, 127
    jbe     mds2
    mov     al, '.'
mds2:
    push    ax
    loop    md_push_s

    add     si, 16
    mov     cx, 16
md_push_i:
 gs lodsb
    push    ax
    loop    md_push_i

    push    bx
    push    gs
    mov     si, dump_fmt
    call    printk
    pop     bx
    pop     cx
    pop     dx
    add     bx, 16
    dec     dx
    jnz     memory_dump1
    pop     es
    popa
    ret
