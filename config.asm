FALSE       equ 0
TRUE        equ 1
PAGE        equ 0x800

DEBUG       equ TRUE

NR_FILES    equ 10
NR_NODES    equ 20
NR_SYSCALLS equ 32
FIRST_BLOCK equ 4

STACKSIZE   equ 0xc800                  ; 50K
BOOTSEG     equ 0x0050                  ; MBR
INITSEG     equ 0x0100                  ; /boot/init.sys
MBTSEG      equ 0x0200                  ; fs
STACKSEG    equ 0x0380
USERSEG     equ 0x1000
USTACKSEG   equ 0x2000                  ; user stack
SHELLSEG    equ 0x5000
ALLOCSEG    equ 0x6000
MUNIXSEG    equ 0x7000                  ; /boot/munix.sys

F_PRESENT   equ 0x80
F_DIR       equ 0x40
F_HIDDEN    equ 0x20
F_LINEAR    equ 0x10                    ; linear block order
F_READ      equ 0x04
F_WRITE     equ 0x02
F_EXEC      equ 0x01

O_EXEC      equ 1
O_WRITE     equ 2
O_READ      equ 4
O_AHEAD     equ 8                       ; r/w ahead
O_CLEAR     equ 16                      ; clear opened file
O_RW        equ (O_READ | O_WRITE)

SET         equ 0
GET         equ 1

L_SET       equ SET
L_GET       equ GET
H_SET       equ SET
H_GET       equ GET

struc MBR
    mbr_jmp     resw 1
    mbr_sign    resb 10
    mbr_munix   resw 1
    mbr_init    resw 1
    mbr_root    resw 1                  ; root dir size
endstruc

struc file                              ; directory entry
    file_flags  resb 1
    file_name   resb 15
    file_block  resw 1                  ; first block withn file
    file_count  resw 1                  ; bytes in file 
    file_pad    resb 4                  ; unused
    file_ctime  resd 1
    file_mtime  resd 1
endstruc

struc node
    n_buf       resw 1                  ; buffer address within gs. 0 if free
    n_block     resw 1                  ; block number
    n_owner     resw 1                  ; file fd, 0 if free
endstruc

struc fd                                ; file table entry
    fd_file     resb file_size
    fd_flags    resw 1                  ; READ, WRITE, etc. 0 if empty
    fd_node     resw 1                  ; file's node
    fd_parent   resw 1                  ; parent's node, -1 if none
    fd_pos      resw 1
endstruc
