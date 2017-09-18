; Include equates.
            .INC    equ.asm

START       .ORG    $0200
            JSR     R_SWEET16
            SET     0, $ABCD
            SET     1, $1234
            ADD     1
            RTN
            STZ     $C0FA

; Set the Reset vector to start our code.
            .ORG    R_RESET_VEC
            .BYTE   <START
            .BYTE   >START
