%include "config.asm"
MUNIX   equ     TRUE

header  resb    16
        section .code
init:   push    0
        pop     ds
        mov     ax, cs
        cli
        mov     word [0x03*4], breakpoint
        mov     word [0x03*4+2], ax
        mov     word [0x21*4], syscall
        mov     word [0x21*4+2], ax
        mov     ss, ax
        xor     sp, sp                  ; stack start is the end of segment
        sti

        push    BUFSEG
        pop     fs
        mov     ax, cs
        mov     ds, ax
        mov     es, ax
        mov     gs, ax

        call    mount_disk

        call    nlcr
        mov     dx, 3
        mov     bx, buftab
        call    memory_dump

        call    fsstat
        jmp     $

%include "tools/debug.asm"

; input: ax=entry, dl=disk (disktab entry)
; output: ax=value
get_mbt_entry:
        push    bx
        push    ax
        mov     bx, ax
        shr     bx, 1
        add     bx, ax                  ; bx=ax*1.5
        push    si
        mov     si, bx
        and     bx, BLOCK-1
        shr     si, BLOCK_LOG
        shl     si, 1
        push    dx
        xor     dh, dh
        add     si, dx
        pop     dx
        mov     si, [si+disktab+d_mbt]
        shl     si, BLOCK_LOG-buffer_log
        mov     ax, [fs:si+bx]
        pop     si
        pop     bx
        test    bx, 1
        pop     bx
        jnz     .odd
        and     ax, 0xfff
        ret
.odd:   shr     ax, 4
        ret

; input: ax=block, bx=file
; outpus: si=buffer
get_buffer:
        xor     si, si
        push    cx
        push    dx
        mov     cx, -1                  ; free buffer
        mov     dx, -1                  ; freeable buffer
 .1:    cmp     si, buffer_size*NR_BUFFERS
        je      .3
        test    byte [si+buftab+b_flags], B_PRESENT
        jz      .get
        cmp     ax, [si+buftab+b_block]
        jne     .get
        push    ax
        mov     al, [si+buftab+b_disk]
        cmp     al, [bx+filetab+fd_disk]
        pop     ax
        je      .ret                    ; buffer is already exists (same block, same disk)
.get:   test    cx, cx
        jns     .2
        test    byte [si+buftab+b_flags], B_PRESENT
        jnz     .2
        mov     cx, si
        jmp     .loop
.2:     test    dx, dx
        jns     .loop
        test    byte [si+buftab+b_flags], B_KEEP
        jnz     .loop
        mov     dx, si
.loop:  add     si, buffer_size
        jmp     .1
.3:     test    cx, cx
        js      .5
        mov     si, cx                  ; free buffer found
.4:     mov     byte [si+buftab+b_flags], B_PRESENT
        mov     [si+buftab+b_fd], bx
        mov     [si+buftab+b_block], ax
        mov     cl, [bx+filetab+fd_disk]
        mov     [si+b_fd], cl
        mov     word [si+b_size], BLOCK
        push    ax
        mov     dx, ax
        mov     ah, 4
        push    bx
        mov     bl, [bx+fd_disk]
        xor     bh, bh
        mov     al, [bx+disktab+d_data]
        mov     bx, si
        shl     bx, BLOCK_LOG-buffer_log
        push    es
        push    fs
        pop     es
        int     0x23
        pop     es
        pop     bx
        test    ax, ax
        pop     ax
        js      .error
        jmp     .ret
.5:     test    dx, dx
        js      .error
        mov     si, dx                  ; freeable buffer found
        ;;;;;;;;;;;;;;;;;;;; FLUSH BUFFER ;;;;;;;;;;;;;;;;;;;;;
        jmp     .4
.error: mov     si, -1
.ret:   pop     dx
        pop     cx
        ret



; input: dl=disk real number
; output: dl=disktab entry
mount_disk:
        push    ax
        push    bx
        push    si
        push    di
        xor     di, di
.1:     cmp     di, disk_size*NR_DISKS  ; find free entry
        je      .error
        test    byte [di+disktab+d_present], 0xff
        jz      .2
        add     di, disk_size
        jmp     .1
.2      mov     ah, 1
        int     0x23                    ; initialize diskdata
        test    ah, ah
        js      .error
        mov     [di+disktab+d_disk], al
        xor     bx, bx                  ; preset for get_buffer
        mov     [filetab+fd_disk], al   ; for get_buffer
        mov     dx, di                  ; return value
        mov     ax, 1                   ; load MBT (1,2,3 blocks)
.3:     call    get_buffer
        test    si, si
        js      .error
        or      byte [si+buftab+b_flags], B_KEEP|B_FLUSH
        mov     [di+disktab+d_mbt], si
        add     di, 2
        inc     ax
        cmp     ax, 4
        jne     .3
        jmp     .ret
.error: mov     dl, -1
.ret:   pop     di
        pop     si
        pop     bx
        pop     ax
        ret


syscall:
        iret

        section .data
disktab resb    disk_size*NR_DISKS
buftab  resb    buffer_size*NR_BUFFERS
filetab resb    fd_size*NR_FILES        ; fd[1]=root dir, fd[2]=current dir, fd[0] for temporary usage

fsstat:
        xor     ax, ax
        xor     bx, bx
        xor     cx, cx
        xor     dx, dx
.7:     push    dx
        xor     dx, dx
        call    get_mbt_entry
        pop     dx
        cmp     ax, 0x001
        je      .10
        test    ax, ax
        jnz     .8
        inc     cx
.8:     cmp     ax, 0xfff
        jne     .9
        inc     dx
.9:     inc     bx
        mov     ax, bx
        jmp     .7
.10:    push    bx
        push    cx
        push    dx
        mov     si, fsstatbuf
        call    printk
        ret
