%include "config.asm"

    jmp     munix
    db "MUNIX KERNEL", 0

node_table:
    resb    NR_NODES * node_size

align 16
file_table:                             ; fd[0] root dir, fd[1] home dir
root_fd:
    resb    file_size
    dw      O_RW
    resw    1
    dw      -1
    dw      0
home_fd:
    resb    fd_size
first_fd:
    resb    fd_size * (NR_FILES - 2)
file_table_end:

syscall_table:
    dw      sys_err
    dw      sys_exit
    dw      sys_err
    dw      sys_read
    dw      sys_err                     ; [4]
    dw      sys_open
    dw      sys_close
    dw      sys_exec
    dw      sys_exec2                   ; execute shell
    dw      sys_home                    ; [9]
    dw      sys_err
    dw      sys_in
    dw      sys_out
    dw      sys_stdin
    dw      sys_stdout                  ; [14]
    dw      sys_err
    dw      sys_err
    dw      sys_err
    dw      sys_err
    dw      sys_lseek                   ; [19]
    dw      sys_stat
    dw      sys_err
    dw      sys_err
    dw      sys_err
    dw      sys_err                     ; [24]
    dw      sys_err
    dw      sys_err
    dw      sys_err
    dw      sys_err
    dw      sys_err                     ; [29]
    dw      sys_err
    dw      sys_err
    dw      sys_err                     ; syscall_table[SYSCALL_NR]=sys_err

find_buf    resb 32
open_buf    resb 32
open_buf_end:

stdin       dw 0                        ; stdin fd
stdout      dw 0                        ; stdout fd


%if DEBUG
%include "tools/debug.asm"
%endif

%include "drivers/blk.asm"
%include "drivers/con.asm"
%include "drivers/mm.asm"
%include "drivers/sys.asm"

munix:
    cli
    mov     ax, cs
    mov     ds, ax
    mov     es, ax                      ; setup data segments
    mov     ax, STACKSEG
    mov     ss, ax
    mov     sp, STACKSIZE               ; setup stack
    push    word MBTSEG
    pop     fs                          ; setup MBT
    push    word 0
    popf                                ; clear flags
    sti
    
    call    mm_init
    call    blk_init
    call    con_init
    call    sys_init

%if DEBUG
    mov     ax, breakpoint
    mov     bx, 3
    call    set_int
%endif

    call    get_free_node               ; setup root_fd
    mov     bx, ax
    mov     word [bx+n_owner], root_fd
    mov     [root_fd+fd_node], ax
    
    mov     ax, FIRST_BLOCK             ; manualy load "." entry of root dir
    mov     bx, [root_fd+fd_node]
    mov     bx, [bx+n_buf]
    mov     si, bx
    int     0x21
    mov     cx, file_size
    mov     di, root_fd+fd_file
    cld
    rep
    gs movsb
    
    jmp     INITSEG:0

; input: ax=function within cs, bx=int number
; output: bx <<= 2
set_int:
    cli
    push    ds
    push    0
    pop     ds
    shl     bx, 2                       ; number -> address
    mov     word [bx], ax
    add     bx, 2
    mov     word [bx], cs
    pop     ds
    sti
    ret

; input: ds=cs
; output: ax=node, 0 if no free nodes
get_free_node:
    push    si
    push    bx
    mov     si, NR_NODES * node_size
get_free_node_rep:
    or      si, si
    jz      no_free_nodes               ; no nodes within node_table
    sub     si, node_size
    mov     ax, [si+node_table+n_owner]
    or      ax, ax
    jnz     get_free_node_rep
    xor     bx, bx
    int     0x20
    or      bx, bx
    jz      no_free_nodes               ; no free buffers
    mov     [si+node_table+n_buf], bx
    lea     ax, [si+node_table]
    jmp     get_free_node_ret
no_free_nodes:
    xor     ax, ax
get_free_node_ret:
    pop     bx
    pop     si
    ret

; input: ds=cs, ax=node
free_node:
    push    di
    push    bx
    mov     di, ax
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; flush closing node (!)
    mov     word [di+n_owner], 0
    mov     bx, [di+n_buf]
    and     bx, ~(PAGE-1)
    int     0x20
    pop     bx
    pop     di
    ret

; input: ds=cs
; output: bx=fd, 0 if not found
get_free_fd:
    mov     bx, first_fd-fd_size
get_free_fd_rep:
    add     bx, fd_size
    cmp     bx, file_table_end
    je      get_free_fd_err
    test    byte [bx+fd_file+file_flags], F_PRESENT
    jnz     get_free_fd_rep
    push    ax
    call    get_free_node
    or      ax, ax
    jz      get_free_fd_err
    push    si
    mov     si, ax
    mov     [si+n_owner], bx
    pop     si
    mov     [bx+fd_node], ax
    pop     ax
    jmp     get_free_fd_ret
get_free_fd_err:
    xor     bx, bx
get_free_fd_ret:
    ret

; input: bx=fd
; free file_table entry and all owened nodes
free_fd:
    push    ax
    push    si
    mov     word [bx+fd_flags], 0
    mov     byte [bx+fd_file+file_flags], 0
    mov     si, NR_NODES * node_size
free_fd_nodes:
    sub     si, node_size
    jz      free_fd_ret
    cmp     bx, [si+node_table+n_owner]
    jne     free_fd_nodes
    lea     ax, [si+node_table]
    call    free_node
    jmp     free_fd_nodes
free_fd_ret:
    pop     si
    pop     ax
    ret

; input: ds=cs, si=source, di=dest
copy_file:
    push    es
    push    cx
    push    cs
    pop     es
    mov     cx, file_size
    cld
    rep
    movsb
    pop     cx
    pop     es
    ret

; input: ds=cs, si=source, di=dest
move_fd:
    push    bx
    push    es
    push    cx
    push    ds
    pop     es
    mov     bx, di
    test    byte [bx+fd_file+file_flags], F_PRESENT
    jz      move_fd_free
    call    free_fd
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;call    free_fd
    ; impl: delete prev file
move_fd_free:
    mov     bx, si
    push    si
    push    di
    mov     cx, fd_size
    cld
    rep
    movsb
    pop     di
    mov     si, NR_NODES * node_size
move_fd_nodes:
    sub     si, node_size
    jz      move_fd_ret
    cmp     bx, [si+node_table+n_owner]
    jne     move_fd_nodes
    mov     word [si+node_table+n_owner], di
    jmp     move_fd_nodes
move_fd_ret:
    pop     si
    call    free_fd
    pop     cx
    pop     es
    pop     bx
    ret

; input: ds=cs, ax=node, cx=block
; output: ax=error
load_node:
    push    bx
    push    si
    mov     si, ax
    mov     bx, [si+n_buf]
    and     bx, ~(PAGE-1)
    mov     [si+n_buf], bx
    mov     [si+n_block], cx
    mov     ax, cx
    int     0x21
    pop     si
    pop     bx
    ret

; input: ax=block
; output: ax=next block
next_block:
    push    bx
    push    ax
    mov     bx, ax
    shr     bx, 1
    add     bx, ax                      ; bx=ax*1.5
    mov     ax, [fs:bx]
    pop     bx
    test    bx, 1
    jnz     next_odd
    and     ax, 0xfff
    jmp     do_ret
next_odd:
    shr     ax, 4
do_ret:
    pop     bx
    ret

; input: bx=fd, ax=block within file
; output: ax=block within disk (0xfff if not valid)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; IMPL LATER: GET_BLOCK MUST DO GET_FREE_BLOCK if more than last block
get_block:
    test    byte [bx+fd_file+file_flags], F_LINEAR
    jz      get_notl
    add     ax, [bx+fd_file+file_block]
    ret
get_notl:
    push    cx
    mov     cx, ax
    mov     ax, [bx+fd_file+file_block]
    or      cx, cx
    jz      get_ret
get_rp:
    cmp     ax, 0xfff
    je      get_ret
    call    next_block
    loop    get_rp
get_ret:
    pop     cx
    ret

; input: cs=ds, bx=parent fd, ds:si=filename (parent entry (!)).
; output: find_buf is file header
find_entry:
    push    ax
    push    cx
    push    dx
    push    di
    push    si
    push    es
    push    ds
    pop     es
    mov     al, [si]
    or      al, al
    jnz     find_not_null
    lea     si, [bx+fd_file]
    mov     di, find_buf
    call    copy_file
    jmp     find_ret
find_not_null:
    mov     ax, 19
    xor     cx, cx
    mov     dx, L_SET
    int     0x80
    or      ax, ax
    jne     find_err
find_next:
    mov     ax, 3
    mov     cx, find_buf
    mov     dx, 32
    int     0x80                        ; read next header
    cmp     ax, 32
    jb      find_err
    mov     ax, [find_buf+file_flags]
    test    ax, F_PRESENT
    jz      find_err
    mov     di, find_buf+file_name
    mov     cx, 15
    push    si
    repe
    cmpsb
    pop     si
    jnz     find_next
    jmp     find_ret
find_err:
    mov     byte [find_buf+file_flags], 0
find_ret:
    pop     es
    pop     si
    pop     di
    pop     dx
    pop     cx
    pop     ax
    ret 

; input: bx=fd
sys_stdin:
    mov     [stdin], bx
    xor     ax, ax
    ret

; input: bx=fd
sys_stdout:
    mov     [stdout], bx
    xor     ax, ax
    ret

; input: bx=fd (0=stdin)
; output: al=char, ah=0 if ok, ah=0xff if error/file ended
sys_in:
    or      bx, bx
    jnz     in_file
    push    bx
    mov     bx, [stdin]
    or      bx, bx
    pop     bx
    jnz     in_file
    int     0x23
    xor     ah, ah
    ret
in_file:
    xor     ax, ax
    test    word [bx+fd_file+file_flags], F_PRESENT
    jz      sys_err
    test    word [bx+fd_flags], O_READ  ; check read access
    jz      sys_err
    push    cx
    mov     cx, [bx+fd_pos]
    cmp     cx, [bx+fd_file+file_count]
    pop     cx
    je      sys_err                     ; file ended
    push    si
    push    di
    mov     di, [bx+fd_node]
    mov     si, [di+n_buf]
    gs lodsb
    inc     word [bx+fd_pos]
    test    si, PAGE-1                  ; buffer ended?
    jnz     in_ret
    sub     si, PAGE
    push    ax
    mov     ax, word [bx+fd_pos]
    shr     ax, 11                      ; pos --> block
    call    get_block
    cmp     ax, 0xfff                   ; last block?
    je      in_ret
    push    cx
    mov     cx, ax
    mov     ax, [bx+fd_node]
    call    load_node
    pop     cx
    or      ax, ax
    pop     ax
    jz      in_ret
in_err:
    mov     ax, -1
in_ret:
    mov     [di+n_buf], si
    pop     di
    pop     si
    ret

; input: bx=fd (0=console), ax=symbol
; output: ax=error
sys_out:
    or      bx, bx
    jnz     out_file
    int     0x24
    ret
out_file:
out_err:
    mov     ax, -1
out_ret:
    ret

; input: ds=cs, bx=fd (0=console), es:cx=buf, dx=count
; output: ax=actual count
sys_read:
    push    cx
    push    di
    mov     di, cx
    mov     cx, dx
read_rep:
    call    sys_in
    cmp     ax, -1
    je      read_ret
    stosb
    loop    read_rep
read_ret:
    mov     ax, di
    pop     di
    pop     cx
    sub     ax, cx
    ret

; input: es:bx=filename, cx=flags
; output: ax=fd/error
sys_open:
    push    bx
    push    si
    push    di
    mov     si, bx
    cmp     byte [es:si], '/'
    jne     open_home
    inc     si
    mov     bx, root_fd
    jmp     do_open
open_home:
    mov     bx, home_fd
do_open:                                ; input: bx=source dir, output: bx=entry
    mov     di, open_buf
open_copy:
    es lodsb
    or      al, al
    jz      open_copy_end
    cmp     al, '/'
    je      open_copy_end
    mov     [di], al
    inc     di
    jmp     open_copy
open_copy_end:
    xor     al, al
open_zero:
    mov     [di], al
    inc     di
    cmp     di, open_buf_end
    jne     open_zero
    push    si
    mov     si, open_buf
    call    find_entry
    pop     si
    test    byte [find_buf+file_flags], F_PRESENT
    jz      open_err2
    test    byte [find_buf+file_flags], F_READ
    jz      open_err2
    mov     ax, bx
    cmp     ax, first_fd
    jae     open_no_fd                  ; if this is not root/home dir, put next file in the same fd
    call    get_free_fd
    or      bx, bx
    jz      open_err
open_no_fd:
    push    si
    push    di
    mov     si, find_buf
    lea     di, [bx+fd_file]
    call    copy_file
    mov     si, ax
    mov     si, [si+fd_node]
    mov     [bx+fd_parent], si
    pop     di
    pop     si
    mov     word [bx+fd_flags], O_READ
    mov     al, [es:si-1]
    or      al, al
    jnz     do_open
    
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; setup over flags
    test    cx, O_EXEC
    jz      open_no_exec
    test    byte [bx+fd_file+file_flags], F_EXEC
    jz      open_err
    or      word [bx+fd_flags], O_EXEC
open_no_exec:
    mov     ax, [bx+fd_parent]
    cmp     ax, [bx+fd_node]
    jne     open_no_node                ; if fd_node != fd_parent no need to allocate new node
    call    get_free_node
    or      ax, ax
    jz      open_err
    push    si
    mov     si, ax
    mov     [si+n_owner], bx
    pop     si
    mov     [bx+fd_node], ax            ; we need 1 node for file and 1 node for parent
open_no_node:
    push    cx
    push    dx
    mov     ax, 19
    mov     cx, 0
    mov     dx, L_SET
    int     0x80
    pop     dx
    pop     cx
    mov     ax, bx
    jmp     open_ret
open_err:
    call    free_fd
open_err2:
    mov     ax, -1
open_ret:
    pop     di
    pop     si
    pop     bx
    ret

; input: es:bx=filename, cx=flags, dx=GET/SET
; output: ax=fd/error
sys_home:
    cmp     dx, SET
    je      home_set
    cmp     dx, GET
    je      home_get
    jmp     sys_err
home_set:
    call    sys_open
    cmp     ax, -1
    je      sys_err
    push    bx
    push    cx
    push    si
    push    di
    mov     bx, ax
    mov     si, bx
    mov     di, home_fd
    call    move_fd
    pop     di
    pop     si
    pop     cx
    mov     word [bx+fd_flags], 0
    mov     byte [bx+fd_file+file_flags], 0
    pop     bx
home_get:
    mov     ax, home_fd
    ret

name_err:
    pop     si
    pop     di
    pop     cx

    pusha
    push    gs
    push    es
    pop     gs
    call    nlcr
    mov     bx, cx
    mov     dx, 1
    call    memory_dump
    pop     gs
    popa
    
    ret

; inpit: bx=file
sys_close:
    call    free_fd
    xor     ax, ax
    ret

; input: bx=file, es:cx=argv, dx=argc
; output: ax=exit code
sys_exec2:
    mov     word [exec_jump+2], SHELLSEG
    jmp     exec_do
sys_exec:
    mov     word [exec_jump+2], USERSEG
exec_do:
    test    word [bx+fd_flags], O_EXEC
    jz      sys_err
    mov     ax, [bx+fd_file+file_block]
    push    bx
    push    gs
    push    word [exec_jump+2]
    pop     gs
    xor     bx, bx
exec_read:
    push    ax
    int     0x21
    pop     ax
    call    next_block
    cmp     ax, 0xfff
    jne     exec_read
    pop     gs
    pop     bx
    call    free_fd
    push    es                          ; save current program data
    push    bx
    push    cx
    push    dx
    push    di
    mov     si, cx                      ; es:si=argv
    mov     cx, dx                      ; cx=argc
    jmp     far [exec_jump]
exec_jump:
    dw      0, 0

; input: bx=error code
sys_exit:
    add     sp, 18
    mov     ax, bx
    pop     di
    pop     dx
    pop     cx
    pop     bx
    pop     es                          ; pushed by exec
    ret

; input: ds=cs, bx=fd
; output: ax=error
; dx=L_GET: output: cx=pos
; dx=L_SET: input: cx=pos
sys_lseek:
    cmp     dx, L_SET
    je      lseek_set
    cmp     dx, L_GET
    je      lseek_get
    jmp     sys_err
lseek_set:
    mov     [bx+fd_pos], cx
    mov     ax, cx
    shr     ax, 11                      ; pos --> block
    call    get_block
    cmp     ax, 0xfff
    je      sys_err
    push    cx
    mov     cx, ax
    mov     ax, [bx+fd_node]
    call    load_node
    pop     cx
    or      ax, ax
    jnz     sys_err
    push    bx
    push    cx
    mov     bx, [bx+fd_node]
    and     cx, PAGE-1
    add     [bx+n_buf], cx
    pop     cx
    pop     bx
    jmp     lseek_ret
lseek_get:
    mov     cx, [bx+fd_pos]
lseek_ret:
    xor     ax, ax
    ret

; input: bx=fd, es:cx=buf
sys_stat:
    push    cx
    push    di
    push    si
    lea     si, [bx+fd_file]
    mov     di, cx
    mov     cx, file_size
    cld
    rep
    movsb
    pop     si
    pop     di
    pop     cx
    ret

strncpy:
    cld
sp1:lodsb
    stosb
    or      al, al
    jz      sp2
    dec     cx
    jz      sp2
    jmp     sp1
sp2:ret

files_dump:
    pusha
    push    es
    push    ds
    push    cs
    pop     ds
    push    gs
    push    ds
    pop     es
    push    ds
    pop     gs
    call    nlcr
    mov     bx, file_table
    mov     dx, 10
    call    memory_dump
    pop     gs
    pop     ds
    pop     es
    popa
    ret

nodes_dump:
    pusha
    push    es
    push    ds
    push    cs
    pop     ds
    push    gs
    push    ds
    pop     es
    push    ds
    pop     gs
    call    nlcr
    mov     bx, node_table
    mov     dx, 8
    call    memory_dump
    pop     gs
    pop     ds
    pop     es
    popa
    ret

mm_dump:
    pusha
    push    es
    push    ds
    push    cs
    pop     ds
    push    cs
    pop     es
    call    nlcr
    xor     bx, bx
    mov     dx, 2
    call    memory_dump
    pop     ds
    pop     es
    popa
    ret
