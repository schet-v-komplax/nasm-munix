%include "config.asm"

header  resb    16
        section .code
init:   push    0
        pop     ds
        xor     ah, ah
        call    reset
        cli
        mov     word [0x23*4], blk_int
        mov     word [0x23*4+2], cs
        sti
        xor     ah, ah                  ; return code
        retf

; ah=0: reset system
; ah=1: initialize disk: input: dl=disk, output: al=disk handler
; ah=3: write block input: al=disk handler, es:bx=buffer, dx=block
; ah=4: read block: input: al=disk handler, es:bx=buffer, dx=block
; output: ah=error
blk_int:
        push    es
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    cs
        pop     ds
        cmp     ah, 4
        ja      .err
        push    bx
        mov     bl, ah
        xor     bh, bh
        mov     si, bx
        shl     si, 1
        pop     bx
        push    .ret
        jmp     inttab[si]
.err:   mov     ah, -1
.ret:   pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     es
        iret

reset:  xor     ah, ah
        int     0x13
        push    es
        push    cs
        pop     es
        mov     di, disktab
        xor     ax, ax
        mov     cx, diskdata_size * NR_DISKS
        cld
        rep
        stosb
        pop     es
        ret

; inpit: dl=disk
; output: al=disk handler
initdisk:
        xor     si, si
.find:  cmp     si, diskdata_size*NR_DISKS
        je      .err
        cmp     byte [si+disktab+d_flags], 0
        je      .1
        add     si, diskdata_size
        jmp     .find
.1:     mov     ah, 0x08
        mov     byte [si+disktab+d_flags], 1
        mov     [si+disktab+d_disk], dl
        int     0x13                    ; get drive parameters
        jc      .err
        push    cx
        and     cx, 0x3f                ; sectors per track
        mov     [si+disktab+d_sectors], cx
        pop     cx
        shr     cx, 6                   ; cylinders
        mov     [si+disktab+d_cylinders], cx
        inc     dh                      ; nr heads
        xor     dl, dl
        mov     [si+disktab+d_heads], dx
        mov     ax, si
        jmp     .ret
.err:   mov     ah, -1
.ret    ret

write_block:
        mov     byte [rw], 3
        jmp     rw_block
read_block:
        mov     byte [rw], 2

; input: al=disk handler, dx=block, es:bx=buffer, rw=2 for read, rw=3 for write
rw_block:
        mov     byte [errs], 16
        mov     cx, BLOCK / 512
        push    ax
        xor     ah, ah
        mov     si, ax
        mov     ax, dx
        shl     ax, BLOCK_LOG - SECTOR_LOG
.rp:    pusha                           ; read one sector
        xor     dx, dx
        div     word [si+disktab+d_sectors]
        mov     cx, dx
        inc     cx
        xor     dx, dx
        div     word [si+disktab+d_heads]
        mov     ch, al
        shl     ah, 6
        or      cl, al                  ; cx=cyl,sec
        shl     dx, 8                   ; dh=head
        mov     dl, [si+disktab+d_disk]
.1:     mov     al, 0x01
        mov     ah, [rw]
        int     0x13
        jnc     .2
        dec     byte [errs]
        jz      .err
        call    reset
        jmp     .1
.2:     mov     ax, es
        add     ax, 0x20
        mov     es, ax
        popa
        inc     ax
        loop    .rp
        pop     ax
        xor     ah, ah
        jmp     .ret
.err:   popa
        pop     ax
        mov     ah, -1
.ret:   ret

bad:    mov     ah, -1
        ret

        section .data
inttab  dw      reset, initdisk, bad, write_block, read_block
errs    db      0
rw      db      0
disktab resb    diskdata_size*NR_DISKS
