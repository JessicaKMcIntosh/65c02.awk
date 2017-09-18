;---------------------------------
;      SWEET-16
;      --------
;      BY S. WOZNIAK
;      COPYRIGHT 1977 BY
;      APPLE COMPUTER INC.
;---------------------------------
;      PAGE ZERO USAGE
;---------------------------------
R0L    .EQ $00
R0H    .EQ $01
R14H   .EQ $1D
R15L   .EQ $1E
R15H   .EQ $1F
;---------------------------------
;      MONITOR SUBROUTINES
;---------------------------------
MON.SAVE    .EQ $F000   ; SAVE REGS
MON.RESTORE .EQ $F00C   ; RESTORE REGS
;---------------------------------
;      ORIGIN AT $F689 IN ROM
;      ORIGIN AT $XX89 IN USER RAM
;---------------------------------
;      ORIGIN MUST BE OF FORM $XX89.
;      ROM VERSION HAS ORIGIN=$F689
;       .OR $0889
       .OR $F689
;---------------------------------
;      MAIN ENTRY
;---------------------------------
SW16   JSR MON.SAVE     ; SAVE REGS
       PLA              ; START INTERPRETING SWEET-16
       STA R15L         ; RIGHT AFTER THE "JSR SW16"
       PLA              ; R15 IS SWEET-16 PC-REG
       STA R15H
SW16B  JSR SW16C        ; INTERPRET AND EXECUTE ONE
       JMP SW16B        ; SWEET-16 INSTRUCTION
;---------------------------------
;      DO ONE SWEET-16 INSTRUCTION
;---------------------------------
SW16C  INC R15L         ; INCREMENT PC-REG
       BNE SW16D
       INC R15H
;SW16D  LDA /*+256       ; PAGE # OF MAIN PART OF SWEET-16
SW16D  LDA #>SET        ; PAGE # OF MAIN PART OF SWEET-16
       PHA              ; PUSH ON STACK FOR RTS
       LDA (R15L)       ; FETCH NEXT INSTRUCTION
       AND #$0F         ; MASK REGISTER NYBBLE
       ASL              ; DOUBLE FOR 2-BYTE REGISTERS
       TAX              ; TO X-REG FOR INDEXING
       LSR              ; BACK FOR EOR
       EOR (R15L)       ; NOW HAVE OPCODE NYBBLE
       BEQ TOBR         ; IF ZERO THEN NON-REG OPCODE
       STX R14H         ; INDICATE "PRIOR RESULT REG"
       LSR
       LSR
       LSR              ; OPCODE*2 TO LSB'S
       TAY              ; USE AS INDEX
       LDA OPTBL-2,Y    ; GET LOW-ORDER ADR BYTE
       PHA              ; ON STACK FOR RTS
       RTS              ; GO TO REG-OP ROUTINE
;---------------------------------
TOBR   INC R15L
       BNE TOBR2        ; INCR PC
       INC R15H
TOBR2  LDA BPTBL,X      ; LOW-ORDER ADR BYTE
       PHA              ; ON STACK FOR RTS
       LDA R14H         ; "PRIOR RESULT REG" INDEX
       LSR              ; PREPARE CARRY FOR BC, BNC
       RTS              ; GO TO NON-REG-OP ROUTINE
;---------------------------------
;      RETURN TO CALLER
;---------------------------------
RTNZ   PLA              ; POP RETURN ADDRESS
       PLA
       JSR MON.RESTORE  ; RESTORE REGS
       JMP (R15L)       ; RETURN TO 6502 CODE VIA PC
;---------------------------------
;      SET  R,VALUE
;---------------------------------
SETZ   LDA (R15L),Y     ; HIGH-ORDER BYTE OF CONSTANT
       STA R0H,X        ; INTO SELECTED REGISTER
       DEY
       LDA (R15L),Y     ; LOW-ORDER BYTE OF CONSTANT
       STA R0L,X
       TYA              ; Y-REG CONTAINS 1
       SEC
       ADC R15L         ; ADD 2 TO PC
       STA R15L
       BCC :1
       INC R15H
:1     RTS
;---------------------------------
;      OPCODE BRANCH TABLE
;      LOW-ORDER BYTES ONLY
;---------------------------------
OPTBL  .by <SET-1       ; 1X
BPTBL  .by <RTN-1       ; 00
       .by <LD-1        ; 2X
       .by <BR-1        ; 01
       .by <ST-1        ; 3X
       .by <BNC-1       ; 02
       .by <LDAT-1      ; 4X
       .by <BC-1        ; 03
       .by <STAT-1      ; 5X
       .by <BP-1        ; 04
       .by <LDDAT-1     ; 6X
       .by <BM-1        ; 05
       .by <STDAT-1     ; 7X
       .by <BZ-1        ; 06
       .by <POP-1       ; 8X
       .by <BNZ-1       ; 07
       .by <STPAT-1     ; 9X
       .by <BM1-1       ; 08
       .by <ADD-1       ; AX
       .by <BNM1-1      ; 09
       .by <SUB-1       ; BX
       .by <BK-1        ; 0A
       .by <POPD-1      ; CX
       .by <RS-1        ; 0B
       .by <CPR-1       ; DX
       .by <BS-1        ; 0C
       .by <INR-1       ; EX
       .by <NUL-1       ; 0D      UNUSED
       .by <DCR-1       ; FX
       .by <NUL-1       ; 0E      UNUSED
       .by <NUL-1       ;         UNUSED
       .by <NUL-1       ; 0F      UNUSED
;---------------------------------
SET    BRA SETZ         ; ALWAYS
;---------------------------------
LD     LDA R0L,X
BK     .EQ *-1          ; BREAK INSTRUCTION
       STA R0L
       LDA R0H,X
       STA R0H
       RTS
;---------------------------------
ST     LDA R0L
       STA R0L,X        ; MOVE RX TO R0
       LDA R0H
       STA R0H,X
       RTS
;---------------------------------
STAT   LDA R0L
STAT2  STA (R0L,X)      ; STORE BYTE INDIRECT
       LDY #0
STAT3  STY R14H         ; RESULT REG
INR    INC R0L,X
       BNE INR2         ; INCR RX
       INC R0H,X
INR2   RTS
;---------------------------------
LDAT   LDA (R0L,X)      ; LOAD INDIRECT (RX)
       STA R0L          ; TO R0
       LDY #0           ; ZERO HIGH-ORDER BYTE
       STY R0H
       BRA STAT3        ; ALWAYS
;---------------------------------
POP    LDY #0           ; HIH-ORDER BYTE = 0
       BRA POP2         ; ALWAYS
POPD   JSR DCR          ; DECR RX
       LDA (R0L,X)      ; POP HIGH-ORDER BYTE @RX
       TAY              ; SAVE IN Y-REG
POP2   JSR DCR          ; DECR RX
       LDA (R0L,X)      ; LOW-ORDER BYTE
       STA R0L          ; TO R0
       STY R0H
POP3   LDY #0
       STY R14H         ; LAST RESULT REG
       RTS
;---------------------------------
LDDAT  JSR LDAT         ; LOW-ORDER BYTE TO R0, INCR RX
       LDA (R0L,X)      ; HIGH-ORDER BYTE TO R0
       STA R0H
       JMP INR          ; INCR RX
;---------------------------------
STDAT  JSR STAT         ; STORE INDIRECT LOW-ORDER
       LDA R0H          ; BYTE AND INCR RX
       STA (R0L,X)      ; STORE HIGH-ORDER BYTE
       JMP INR          ; INCR RX
;---------------------------------
STPAT  JSR DCR          ; DECR RX
       LDA R0L
       STA (R0L,X)      ; STORE R0 LOW BYTE @RX
       JMP POP3         ; INDICATE R0 AS LAST RESULT REG
;---------------------------------
DCR    LDA R0L,X
       BNE DCR2         ; DECR RX
       DEC R0H,X
DCR2   DEC R0L,X
       RTS
;---------------------------------
SUB    LDY #0           ; RESULT TO R0
CPR    SEC              ; NOTE Y-REG=13*2 FOR CPR
       LDA R0L
       SBC R0L,X
       STA R0L,Y        ; R0-RX TO RY
       LDA R0H
       SBC R0H,X
SUB2   STA R0H,Y
       TYA              ; LAST RESULT REG*2
       ADC #0           ; CARRY TO LSB
       STA R14H
       RTS
;---------------------------------
ADD    LDA R0L
       ADC R0L,X
       STA R0L          ; R0+RX TO R0
       LDA R0H
       ADC R0H,X
       LDY #0           ; R0 FOR RESULT
       BEQ SUB2         ; FINISH ADD
;---------------------------------
BS     LDA R15L         ; NOTE X-REG IS 12*2!
       JSR STAT2        ; PUSH LOW PC BYTE VIA R12
       LDA R15H
       JSR STAT2        ; PUSH HIGH-ORDER PC BYTE
BR     CLC
BNC    BCS BNC2         ; NO CARRY TEST
BR1    LDA (R15L),Y     ; DISPLACEMENT BYTE
       BPL BR2
       DEY
BR2    ADC R15L         ; ADD TO PC
       STA R15L
       TYA
       ADC R15H
       STA R15H
BNC2   RTS
;---------------------------------
BC     BCS BR
       RTS
;---------------------------------
BP     ASL              ; DOUBLE RESULT REG INDEX
       TAX
       LDA R0H,X        ; TEST FOR PLUS
       BPL BR1          ; BRANCH IF SO
       RTS
;---------------------------------
BM     ASL              ; DOUBLE RESULT REG INDEX
       TAX
       LDA R0H,X        ; TEST FOR MINUS
       BMI BR1          ; BRANCH IF SO
       RTS
;---------------------------------
BZ     ASL              ; DOUBLE RESULT REG INDEX
       TAX
       LDA R0L,X        ; TEST FOR ZERO
       ORA R0H,X        ; BOTH BYTES
       BEQ BR1          ; BRANCH IF SO
       RTS
;---------------------------------
BNZ    ASL              ; DOUBLE RESULT REG INDEX
       TAX
       LDA R0L,X        ; TEST FOR NON-ZERO
       ORA R0H,X        ; BOTH BYTES
       BNE BR1          ; BRANCH IF SO
       RTS
;---------------------------------
BM1    ASL              ; DOUBLE RESULT REG INDEX
       TAX
       LDA R0L,X        ; CHECK BOTH BYTES
       AND R0H,X        ; FOR $FF (MINUS 1)
       EOR #$FF
       BEQ BR1          ; BRANCH IF SO
       RTS
;---------------------------------
BNM1   ASL              ; DOUBLE RESULT REG INDEX
       TAX
       LDA R0L,X        ; CHECK BOTH BYTES FOR NOT $FF
       AND R0H,X
       EOR #$FF
       BNE BR1          ; BRANCH IF NOT MINUS 1
NUL    RTS
;---------------------------------
RS     LDX #12+12       ; 12*2 FOR R12 AS STACK PNTR
       JSR DCR          ; DECR STACK PNTR
       LDA (R0L,X)      ; POP HIGH RETURN ADR TO PC
       STA R15H
       JSR DCR
       LDA (R0L,X)      ; SAME FOR LOW BYTE
       STA R15L
       RTS
;---------------------------------
RTN    JMP RTNZ
;---------------------------------
