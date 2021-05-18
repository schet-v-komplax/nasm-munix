;
; mm.asm
;
; is used to manage 64K (32 pages) memory block at ALLOCSEG
; for correct work gs must not be changed

mm_init:
    push    ax
    push    bx
    push    ALLOCSEG
    pop     gs
    mov     ax, int_0x20
    mov     bx, 0x20
    call    set_int
    mov     bx, 2
    int     0x20                        ; free all pages
    pop     bx
    pop     ax
    ret

;
; INT 0x20
;
; bx=0: get_free_page
; bx=0x800,0x1000,0x1800,...,0xf800: free_page
; bx=1: dump_memory
; bx=2: free_pages
int_0x20:
    or      bx, bx
    jz      get_free_page
    cmp     bx, 1
    je      dump_memory
    cmp     bx, 2
    je      free_pages

; input: gs:bx=address of page to free
free_page:
    test    bx, 0x07ff
    jnz     bad_page
    shr     bx, 11                      ; address to page number
    mov     byte [gs:bx], 0             ; make free
bad_page:
    iret

; output: gs:bx=addres of free page, bx=0 if no free pages
get_free_page:
    push    ax
    mov     bx, 31
find_page:
    mov     al, [gs:bx]
    or      al, al
    jz      ret_page
    dec     bx
    jnz     find_page
ret_page:
    pop     ax
    inc     byte [gs:bx]                ; mark as used
    shl     bx, 11                      ; page number to address
    ;int3
    iret

; output: ax=number of free pages, bx=0
dump_memory:
    mov     bx, 31
    xor     ax, ax
    push    cx
check_page:
    mov     cl, [gs:bx]
    or      cl, cl
    jnz     page_not_free
    inc     ax
page_not_free:
    dec     bx
    jnz     check_page
    pop     cx
    iret

free_pages:
    push    ax
    push    cx
    push    di
    push    es
    push    gs
    pop     es
    xor     al, al
    xor     di, di
    mov     cx, 32
    cld
    rep
    stosb
    pop     es
    pop     di
    pop     cx
    pop     ax
    inc     byte [gs:0]
    iret
