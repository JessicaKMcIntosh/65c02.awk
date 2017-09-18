; Include equates.
            .INC    equ.asm

; Halt the system.
            .MACRO  HALT
            STZ     R_HALTSYS
            .ENDM

START       .ORG    $0200
            LDA     #$A1
            AND     $F

; Display Test, R_PRINTCHAR
            LDX     #0              ; Set the memory counter.
:1          LDA     #$21            ; Get a character.
:2          JSR     R_PRINTCHAR     ; Write the character to the display.
            INA                     ; Increment the character.
            INX                     ; Advance to the next address.
            CMP     #$7E            ; If we have reached the limit of printable characters
            BEQ     :1              ; Reset the character counter.
            CPX     #$FF            ; See if we have printed enough characters
            BNE     :2              ; Nope, continue.
            HALT                    ; Halt the emulator.

; Display Test, direct
            LDA     #$1             ; Turn off the display.
            STA     R_DISPCTRL
            LDX     #0              ; Set the memory counter.
:1          LDA     #$21            ; Get a character.
:2          STA     R_DISPL,X       ; Write the character to the display.
            INA                     ; Increment the character.
            INX                     ; Advance to the next address.
            CMP     #$7E            ; If we have reached the limit of printable characters
            BEQ     :1              ; Reset the character counter.
            CPX     #$F0            ; See if we have reached the last row.
            BNE     :2              ; Nope, continue.
            STZ     R_DISPCTRL      ; Draw the display.
            HALT                    ; Halt the emulator.
            STZ     R_SCROLL        ; Move the display up one line.
            HALT                    ; Halt the emulator.
            STZ     R_DISPCLR       ; Clear the display.
            HALT                    ; Halt the emulator.

; Set the Reset vector to start our code.
            .ORG    R_RESET_VEC
            .BYTE   <START
            .BYTE   >START
