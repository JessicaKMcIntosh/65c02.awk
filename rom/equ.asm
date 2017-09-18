            .LIST   OFF         ; Don't need to list all of this...

; ROM memory locations.
R_SWR       .EQU    $0000       ; ---
R_SWR1      .EQU    $0002       ;  |
R_SWR2      .EQU    $0004       ;  |
R_SWR3      .EQU    $0006       ;  |
R_SWR4      .EQU    $0008       ;  |
R_SWR5      .EQU    $000A       ;  |
R_SWR6      .EQU    $000C       ;  |
R_SWR7      .EQU    $000E       ;  | Sweet 16 registers.
R_SWR8      .EQU    $0010       ;  |
R_SWR9      .EQU    $0012       ;  |
R_SWR10     .EQU    $0014       ;  |
R_SWR11     .EQU    $0016       ;  |
R_SWR12     .EQU    $0018       ;  |
R_SWR13     .EQU    $001A       ;  |
R_SWR14     .EQU    $001C       ;  |
R_SWR15     .EQU    $001E       ; ---
R_PARMA     .EQU    $00F0       ; ---
R_PARMAL    .EQU    $00F0       ;  |
R_PARMAH    .EQU    $00F1       ;  |
R_PARMB     .EQU    $00F2       ;  |
R_PARMBL    .EQU    $00F2       ;  | Parameter passing.
R_PARMBH    .EQU    $00F3       ;  |
R_PARMC     .EQU    $00F4       ;  |
R_PARMCL    .EQU    $00F4       ;  |
R_PARMCH    .EQU    $00F5       ; ---
R_TEMP      .EQU    $00F9       ; General temporary value.
R_INPOS     .EQU    $00FA       ; The current position of the input buffer.
R_CURSOR    .EQU    $00FB       ; Cursor position for R_PRINTCHAR
R_SAVE_A    .EQU    $00FC       ; ---
R_SAVE_Y    .EQU    $00FD       ;  | Save registers and processor state.
R_SAVE_X    .EQU    $00FE       ;  | Used by R_SAVE and R_RESTORE
R_SAVE_P    .EQU    $00FF       ; ---
R_DISPL     .EQU    $C000       ; ---
R_DISP0     .EQU    $C000       ;  |
R_DISP1     .EQU    $C028       ;  |
R_DISP2     .EQU    $C050       ;  | Display memory.
R_DISP3     .EQU    $C078       ;  |
R_DISP4     .EQU    $C0A0       ;  |
R_DISP5     .EQU    $C0C8       ;  |
R_DISPH     .EQU    $C0EF       ; ---
R_DISPCTRL  .EQU    $C0F0       ; ---
R_DISPCLR   .EQU    $C0F1       ;  | Display control.
R_SCROLL    .EQU    $C0F2       ; ---
R_HALTSYS   .EQU    $C0FA       ; Write anything to halt the emulator.
R_INTRATE   .EQU    $C0FB       ; Sets the interrupt/keyboard rate.
R_RANL      .EQU    $C0FC       ; 16 byte random number low byte.
R_RANH      .EQU    $C0FD       ; 16 byte random number high byte.
R_KEYBP     .EQU    $C0FE       ; Keyboard interface. Last key pressed.
R_KEYB      .EQU    $C0FF       ; The same as R_KEYBP but reading resets to 0.
R_MONITOR   .EQU    $E000       ; Monitor.
R_MONMESS   .EQU    $EA00       ; Monitor messages.
R_RTS       .EQU    $FFF0       ; This location will always have an RTS.
R_NMIT_VEC  .EQU    $FFFA       ; NMI vector.
R_RESET_VEC .EQU    $FFFC       ; Reset vector.
R_IRQT_VEC  .EQU    $FFFE       ; IRQ Vector.

; ROM subroutines.
R_SAVE      .EQU    $F000       ; Save the registers and status.
R_RESTORE   .EQU    $F00C       ; Restore the registers and status.
R_MEMFILLP  .EQU    $F017       ; Fill a page worth of memory.
R_PRINTCHAR .EQU    $F01D       ; Print a character on the display.
R_PRINTMSG  .EQU    $F04F       ; Print a null terminated message.
R_SWEET16   .EQU    $F689       ; Enter Sweet 16

; Character constants.
CHAR_NULL   .EQ     $00
CHAR_BEL    .EQ     $07
CHAR_TAB    .EQ     $09
CHAR_CR     .EQ     $0D
CHAR_ESC    .EQ     $1B
