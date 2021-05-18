;
; masterboot.asm
;

[bits 16]

LOADOFF     equ 0x7c00                  ; bios puts masterboot here
BOOTOFF     equ 0x0500                  ; masterboot copies itself here (first free memory)

ALLOCSEG    equ 0x6000
MBTSEG      equ 0x0200
MUNIXSEG    equ 0x7000                  ; /boot/munix.sys
INITSEG     equ 0x0100                  ; /boot/init.sys

header      resb 16                     ; set up by tools/build
sign        equ header+2
munix_sys   equ header+12
init_sys    equ header+14

    xor     ax, ax
    mov     ds, ax
    mov     es, ax
    mov     si, LOADOFF
    mov     di, BOOTOFF
    mov     cx, 256
    cld
    rep
    movsw
    jmp    BOOTOFF/16:init              ; migrate to INITOFF
init:
    mov     ax, cs
    mov     ds, ax
    mov     es, ax
    cli
    mov     ss, ax
    mov     sp, 0x400                   ; assume stack is [0x700-0x900]
    sti
    mov     si, sign
    mov     cx, 10
    call    print

    mov     [dev], dl
    call    reset
    mov     ah, 0x08
    int     0x13                        ; get drive parameters
    jc      bad_disk
    and     cl, 0x3f                    ; sectors per track
    mov     [sectors], cl
    inc     dh                          ; nr heads
    mov     [heads], dh
    
    mov     ax, MBTSEG
    mov     fs, ax
    mov     es, ax
    xor     bx, bx
    xor     dx, dx
    mov     ax, 1
    call    read_block
    inc     ax
    call    read_block
    inc     ax
    call    read_block                  ; now, MBT is set up

    mov     ax, [munix_sys]
    push    MUNIXSEG
    pop     es
    xor     bx, bx
    call    read_file                   ; load munix.sys

    mov     ax, [init_sys]
    push    INITSEG
    pop     es
    xor     bx, bx
    call    read_file                   ; load init.sys
    
    mov     dl, [dev]
    jmp     MUNIXSEG:0

; input: ax=first block within file, es:bx buffer
read_file:
    cmp     ax, 0xfff
    je      last_block
    call    read_block
    push    bx
    push    ax
    mov     bx, ax
    shr     bx, 1
    add     bx, ax                      ; bx=ax*1.5
    mov     ax, [fs:bx]
    pop     bx
    test    bx, 1
    pop     bx
    jnz     next_odd
    and     ax, 0xfff
    jmp     read_file
next_odd:
    shr     ax, 4
    jmp     read_file
last_block:
    ret


; input: ax=block number, es:bx buffer
; output: es:bx end of buffer
read_block:
    push    ax
    mov     word [block], 4
    mul     word [block]                ; dx ax=lba
rp_read:
    call    read_sec
    inc     ax
    jnc     rp_ok
    inc     dx
rp_ok:
    add     bx, 512
    dec     word [block]
    jnz     rp_read
    pop     ax
    ret
block       dw 0


; input: dx ax=sector, es:bx buffer
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
    mov     dl, [dev]
    mov     ax, 0x0201
    int     0x13
    pop     es
    popa
    jnc     read_ok
    dec     byte [read_errs]
    jz      read_error
    call    reset
    jmp     read_sec
read_ok:
    ret

reset:
    push    ax
    xor     ah, ah
    int     0x13
    jc      bad_disk
    pop     ax
    ret

print:                                  ; input: si=msg, cx=length
    lodsb
    mov     ah, 0x0e
    int     0x10
    loop    print
    ret

bad_disk:
    mov     ax, 0x4442                  ; BD
    jmp     die
read_error:
    mov     ax, 0x4552                  ; RE
die:
   mov     [errno], ax
breakpoint:
   push    cs
   pop     es
   mov     si, err_msg
   mov     cx, err_end-err_msg
   call    print
   jmp     $

dev         db 0
sectors     db 0                        ; sectors per track
heads       db 0                        ; nr heads
read_errs   db 255
root        dw 0                        ; number of root dir entries

err_msg     db "Booting failed (Error #"
errno       db "BP). Press Ctrl+Alt+Del to reboot"
err_end:
