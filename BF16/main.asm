
.p816

.include "bf16.inc"

.import BF16_ADD
.import BF16_MUL


.segment "MAIN"

.define DPAGE_BASE      $2000
.define STACK_BASE      $7BFF

.define BF16_FN_PTR     $00
.define BF16_CSTR_PTR   $02

.define FTDI_INIT       $F800
.define FTDI_WRITE      $F803
.define FTDI_READ       $F806
.define FTDI_CAN_READ   $F809

.proc       main
MAIN_START:
MAIN:       SEI
            CLC
            XCE                 ; native mode
            REP     #$30        ; 16-bit X/Y, A
            .a16
            .i16
            LDX     #STACK_BASE ; Stack right below the hardware i/o register page
            TXS
            LDA     #DPAGE_BASE ; Direct page in $0000
            TCD
            SEP     #$30        ; 8-bit X/Y/A
            .a8
            .i8

            JSR     WAIT_KEY
            REP     #$20                    ; 16-bit accumulator
            .a16
            
            LDX     #0
            PHX
            
            ;
            ; Run through the table for BF16_ADD
            ;
FN_LOOP:    PLX
            LDA     FN_NAME_TABLE, X
            BEQ     EXIT
            STA     BF16_CSTR_PTR
            SEP     #$20
            .a8
            JSR     PRNTCSTR
            REP     #$20
            .a16
            LDA     FN_PTR_TABLE, X
            STA     BF16_FN_PTR
            INX
            INX
            PHX
DO_TABLE:   LDX     #0                      ; X will hold the operand 1 index…
OUTER_LOOP: LDY     #0                      ; …and Y will hold the operand 2 index
INNER_LOOP: PHX
            PHY                             ; save X/Y since the BF16_ADD clobbers them
            PEA     SUM_DONE-1              ; return address from the DO_SUM call below
            LDA     VALUE_TABLE, X
            PHA                             ; value[X] from the table…
            LDA     VALUE_TABLE, Y
            PHA                             ; …added to value[Y] from the table
            JMP     DO_SUM                  ; go execute the code and return from it to here
SUM_DONE:   PLY
            PLX
            INY
            INY                             ; pull X/Y from the stack and increment Y by 2 (words)
            CPY     #80                     ; Y < 80, continue inner loop
            BCC     INNER_LOOP
            INX
            INX                             ; increment X by 2 (words)
            CPX     #80
            BCC     OUTER_LOOP              ; X, < 80, continue outer loop
            SEP     #$20
            .a8
            
            JSR     WAIT_KEY
            
            REP     #$20
            .a16
            BRA     FN_LOOP
            
EXIT:
            SEP     #$20                    ; 8-bit accumulator
            .a8
            STP

FN_PTR_TABLE:
            .WORD  BF16_ADD
            .WORD  BF16_MUL

FN_NAME_TABLE:
            .WORD  BF16_ADD_NAME
            .WORD  BF16_MUL_NAME
            .WORD  $0000

BF16_ADD_NAME:
            .BYTE   $0D,$0A,"Calling BF16_ADD...",$0D,$0A,$0D,$0A,$00
BF16_MUL_NAME:
            .BYTE   $0D,$0A,"Calling BF16_MUL...",$0D,$0A,$0D,$0A,$00

WAIT_KEY:   ; Wait for a keypress
            JSR     FTDI_READ
            LDA     #'O'
            JSR     FTDI_WRITE
            LDA     #'K'
            JSR     FTDI_WRITE
            LDA     #$0D
            JSR     FTDI_WRITE
            LDA     #$0A
            JSR     FTDI_WRITE
            
            RTS

DO_SUM:     .i8
            .a16
            ;
            ; Print operand 1:
            ;
            LDA     3, S
            SEP     #$20                    ; 8-bit accumulator
            .a8
            JSR     PRNTWORD
            
            LDA     #'+'
            JSR     FTDI_WRITE
            
            REP     #$20
            .a16
            LDA     1, S
            SEP     #$20
            .a8
            JSR     PRNTWORD
            
            LDA     #'='
            JSR     FTDI_WRITE
            
            REP     #$20
            .a16
            PEA     FN_RETURN-1             ; Return address on stack
            JMP     (DPAGE_BASE + BF16_FN_PTR)
FN_RETURN:
            SEP     #$20
            .a8
            JSR     PRNTWORD
            
            LDA     #$0D
            JSR     FTDI_WRITE
            LDA     #$0A
            JSR     FTDI_WRITE
            
            REP     #$20
            .a16
            
            RTS
            .i8
            .a8

PRNTCSTR:   LDY     #0
PRNTCSTR_LOOP:
            LDA     (BF16_CSTR_PTR), Y
            BEQ     PRNTCSTR_EXIT
            JSR     FTDI_WRITE
            INY
            BRA     PRNTCSTR_LOOP
PRNTCSTR_EXIT:
            RTS


PRNTWORD:   XBA                             ; Swap the MSB to the LSB
            PHA
            LDA     #'0'
            JSR     FTDI_WRITE
            LDA     #'x'
            JSR     FTDI_WRITE              ; Print the '0x' prefix
            PLA
            JSR     PRNTBYTE                ; Print the MSB byte…
            XBA                             ; …swap the original LSB back and fall through…
PRNTBYTE:   PHA
            LSR
            LSR
            LSR
            LSR                             ; Isolate the high nibble…
            JSR     PRNTNIBBLE              ; …and print it
            PLA
            AND     #$0F                    ; Isolate the low nibble and fall through…
PRNTNIBBLE: CMP     #$0A
            BCC     PRNTNIBBLE_LN_LT_10
            CLC
            ADC     #'A'-'0' - 10           ; Shift for [A-F] digits in composition with…
PRNTNIBBLE_LN_LT_10:
            ADC     #'0'                    ; …shift for [0-9] digits
            JSR     FTDI_WRITE              ; Print the hex digit
            RTS

VALUE_TABLE:
            .WORD   BF16_0,     BF16_1,     BF16_2,     BF16_4,         BF16_8
            .WORD   BF16_1_2,   BF16_1_3,   BF16_1_4,   BF16_1_5,       BF16_1_8
            .WORD   BF16_PI_4,  BF16_PI_2,  BF16_PI,    BF16_2PI,       BF16_1_PI
            .WORD   BF16_2_PI,  BF16_EULER, BF16_SQRT2, BF16_POS_INF,   BF16_POS_NAN
            .WORD   BF16_0|$8000,       BF16_1|$8000,       BF16_2|$8000,       BF16_4|$8000
            .WORD   BF16_8|$8000,       BF16_1_2|$8000,     BF16_1_3|$8000,     BF16_1_4|$8000
            .WORD   BF16_1_5|$8000,     BF16_1_8|$8000,     BF16_PI_4|$8000,    BF16_PI_2|$8000
            .WORD   BF16_PI|$8000,      BF16_2PI|$8000,     BF16_1_PI|$8000,    BF16_2_PI|$8000
            .WORD   BF16_EULER|$8000,   BF16_SQRT2|$8000,   BF16_NEG_INF,       BF16_NEG_NAN

.export MAIN_SIZE = * - MAIN_START

.endproc
