;
; init.asm
; contains munix startup code & some interrupts
;
;
[bits 16]

    mov     ax, cs
    mov     ds, ax
    mov     es, ax

    mov     ax, 5
    mov     bx, config
    mov     cx, 4                       ; r--
    int     0x80

    mov     bx, ax
    push    ax
    mov     ax, 3
    mov     cx, buf
    mov     dx, 0x800
    int     0x80

    mov     si, buf
parse_ops:
    mov     di, op1
parse_opa:
    lodsb
    or      al, al
    jz      parse_done
    cmp     al, ' '
    jbe     parse_opa
    cmp     al, '='
    je      parse_opa_ok
    stosb
    jmp     parse_opa
parse_opa_ok:
    xor     al, al
    stosb
    mov     di, op2
parse_opb:
    lodsb
    cmp     al, ' '
    jbe     parse_op
    stosb
    jmp     parse_opb
parse_op:
    xor     al, al
    stosb

    push    si
    mov     si, op1
    mov     di, op_shell
    call    strcmp
    pop     si
    or      ax, ax
    je      load_shell

    push    si
    mov     si, op1
    mov     di, op_home
    call    strcmp
    pop     si
    or      ax, ax
    je      load_home

    jmp     parse_ops
parse_done:
    mov     ax, 6
    pop     bx
    int     0x80

    mov     ax, 8                       ; execute shell
    mov     bx, [shell_fd]
    mov     cx, home_buf
    mov     dx, 1
    int     0x80
error:
    mov     si, msg
    mov     cx, msg-msg_end
    call    print
    jmp     $

load_shell:
    mov     ax, 5
    mov     bx, op2
    mov     cx, 5                       ; r-x
    int     0x80
    mov     [shell_fd], ax
    cmp     ax, -1
    je      error
    jmp     parse_ops

load_home:
    mov     ax, 9
    mov     bx, op2
    mov     cx, 6                       ; rw-
    mov     dx, 0
    int     0x80
    cmp     ax, -1
    je      error
    push    si
    mov     si, op2
    mov     di, home_buf
    call    strcpy
    pop     si
    jmp     parse_ops

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

print:
    cld
pr1:lodsb
    or      al, al
    jz      pr2
    int     0x24
    loop    pr1
pr2:ret

msg         db "init.sys: Press Ctrl+Alt+Del to reboot", 0
msg_end:
config      db "/boot/init.config", 0
buf         resb 0x800

op_shell    db "shell", 0
op_home     db "home", 0
shell_fd    dw 0

home_buf    resb 64
op1         resb 32
op2         resb 32
