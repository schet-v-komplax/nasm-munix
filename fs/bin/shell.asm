    push    es
    pop     ds
    push    cs
    pop     es

    cmp     dx, 1
    jb      do_exit
    mov     di, home
    call    strcpy

    mov     ax, cs
    mov     ds, ax
    mov     es, ax
    call    nlcr
parse_com:
    xor     dx, dx
    push    home
    mov     si, line
    call    print
    mov     di, command
get:
    mov     ax, 11
    xor     bx, bx
    int     0x80                        ; read symbol
    cmp     al, 13
    je      command_ok
    cmp     al, ' '
    jne     not_space
    inc     dx
    xor     al, al
not_space:
    cmp     al, 8
    jne     not_back
    dec     di
    jmp     get
not_back:
    stosb
    jmp     get
command_ok:
    inc     dx
    xor     al, al
    stosb
    call    nlcr

    mov     di, command
    mov     si, exit
    call    strcmp
    or      ax, ax
    je      do_exit

    mov     di, command
    mov     si, cd
    call    strcmp
    or      ax, ax
    je      do_cd

    mov     ax, 5
    mov     bx, command
    mov     cx, 5                       ; r-x
    int     0x80
    cmp     ax, -1
    jne     exec_com

    mov     ax, 5
    mov     bx, bin_com
    mov     cx, 5                       ; r-x
    int     0x80
    cmp     ax, -1
    jne     exec_com

    mov     si, no_com
    call    print
    jmp     parse_com
exec_com:
    mov     bx, ax
    mov     ax, 7                       ; execute command
    mov     cx, command
    int     0x80
    or      ax, ax
    jz      parse_com
    push    ax
    push    command
    mov     si, end_com
    call    print
    jmp     parse_com

strcmp:
    cld
sc1:lodsb
	scasb
	jne     sc2
	or      al, al
	jne     sc1
	xor     ax, ax
    ret
sc2:mov     ax, 1
    ret

strcpy:
    cld
sp1:lodsb
    stosb
    or      al, al
    jnz     sp1
    ret

do_exit:
    mov     ax, 1
    xor     bx, bx
    int     0x80

do_cd:                                  ; di points to arg2
    cmp     dx, 1
    je      parse_com
    mov     si, di
    
    mov     ax, 9
    mov     bx, si
    mov     cx, 6
    mov     dx, 0
    int     0x80                        ; do cd
    cmp     ax, -1
    je      parse_com
    cld
    mov     di, home
    cmp     byte [si], '/'
    jne     cd_rel
    jmp     next_dir
cd_rel:
    xchg    di, si
cr: lodsb
    or      al, al
    jnz     cr
    dec     si
    xchg    di, si
next_dir:
dcp:lodsb
    stosb
    or      al, al
    jz      cp2
    cmp     al, '/'
    je      next_dir
    jmp     dcp
cp2:jmp     parse_com


nlcr:
    push    ax
    mov     al, 0x0a
    int     0x24
    mov     ax, 0x0d
    int     0x24
    pop     ax
    ret

%include "tools/print.asm"

line        db "[#s]## ", 0
end_com     db "#s executed with code #d", 13, 10, 0
no_com      db "command not found", 13, 10, 0

bin_com     db "/bin/"
command     resb 64
home        resb 64

cd          db "cd", 0
exit        db "exit", 0
