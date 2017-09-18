; AWK 65c02 Emulator Monitor.
;
; Copyright (C) 2007 Lorance Stinson All rights reserved.  This script is free
; software.  It may be copied or modified according to the same terms as Perl.
;
; For more information email <LoranceStinson+65c02@gmail.com>.
; Or see http://lorance.freeshell.org/
;
; Code starts at E000.
; Messages are stored in monmess.asm and starts at EA00.

; Include equates.
            .INC    equ.asm

; Include the messages.
            .INC   messages.asm

; ROM Monitor.
R_MONITOR   .ORG   $E000

; Startup routine.
STARTUP     STZ     R_DISPCLR       ; Clear the display.
            STZ     R_CURSOR        ; Set the cursor.
            LDA    #<M_GREEET       ; Print the greeting message.
            STA    R_PARMAL
            LDA    #>M_GREEET
            STA    R_PARMAH
            JSR    R_PRINTMSG

; Make some visual noise for testing...
:1          LDA     #$21            ; Get a character.
:2          JSR     R_PRINTCHAR     ; Write the character to the display.
            INA                     ; Increment the character.
            INX                     ; Advance to the next address.
            CMP     #$7E            ; If we have reached the limit of printable characters
            BEQ     :1              ; Reset the character counter.
            BRA     :2              ; Nope, continue.

            STZ    R_HALTSYS

; Set the Reset vector to the monitor startup
            .ORG    R_RESET_VEC
            .BYTE   <STARTUP
            .BYTE   >STARTUP
