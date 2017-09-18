; Include equates.
            .INC    equ.asm
; ROM Utilities.

R_UTILS     .ORG    $F000

; $F000
; Save the registers and status.
; Clobbers A and clears Decimal mode.
R_SAVE      STA     R_SAVE_A
            STX     R_SAVE_X
            STY     R_SAVE_Y
            PHP
            PLA
            STA     R_SAVE_P
            CLD
            RTS

;$F00C
; Restore the registers and status.
R_RESTORE   LDA     R_SAVE_P
            PHA
            LDA     R_SAVE_A
            LDX     R_SAVE_X
            LDY     R_SAVE_Y
            PLP
            RTS

; $F017
; Fill a page worth of memory.
; Limited to 256 bytes. Can cross page boundaries.
; Register A - The byte to fill memory with.
; Register X - Unchanged.
; Register Y - The number of bytes to clear. Clobbered.
;              Set to 0 to write 256 bytes.
; R_PARMA (F0 & F1) - The address to clear.
; Processor status is clobbered.
R_MEMFILLP  DEY                 ; Decrement the byte counter.
            STA     (R_PARMA),Y ; Write the fill byte.
            BNE     R_MEMFILLP  ; Continue until all the bytes are written.
            RTS                 ; Return.

; $F01D
; Print a character on the display.
; Register A - The character to print. (Clobbered if a CR.)
; Register X - Unchanged.
; Register Y - Unchanged.
; R_CURSOR   - The Position of the cursor.
; Processor status is clobbered.
R_PRINTCHAR PHX                 ; Save the X register.
            LDX     R_CURSOR    ; Get the current cursor position.
            CMP     #CHAR_CR    ; If the character is a CR.
            BEQ     :2          ; It gets special handling.
            CPX     #<R_DISPH   ; See if the cursor is off the display.
            BCC     :1
            STZ     R_SCROLL    ; Scroll the display by one line.
            LDX     #<R_DISP5   ; Set the cursot to the start of row 5
:1          STA     R_DISPL,X   ; Write the character.
            INX                 ; Increase the cursor position.
:3          STX     R_CURSOR    ; Save the cursor position.
            PLX                 ; Restore the X register.
            RTS                 ; Return.
:2          CPX     #<R_DISP5   ; If on row 5
            BCC     :4          ; Not row 5, move the cursor down one line.
            STZ     R_SCROLL    ; Scroll the display
            LDX     #<R_DISP5   ; Reset to the start of row 5.
            BRA     :3          ; And continue on.
:4          LDA     #0          ; Find the next row.
            STX     R_TEMP      ; Hold the cursor for comparison.
            CLC
            CLD                 ; Make sure math works right.
:5          ADC     #$28        ; Move on to the next row.
            CMP     R_TEMP      ; See if the cursor is past this row.
            BCC     :5          ; Have not passed the cursor yet.
            TAX                 ; Set the cursor to the start of the next row.
            BRA     :3          ; And continue on.

; $F04F
; Print a null terminated message less than 255 bytes long.
; Register A - Unchanged.
; Register X - Unchanged.
; Register Y - Unchanged.
; R_PARMA    - The address of the message.
; Processor status is clobbered.
; Modified from the example at:
; http://en.wikibooks.org/wiki/Transwiki:List_of_hello_world_programs
R_PRINTMSG  PHA                 ; Save the A register.
            PHY                 ; Save the Y register.
            LDY     #$00        ; Starting index in Y register.
:1          LDA     (R_PARMA),Y ; Read message text.
            BEQ     :2          ; End of text.
            JSR     R_PRINTCHAR ; output char
            INY                 ; Move to the next character.
            BNE     :1          ; Repeat
:2          PLA                 ; Restore the A register.
            PLY                 ; Restore the Y register.
            RTS                 ; Return


; This location will always have an RTS.
            .ORG    $FFF0
            RTS
