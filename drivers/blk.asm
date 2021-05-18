;
; blk.asm
;
; driver for block drivers

BLOCK       equ 4                       ; sectors per block

; input: dl=disk number
blk_init:
    push    ax
    push    bx
    call    setup_disk
    mov     ax, read_block
    mov     bx, 0x21
    call    set_int
    pop     bx
    pop     ax
    ret

; input: dl=device
setup_disk:
    mov     [root_dev], dl
    push    di
    push    es
    call    reset
    mov     ah, 0x08
    int     0x13                        ; get drive parameters
    pop     es
    pop     di
    and     cl, 0x3f                    ; sectors per track
    mov     [sectors], cl
    inc     dh                          ; nr heads
    mov     [heads], dh
    ret

reset:
    push    di
    push    es
    push    ax
    xor     ah, ah
    int     0x13
    pop     ax
    pop     es
    pop     di
    ret

;
; INT 0x21
;
; read block
; input: ax=block number, gs:bx=buffer
; output: ax=error
read_block:
    push    ds
    push    es
    push    cs
    pop     ds
    push    gs
    pop     es
    push    dx
    push    bx
    mov     byte [nr_reads], 255
    mov     word [block], BLOCK
    mul     word [block]                ; dx ax=lba
rp_read:
    dec     byte [nr_reads]
    jz      bad_read
    call    read_sec
    jc      rp_read
    inc     ax
    jnc     rp_ok
    inc     dx
rp_ok:
    add     bx, 512
    dec     word [block]
    jnz     rp_read
    xor     ax, ax
    jmp     ret_read
bad_read:
    mov     ax, -1
ret_read:
    pop     bx
    pop     dx
    pop     es
    pop     ds
    iret
block       dw 0


; input: dx ax=sector, es:bx buffer
; output: CF if error
read_sec:
    pusha
    push    es
    push    bx
    mov     cl, [sectors]
    push    ax
    mov     al, cl
    mul     byte [heads]                ; ax=sectors*heads
    mov     bx, ax
    pop     ax
    div     bx                          ; ax=cyl dx=sec within syl
    xchg    ax, dx
    mov     ch, dl                      ; ch=[7..0]cyl
    div     cl                          ; al=head ah=sec
    mov     cl, ah                      ; cl=sec
    inc     cl                          ; +1 as first sctor is 1
    xor     dl, dl
    shr     dx, 2
    or      cl, dl                      ; cl=[9..8]cyl,[5..0]sec
    mov     dh, al                      ; dh=head
    pop     bx
    mov     dl, [root_dev]
    mov     ax, 0x0201
    int     0x13
    pop     es
    popa
    ret

nr_reads    db 0

root_dev    db 0
sectors     dw 0
heads       dw 0
munix_block dw 0
