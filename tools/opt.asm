; input: es:si=argv, cx=argc
; output: bx=opt ptr, al=opt (if not opt, al=0), es:si=next opt
get_opt:
    mov     bx, si
    dec     cx
    es lodsb
    cmp     al, '-'
    jne     skip_opt
    es lodsb
    inc     si
    ret

skip_opt:
    es lodsb
    or      al, al
    jnz     skip_opt
    dec     cx
    ret
