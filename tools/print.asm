; input: si=str, ds=es=cs
; output: si=end of str
print:
    pop     word [pr_ret]
    mov     [pr_ax], ax
    mov     [pr_bx], bx
    mov     [pr_cx], cx
    mov     [pr_di], di
pr_next:
    cld
    lodsb
    or      al, al
    jz      pr_do_ret
    cmp     al, '#'
    jne     pr_out
    call    skip_atoi
    lodsb
    cmp     al, 's'
    je      pr_s
    cmp     al, 'd'
    je      pr_d
    cmp     al, 'x'
    je      pr_x
    cmp     al, 'c'
    je      pr_c
pr_out:
    int     0x24
    jmp     pr_next
pr_do_ret:
    mov     ax, [pr_ax]
    mov     bx, [pr_bx]
    mov     cx, [pr_cx]
    mov     di, [pr_di]
    jmp     [pr_ret]

pr_s:
    cld
    or      cx, cx
    jnz     pr_s1
    mov     cx, 0xffff
pr_s1:
    mov     [pr_si], si
    pop     si
pr_s_next:
    lodsb
    or      al, al
    jz      pr_s_done
    cmp     al, '@'
    je      pr_s_next
    int     0x24
    loop    pr_s_next
pr_s_done:
    mov     si, [pr_si]
    jmp     pr_next

pr_d:
    mov     word [pr_i_n], 10
    jmp     pr_i
pr_x:
    mov     word [pr_i_n], 16
pr_i:
    pop     ax
    push    bx
    push    dx
    mov     di, intbuf+8
    std
pr_i_next:
    xor     dx, dx
    div     word [pr_i_n]
    mov     bx, dx
    push    ax
    mov     al, intstr[bx]
    stosb
    pop     ax
    cmp     cx, 1
    jbe     pr_i1
    dec     cx
    jmp     pr_i_next
pr_i1:
    or      ax, ax
    jnz     pr_i_next
pr_i_done:
    pop     dx
    pop     bx
    inc     di
    push    di
    xor     cx, cx
    jmp     pr_s

pr_c:
    pop     ax
    jmp     pr_out

; output: cx=int
skip_atoi:
    push    ax
    xor     ax, ax
skip_next:
    mov     cx, ax
    lodsb
    cmp     ax, '0'
    jb      skip_done
    cmp     ax, '9'
    ja      skip_done
    xchg    ax, cx
    mul     byte [skip_10]
    add     ax, cx
    sub     ax, '0'
    jmp     skip_next
skip_done:
    dec     si
    pop     ax
    ret

pr_i_n      dw 0
pr_ret      dw 0
pr_ax       dw 0
pr_bx       dw 0
pr_cx       dw 0
pr_si       dw 0
pr_di       dw 0
intbuf      resb 10
skip_10     db 10
intstr      db "0123456789abcdef"
