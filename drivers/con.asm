;
; con.asm
; provides console input/output functions
;

con_init:
    push    ax
    push    bx
    mov     ax, con_in
    mov     bx, 0x23
    call    set_int
    mov     ax, con_out
    mov     bx, 0x24
    call    set_int
    pop     bx
    pop     ax
    ret

; output: al=read symbol, ah=extended ascii
con_in:
    xor     ah, ah
    int     0x16
    int     0x24
    iret

; input: al=symbol to put on screen
con_out:
    push    ax
    mov     ah, 0x0e
    int     0x10
    pop     ax
    iret
