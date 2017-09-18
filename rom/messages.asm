; AWK 65c02 Emulator Monitor.
;
; Copyright (C) 2007 Lorance Stinson All rights reserved.  This script is free
; software.  It may be copied or modified according to the same terms as Perl.
;
; For more information email <LoranceStinson+65c02@gmail.com>.
; Or see http://lorance.freeshell.org/
;
; Messages for the Monitor.
; Code is stored in monitor.asm and starts at EA00.

R_MONMESS   .ORG    $EA00

; Greeting presented to the user when the emulator starts.
M_GREEET    .STRING "Welcome to the AWK 65c02 Emulator"
            .BYTE   CHAR_CR
            .BYTE   $00

