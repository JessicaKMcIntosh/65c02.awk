; Include equates.
            .INC    equ.asm

; Halt the system.
            .MACRO  HALT
            STZ     R_HALTSYS
            .ENDM

START       .ORG    $0200
; Use R_PRINTMSG
            LDA     #<MSG
            STA     R_PARMAL
            LDA     #>MSG
            STA     R_PARMAH
            JSR     R_PRINTMSG
            HALT

; Modified from the example at http://en.wikibooks.org/wiki/Transwiki:List_of_hello_world_programs
;            LDX     #$00        ; starting index in .X register
;LOOP        LDA     MSG,X       ; read message text
;            BEQ     LOOPEND     ; end of text
;            JSR     R_PRINTCHAR ; output char
;            INX
;            BNE     LOOP        ; repeat
;LOOPEND     HALT

; The data.
MSG         .STRING ">Hello, world!"
            .BYTE   $0D
            .BYTE   '>
            .BYTE   $00

; Set the Reset vector to start our code.
            .ORG    R_RESET_VEC
            .BYTE   <START
            .BYTE   >START
