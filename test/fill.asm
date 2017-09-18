; Include equates.
            .INC    rom/equ.asm

; Halt the system.
            .MACRO  HALT
            STZ     R_HALTSYS
            .ENDM

; Fill a memory bank with a value.
START       .ORG    $0200       ; Store the program at 0x0200
            LDA     #$00        ; The address to write.
            STA     R_PARMAL
            LDA     #$03
            STA     R_PARMAH
            LDY     #$FF        ; The number of bytes to write.
            LDA     #$AA        ; The value to write.
            JSR     R_MEMFILLP  ; Fill the memory.
            STZ     $C0FA       ; HALT!

; Fill a page worth of memory.
; Limited to 256 bytes. Can cross page boundaries.
; Register A - The byte to fill memory with.
; Register X - Unchanged.
; Register Y - The number of bytes to clear. Clobbered.
;              Set to 0 to write 256 bytes.
; R_PARMA (F0 & F1) - The address to clear.
R_MEMFILLP  DEY                 ; Decrement the byte counter.
            STA     (R_PARMA),Y ; Write the fill byte.
            BNE     R_MEMFILLP  ; Continue until all the bytes are written.
            RTS                 ; Return.

; Set the Reset vector to start our code.
            .ORG    R_RESET_VEC
            .BYTE   <START
            .BYTE   >START
