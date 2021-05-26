TRUE            equ 1
FALSE           equ 0
DEBUG           equ TRUE

GET             equ 0
SET             equ 1

BLOCK           equ 2048
SECTOR          equ 512
BLOCK_LOG       equ 11
SECTOR_LOG      equ 9

NR_DISKS        equ 4
NR_FILES        equ 8
NR_SYSCALLS     equ 16
NR_BUFFERS      equ 32

INITSEG         equ 0x0050
BUFSEG          equ 0x5000
KERNSEG         equ 0x6000
DRVSEG          equ 0x7000

struc diskdata
    d_flags     resb 1                  ; 0=free
    d_disk      resb 1                  ; disk actual number
    d_sectors   resw 1
    d_heads     resw 1
    d_cylinders resw 1
endstruc

struc disk
    d_present   resb 1
    d_data      resb 1                  ; diskdata struc, <0 if unused
    d_mbt       resw 3                  ; mbt buffers
endstruc

struc file
    f_flags     resb 1
    f_name      resb 15
    f_block     resw 1
    f_size      resd 1
    f_pad       resw 1
    f_ctime     resd 1
    f_mtime     resd 1
endstruc

F_PRESENT       equ 0x80
F_DIR           equ 0x40
F_HIDDEN        equ 0x20
F_LINEAR        equ 0x10
F_READ          equ 0x04
F_WRITE         equ 0x02
F_EXEC          equ 0x01

struc fd
    fd_flags    resb 1
    fd_disk     resb 1
    fd_file     resw 1                  ; offset of file within fs segment
    fd_pos      resd 1
endstruc

B_FLUSH         equ 0x01                ; flush if changed
B_KEEP          equ 0x02                ; keep in memory unless fd is closed
B_PRESENT       equ 0x80

struc buffer
    b_flags     resb 1
    b_disk      resb 1
    b_fd        resw 1                  ; last accessed fd, used to free buffer on closing fd
    b_block     resw 1
    b_size      resw 1
endstruc
buffer_log      equ 3                   ; 2K block address=fs:'offset of buffer struc within buftab'<<(BLOCK_LOG-buffer_log)
