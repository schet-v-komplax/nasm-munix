    xor     ah, ah
    mov     al, 2
    int     0x10
    mov     ax, 1
    xor     bx, bx
    int     0x80
