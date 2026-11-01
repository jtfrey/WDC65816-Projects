
.p816

.include "bf16.inc"

.import BF16_ADD


.segment "MAIN"

.define DPAGE_BASE      $2000
.define STACK_BASE      $7BFF

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
            
            ; Wait for a keypress
            JSR     FTDI_READ
            
            REP     #$20
            .a16
            LDA     #BF16_1_5
            PHA                 ; argument 1
            STA     $00
            LDA     #BF16_1_8
            PHA                 ; argument 2
            STA     $02
            JSR     BF16_ADD
            STA     $04
            
            
            ;
            ; Print operand 1:
            ;
            LDA     $00
            SEP     #$20                    ; 8-bit accumulator
            .a8
            JSR     PRNTWORD
            
            LDA     #'+'
            JSR     FTDI_WRITE
            
            REP     #$20
            .a16
            LDA     $02
            SEP     #$20
            .a8
            JSR     PRNTWORD
            
            LDA     #'='
            JSR     FTDI_WRITE
            
            REP     #$20
            .a16
            LDA     $04
            SEP     #$20
            .a8
            JSR     PRNTWORD
            
            LDA     #$0D
            JSR     FTDI_WRITE
            LDA     #$0A
            JSR     FTDI_WRITE
            
            STP

PRNTWORD:   XBA                             ; Swap the MSB to the LSB
            PHA
            LDA     #'0'
            JSR     FTDI_WRITE
            LDA     #'x'
            JSR     FTDI_WRITE
            PLA
            JSR     PRNTBYTE
            XBA
PRNTBYTE:   PHA
            LSR
            LSR
            LSR
            LSR
            JSR     PRNTNIBBLE
            PLA
            AND     #$0F
PRNTNIBBLE: CMP     #$0A
            BCC     PRNTNIBBLE_LN_LT_10
            CLC
            ADC     #'A'-'0' - 10
PRNTNIBBLE_LN_LT_10:
            ADC     #'0'
            JSR     FTDI_WRITE
            RTS

.export MAIN_SIZE = * - MAIN_START

.endproc
