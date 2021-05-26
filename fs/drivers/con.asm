SCRSEG  equ     0xb800
LINES   equ     25
COLUMNS equ     80
SCRSIZE equ     LINES*COLUMNS*2
NPAR    equ     16

SHIFT   equ     0x40

header  resb    16
        section .code
init:   mov     ah, 0x03
        xor     bh, bh
        int     0x10                    ; get cursor pos
        mov     [x], dl
        mov     [y], dh
        call    setpos
        push    0
        pop     ds
        cli
        mov     word [0x09*4], key_int
        mov     word [0x09*4+2], cs
        mov     word [0x24*4], cons_int
        mov     word [0x24*4+2], cs
        sti
        xor     ah, ah                  ; return code
        retf

key_int:
        cli
        push    ds
        push    ax
        push    bx
        push    cs
        pop     ds
        in      al, 0x60                ; key
        test    al, 0x80                ; check release bit
        jz      key1
        or      byte [kstat], 0x80
        and     al, 0x7f
        jmp     stkey
key1:   and     byte [kstat], 0x7f
        xor     ah, ah
        mov     bx, ax
        test    byte [kstat], SHIFT
        jnz     sshift
        mov     cl, scanset[bx]
        jmp     chkk
sshift: mov     cl, shiftset[bx]
chkk:   cmp     cl, 128
        ja      stkey
        mov     [keyc], cl
        jmp     keyret
stkey:  cmp     al, 0x2a                ; left shift
        jne     kshift
        mov     al, SHIFT
        call    chgstat
kshift:
keyret: pop     bx
        pop     ax
        pop     ds
        mov     al, 0x20
        out     0x20, al
        sti
        iret

chgstat:                                ; input: al=status bit
        test    byte [kstat], 0x80
        jnz     statrl
        or      byte [kstat], al
        ret
statrl: mov     byte [kstat], 0
        not     al
        and     byte [kstat], al
        ret

; ah=0: clear
; ah=1: put char: input: al=char
; ah=2: get char: output: al=char
; ah=3: write: input: gs:bx=msg, cx=len (cx=0 any length)
; ah=4: read: input: gs:bx=buf, cx=len
cons_int:
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        push    gs
        push    cs
        pop     ds
        push    SCRSEG
        pop     es
        push    bx
        cmp     ah, 4
        ja      .ret
        mov     bl, ah
        xor     bh, bh
        mov     si, bx
        shl     si, 1
        pop     bx
        call    inttab[si]
        call    setcur
.ret:   pop     gs
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        iret

clear:  push    ax
        mov     ax, 0x0720
        mov     cx, LINES*COLUMNS
        xor     di, di
        mov     [x], di
        mov     [y], di
        mov     [pos], di
        cld
        rep
        stosw
        pop     ax
        ret

bs:     push    di
        dec     word [pos]
        mov     di, [pos]
        shl     di, 1
        mov     word [es:di], 0x0720
        dec     byte [x]
        jns     bsret
        mov     byte [x], COLUMNS-1
        dec     byte [y]
        jns     bsret
        call    scdown
bsret:  pop     di
        ret

tab:    add     byte [x], 8
        and     byte [x], ~7
        add     word [pos], 8
        and     word [pos], ~7
        cmp     byte [x], COLUMNS
        jb      .ret
        call    lf
        call    cr
.ret:   ret

savecur:
        push    word [x]
        pop     word [sx]
        push    word [y]
        pop     word [sy]
        ret

restcur:
        push    word [sx]
        pop     word [x]
        push    word [sy]
        pop     word [y]
        jmp     setpos

lf:     cmp     byte [y], LINES-1
        je      scup
        add     word [pos], COLUMNS
        inc     byte [y]
        ret

ri:     cmp     byte [y], 0
        je      scdown
        sub     word [pos], COLUMNS
        dec     byte [y]
        ret

cr:     push    ax
        mov     ax, [x]
        sub     [pos], ax
        sub     [x], ax
        pop     ax
        ret
        
scup:   push    di
        push    si
        push    cx
        push    ds
        push    word SCRSEG
        pop     ds
        xor     di, di
        mov     si, COLUMNS*2
        mov     cx, SCRSIZE-COLUMNS*2
        cld
        rep
        movsb
        mov     cx, COLUMNS
        mov     ax, 0x0720
        rep
        stosw
        pop     ds
        pop     cx
        pop     si
        pop     di
        ret

scdown: ret

; input: al=char
putc:   cmp     byte [state], 1
        je      p1
        cmp     byte [state], 2
        je      p2
        cmp     byte [state], 3
        je      p3
        cmp     byte [state], 4
        je      p4
        cmp     al, 0x20
        jb      psys
        mov     di, [pos]
        shl     di, 1
        push    ax
        mov     ah, [attr]
        stosw
        pop     ax
        jmp     incpos
psys:   cmp     al, 8                   ; backspace
        je      bs
        cmp     al, 9                   ; tab
        je      tab
        cmp     al, 10                  ; lf
        je      lf
        cmp     al, 11
        je      lf
        cmp     al, 12
        je      lf
        cmp     al, 13                  ; cr
        je      cr
        cmp     al, 27                  ; esc
        jne     pret1                   ; unknown char
        inc     byte [state]
pret1:  ret
p1:     cmp     al, '['
        jne     do_p1
        inc     byte [state]
        mov     word [pars], 0
        ret
do_p1:  mov     byte [state], 0
        cmp     al, 'E'
        jne     esc_E
        call    lf
        call    cr
        ret
esc_E:  cmp     al, 'D'
        je      lf
        cmp     al, 'M'
        je      ri
        cmp     al, '7'
        je      savecur
        cmp     al, '8'
        je      restcur
pret2:  ret
p2:     mov     cx, NPAR
        mov     di, par
        push    es
        push    ds
        pop     es
        push    ax
        xor     ax, ax
        cld
        rep
        stosb
        pop     ax
        pop     es
        mov     [pars], cx
        inc     byte [state]
p3:     cmp     al, '9'
        ja      p3end
        push    ax
        sub     al, '0'
        mov     bl, 10
        xor     ah, ah
        mov     dx, ax
        mov     di, [pars]
        mov     ax, [di+par]
        mul     bl
        add     ax, dx
        mov     [di+par], al
        pop     ax
        ret
p3end:  inc     word [pars]
        cmp     al, ';'
        je      pret2
p4:     mov     byte [state], 0
        cmp     al, 'm'
        je      csi_m
        ret

csi_m:  push    ax
mrp:    dec     word [pars]
        js      cret
        mov     bx, word [pars]
        mov     al, [par+bx]
        or      al, al
        jne     mcl
        mov     byte [attr], 0x07
        jmp     mend
mcl:    cmp     al, 1
        jne     msb
        or      byte [attr], 8
        jmp     mend
msb:    cmp     al, 2
        jne     mst
        and     byte [attr], ~8
        jmp     mend
mst:    cmp     al, 30
        jb      msfr
        cmp     al, 37
        ja      msfr
        sub     al, 30
        and     byte [attr], ~7
        or      byte [attr], al
        jmp     mend
msfr:
        jmp     mend
mend:   jmp     mrp
cret:   pop     ax
        ret

; output: al=char
getc:   cli
        mov     al, [keyc]
        or      al, al
        sti
        jz      getc                    ; wait for input
        mov     byte [keyc], 0
        ret

; input: gs:bx=msg, cx=count
write:  push    ax
        mov     si, bx
.1:     gs lodsb
        or      al, al
        jz      .ret
        call    putc
        loop    .1
.ret:   pop     ax
        ret

; input: gs:bx=buffer, cx=count
read:   push    ax
.1:     call    getc
        mov     [gs:bx], al
        inc     bx
        loop    .1
        pop     ax
        ret

incpos: inc     word [pos]
        inc     byte [x]
        cmp     byte [x], COLUMNS
        jne     .ret
        mov     byte [x], 0
        cmp     byte [y], LINES-1
        jne     .1
        sub     word [pos], COLUMNS
        jmp     scup
.1:     inc     byte [y]
.ret:   ret

setcur: push    ax
        push    dx
        mov     dx, 0x3d4
        mov     al, 0xf
        out     dx, al
        mov     dx, 0x3d5
        mov     al, [pos]
        out     dx, al
        mov     dx, 0x3d4
        mov     al, 0xe
        out     dx, al
        mov     dx, 0x3d5
        mov     al, [pos+1]
        out     dx, al
        pop     dx
        pop     ax
        ret

setpos: mov     ax, [y]
        mov     cl, COLUMNS
        mul     cl
        add     ax, [x]
        mov     [pos], ax
        ret

        section .data
inttab  dw      clear, putc, getc, write, read
scanset:
        db      -1, 27, "1234567890-=", 8, 9
        db      "qwertyuiop[]", 13, -1  ; left ctrl unimplemented
        db      "asdfghjkl;'`", -1      ; left shift
        db      "\zxcvbnm,./", -1       ; right shift
        db      "*", -1                 ; left alt
        db      " ", -1                 ; caps lock
        db      -1, -1, -1, -1, -1      ; F1-F5
        db      -1, -1, -1, -1, -1      ; F6-F10
        db      -1, -1                  ; numlock, scrlock
        db      "789-456+1230."
        db      -1, -1, -1, -1, -1, -1, -1, -1
        times   128-($-scanset) db -1
shiftset:
        db      -1, 27, "!@#$%^&*()_+", 8, 9
        db      "QWERTYUIOP{}", 13, -1
        db      "ASDFGHJKL:", 0x22, "~", -1
        db      "|ZXCVBNM<>?", -1
        db      "*", -1                 ; left alt
        db      " ", -1                 ; caps lock
        db      -1, -1, -1, -1, -1      ; F1-F5
        db      -1, -1, -1, -1, -1      ; F6-F10
        db      -1, -1                  ; numlock, scrlock
        db      "789-456+1230."
        db      -1, -1, -1, -1, -1, -1, -1, -1
        times   128-($-shiftset) db -1

attr    db      0x07
state   db      0                       ; 0=default,1=esc,2=clear par-list,3=read par,4=csi
x       dw      0
y       dw      0
sx      dw      0
sy      dw      0
pos     dw      0
keyc    db      0
kstat   db      0                       ; rs------, (r)eleased, (s)hift
pars    dw      0
par     resb    NPAR
