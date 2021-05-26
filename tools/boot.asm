;
; boot.asm
; loads munix.sys and drivers and initializes them
; possible errors: BD:bad disk, DF:diver failed, RE:read error, BP:breakpoint
; for breakpoint, use 'jmp break'. breakpoint in boot doesn't pause the program, but stop it.
;
; the boot is well-optimized (i guess), it's size is 391 bytes (max size is 398 bytes)
; though, you can decrease number of drivers (it's 16 by default) to get extra space for source code

%include "config.asm"

LOADSEG equ     0x07c0
DRV_MAX equ     16                      ; must be equal to DRV_MAX in tools/mkfs.c

header  resb    16                      ; header is set up by tools/mkfs
drivers resw    DRV_MAX                 ; also is set up by tools/mkfs

signlen equ     10
sign    equ     header+2
munix   equ     header+12
drv_nr  equ     header+14

        section .code
        mov     ax, INITSEG
        cli
        mov     ss, ax
        mov     sp, 0x400               ; assuming, boot stack is [0x700-0x900]
        sti
        mov     es, ax
        push    LOADSEG
        pop     ds
        push    BUFSEG
        pop     fs
        xor     di, di
        xor     si, si
        mov     cx, 256
        cld
        rep
        movsw
        jmp     INITSEG:init            ; copy and migrate to INITSEG
init:   push    cs
        pop     ds
        mov     si, sign
        mov     cx, signlen
        call    print

        mov     [dev], dl
        call    reset
        mov     ah, 0x08
        int     0x13                    ; get drive parameters
        jc      bddsk
        and     cl, 0x3f                ; sectors per track
        mov     [sectors], cl
        inc     dh                      ; nr heads
        mov     [heads], dh

        push    fs                      ; load MBT
        pop     es
        mov     cx, 3                   ; max MBT size is 3 blocks
        xor     bx, bx
        mov     ax, 1
.1:     call    read_block
        inc     ax
        loop    .1

        push    KERNSEG
        pop     es
        xor     bx, bx
        mov     ax, [munix]
        call    read_file               ; load munix

        mov     cx, [drv_nr]
        mov     si, drivers
        push    DRVSEG
        pop     es
.2:     xor     bx, bx
        lodsw
        call    read_file
        cmp     byte [es:0], 0x7f       ; driver magic
        jne     drvfl
        mov     ax, es
        mov     [drvjmp+2], ax
        pusha
        push    ds
        push    es
        mov     ds, ax
        mov     es, ax
        call    far [cs:drvjmp]         ; initialize driver
        or      ah, ah
        jnz     drvfl
        pop     es
        pop     ds
        popa
        add     ax, 0x0100
        mov     es, ax                  ; next 4K page
        loop    .2
        
        mov     dl, [dev]
        jmp     KERNSEG:16

; input: ax=entry number
; output: ax=entry value
get_mbt_entry:
        push    bx
        push    ax
        mov     bx, ax
        shr     bx, 1
        add     bx, ax                  ; bx=ax*1.5
        mov     ax, [fs:bx]
        pop     bx
        test    bx, 1
        pop     bx
        jnz     .odd
        and     ax, 0xfff
        ret
.odd:   shr     ax, 4
        ret

; input: ax=block, es:bx=buffer
; output: es:bx next buffer
read_block:
        push    ax
        push    cx
        mov     cx, BLOCK / 512
        shl     ax, BLOCK_LOG - SECTOR_LOG
.rp:    pusha                           ; read one sector
        xor     dx, dx
        div     word [sectors]          ; ax=cyl,head, dx=sector-1
        mov     cx, dx
        inc     cx
        xor     dx, dx
        div     word [heads]            ; ax=cylinder, dx=head, cx=sector
        mov     ch, al
        shl     ah, 6
        or      cl, al                  ; cx=cyl,sec
        shl     dx, 8                   ; dh=head
        mov     dl, [dev]
.1:     mov     ax, 0x0201
        int     0x13
        jnc     .2
        dec     byte [errs]
        jz      rderr
        call    reset
        jmp     .1
.2:     mov     ax, es
        add     ax, 0x20
        mov     es, ax
        popa
        inc     ax
        loop    .rp
        pop     cx
        pop     ax
        ret

; input: ax=first block, es:bx=buffer
; output: ax=-1, di=last block within file
read_file:
        push    es
.1:     cmp     ax, 0xfff
        je      .ret
        cmp     ax, 3
        jbe     bddsk
        call    read_block
        call    get_mbt_entry
        jmp     .1
.ret:   pop     es
        ret

reset:  xor     ah, ah
        int     0x13
        jc      bddsk
        ret

; input: si=msg,cx=len
; output: ax=?, cx=0, si=end of msg
print:  cs lodsb
        mov     ah, 0x0e
        int     0x10
        loop    print
        ret

bddsk:  mov     ax, 0x4442              ; 'BD'
        jmp     die
drvfl:  mov     ax, 0x4644              ; 'DF'
        jmp     die
rderr:  mov     ax, 0x4552              ; 'RE'
die:    mov     [cs:error], ax
break:  mov     si, errmsg              ; 'BP'
        mov     cx, errlen
        call    print
        jmp     $
        
        section .data
sectors dw      0
heads   dw      0
dev     db      0
errs    db      255
drvjmp  dw      16, 0
errmsg  db      13, 10, "Boot error #"
error   db      "BP. Press Ctrl+Alt+Del to reboot"
errlen  equ     $-errmsg
