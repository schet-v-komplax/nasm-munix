sys_init:
    push    ax
    push    bx
    mov     ax, sys_call
    mov     bx, 0x80
    call    set_int
    pop     bx
    pop     ax
    ret

sys_err:
    mov     ax, -1
    ret

; input: ax=syscall, bx,cx,dx=args, es=data segment
; output: ax=error
sys_call:
    pushf
    push    ds
    push    fs
    push    gs
    push    word 0
    popf
    push    cs
    pop     ds
    push    MBTSEG
    pop     fs
    push    ALLOCSEG
    pop     gs
    cmp     ax, NR_SYSCALLS
    jb      sys_ok
    mov     ax, sys_err
    jmp     sys_do_call
sys_ok:
    shl     ax, 1
    add     ax, syscall_table
sys_do_call:
    push    si
    mov     si, ax
    call    [si]
    pop     si
    pop     gs
    pop     fs
    pop     ds
    popf
    iret
