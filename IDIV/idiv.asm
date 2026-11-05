
.p816

.segment "CODE"

.define DPAGE_BASE      $2000
.define STACK_BASE      $7BFF


.DEFINE MATH16_ARG1     $00
.DEFINE MATH16_ARG2     $02
.DEFINE MATH16_SCR1     $04
.DEFINE MATH16_SCR2     $06


.define FTDI_INIT       $F800
.define FTDI_WRITE      $F803
.define FTDI_READ       $F806
.define FTDI_CAN_READ   $F809


CODE_START:

main:           .i8
                .a8
                SEI
                CLC
                XCE                                 ; native mode
                REP     #$30                        ; 16-bit X/Y, A
                .a16
                .i16
                LDX     #STACK_BASE                 ; Stack right below the hardware i/o register
                                                    ; page
                TXS
                LDA     #DPAGE_BASE                 ; Relocate direct page
                TCD
                SEP     #$30                        ; 8-bit X/Y/A
                .a8
                .i8
    
                JSR     WAIT_KEY
                REP     #$20                        ; 16-bit accumulator
                .a16
                
                LDA     #16459
                STA     MATH16_ARG1
                LDA     #137
                STA     MATH16_ARG2
                JSR     DIDIV16
                
                LDA     MATH16_ARG2
                SEP     #$20
                .i8
                .a8
                JSR     PRNTWORD
                LDA     #' '
                JSR     FTDI_WRITE
                LDA     #'R'
                JSR     FTDI_WRITE
                LDA     #' '
                JSR     FTDI_WRITE
                REP     #$20
                .i8
                .a16
                LDA     MATH16_ARG1
                SEP     #$20
                .i8
                .a8
                JSR     PRNTWORD
                LDA     #$0D
                JSR     FTDI_WRITE
                LDA     #$0A
                JSR     FTDI_WRITE
                
                JSR     WAIT_KEY
                REP     #$20                        ; 16-bit accumulator
                .a16
                
                LDA     #16459
                PHA
                LDA     #137
                PHA
                JSR     SIDIV16
                
                PLA
                SEP     #$20
                .i8
                .a8
                JSR     PRNTWORD
                LDA     #' '
                JSR     FTDI_WRITE
                LDA     #'R'
                JSR     FTDI_WRITE
                LDA     #' '
                JSR     FTDI_WRITE
                REP     #$20
                .i8
                .a16
                PLA
                SEP     #$20
                .i8
                .a8
                JSR     PRNTWORD
                LDA     #$0D
                JSR     FTDI_WRITE
                LDA     #$0A
                JSR     FTDI_WRITE
                
                
                STP

;
; SIDIV16
; A 16-bit dividend is pushed to the stack followed by a 16-bit
; divisor.  On return, the values have been replaced by the
; remainder and the quotient, respectively.
;
; This subroutine uses only storage on the stack.  For that reason
; it requires more cycles (the stack-relative addressing mode is
; not available on all ALU instructions) and data must be moved
; in and out of the accumulator inside the loops.
;
SIDIV16:        .i8
                .a16
                ;
                ; The stack looks like:
                ;   [S+5]   dividend
                ;   [S+3]   divisor
                ;   [S+1]   return address
                ;
                LDA     3, S                        ; A <= divisor
                BNE     SIDIV16_NOT_DBZ
                ;
                ; Invalid — divide by zero; leave [S+3] as zero and…
                ;
                EOR     #$FFFF                      ; …maximize the unsigned value…
                STA     5, S                        ; …to make the remainder MAX_INT.
                RTS                                 ; Result is 0 R $FFFF
SIDIV16_NOT_DBZ:CMP     5, S                        ; divisor CMP dividend
                BEQ     SIDIV16_ONE                 ; divisor == dividend
                BCC     SIDIV16_NORM                ; divisor strictly less than dividend
                ;
                ; divisor > dividend, result is a quotient of
                ; zero with the dividend as the remainder.  Note that
                ; this will also catch the dividend's being zero and return
                ; 0 R 0.
                ;
                LDA     #0
                STA     3, S                        ; Quotient is 0, remainder is the dividend
                RTS
SIDIV16_ONE:    ;
                ; The dividend == divisor, so the result is 1 R 0.
                ;
                LDA     #1
                STA     3, S                        ; Quotient is 1…
                DEC
                STA     5, S                        ; …remainder is 0
                RTS
SIDIV16_NORM:   ;
                ; Align the divisor with the left-hand side of the dividend.
                ; The divisor is already in A when we get here and we know
                ; it's less than the dividend.  We'll use 8-bit X for the shift
                ; count.
                ;
                LDX     #1
SIDIV16_DSHIFT: INX                                 ; shift count++
                ASL                                 ; divisor <<= 1
                CMP     5, S                        ; divisor CMP dividend
                BCC     SIDIV16_DSHIFT              ; strictly less-than, keep shifting
                PHA
                ;
                ; Zero-out the quotient.  The stack will look like:
                ;   [S+7]   dividend (remainder)
                ;   [S+5]   quotient
                ;   [S+3]   return address
                ;   [S+1]   shifted divisor
                ;
                LDA     #0
                STA     5, S                        ; quotient <= 0
SIDIV16_LOOP:   LDA     7, S                        ; A <= dividend
                CMP     1, S                        ; dividend CMP divisor
                BCC     SIDIV16_NXT                 ; dividend < divisor
                SEC
                SBC     1, S                        ; dividend -= divisor
                STA     7, S                        ; write updated dividend back to stack
                SEC
SIDIV16_NXT:    ;
                ; Getting here via branch means [C] is clear; via the
                ; dividend update [C] is set.  So we can ROL the [C]arry
                ; bit into the quotient:
                ;
                LDA     5, S                        ; A <= quotient
                ROL                                 ; A <= (quotient << 1) | [C]
                STA     5, S                        ; write-back quotient
                DEX
                BEQ     SIDIV16_DONE
                LDA     1, S
                LSR                                 ; update the divisor
                STA     1, S
                BRA     SIDIV16_LOOP
SIDIV16_DONE:   PLA                                 ; pop the divisor off the stack
                RTS                                 ; return to caller



;
; DIDIV16
; A 16-bit dividend and divisor are stored to a direct page location.
; On return, the values therein have been replaced by the remainder and the
; quotient, respectively.
;
; This subroutine uses memory locations in the direct page to keep addresses
; relative (a single byte offset) and also leverage in-memory ALU operations
; like ROL, LSR, and INC/DEC.  This allows the dividend to be kept in the
; accumulator through all iterations of the division loop vs. being moved
; in and out as in SIDIV16.
;
DIDIV16:        .i8
                .a16
                ;
                ; dividend is in MATH16_ARG1
                ; divisor is in MATH16_ARG2
                ;
                LDA     MATH16_ARG2                 ; A <= divisor
                BNE     DIDIV16_NOT_DBZ             ; non-zero, not a divide by zero
                EOR     #$FFFF                      ; A <= $FFFF
                STA     MATH16_ARG1                 ; We'll return with max in the dividend
                RTS                                 ; for 0 R $FFFF -- divide by zero = "infinite"
DIDIV16_NOT_DBZ:CMP     MATH16_ARG1                 ; divisor CMP dividend
                BEQ     DIDIV16_ONE                 ; divisor == dividend
                BCC     DIDIV16_NORM                ; divisor strictly less than dividend
                ;
                ; divisor > dividend, so the dividend IS the remainder and
                ; the quotient is zero:
                ;
                STZ     MATH16_ARG2
                RTS
DIDIV16_ONE:    LDA     #1
                STA     MATH16_ARG2                 ; quotient = 1…
                STZ     MATH16_ARG1                 ; …remainder = 0…
                RTS                                 ; 1 R 0
DIDIV16_NORM:   ;
                ; Align the divisor with the left-hand side of the dividend.
                ; The divisor is already in A when we get here and we know
                ; it's less than the dividend.  We'll use MATH16_SCR1 for the shift
                ; count.
                ;
                STZ     MATH16_SCR1
DIDIV16_DSHIFT: INC     MATH16_SCR1                 ; shift count++
                ASL                                 ; divisor <<= 1
                CMP     MATH16_ARG1                 ; divisor CMP dividend
                BCC     DIDIV16_DSHIFT              ; strictly less-than, keep shifting
                STA     MATH16_SCR2                 ; shifted divisor in MATH16_SCR1
                STZ     MATH16_ARG2                 ; zero-out the quotient
                ;
                ; MATH16_ARG1:      dividend/remainder
                ; MATH16_ARG2:      quotient
                ; MATH16_SCR1:      shift count
                ; MATH16_SCR2:      shifted divisor
                ;
                LDA     MATH16_ARG1                 ; A <= dividend
DIDIV16_LOOP:   CMP     MATH16_SCR2                 ; dividend CMP shifted divisor
                BCC     DIDIV16_NXT                 ; dividend < divisor
                SEC
                SBC     MATH16_SCR2                 ; A <= dividend - divisor
                SEC                                 ; set [C]arry for quotient update
DIDIV16_NXT:    ;
                ; Getting here via branch means [C] is clear; via the
                ; dividend update [C] is set.  So we can ROL the [C]arry
                ; bit into the quotient:
                ;
                ROL     MATH16_ARG2
                DEC     MATH16_SCR1                 ; decrement the shift count
                BMI     DIDIV16_DONE
                LSR     MATH16_SCR2                 ; shift divisor right
                BRA     DIDIV16_LOOP
DIDIV16_DONE:   ;
                ; The remainder is in the accumulator; write it back to MATH16_ARG1
                ; and return with the quotient already in MATH16_ARG2.
                ;
                STA     MATH16_ARG1
                RTS



                .i8
                .a8
;
; WAIT_KEY
; Waits for the FTDI serial interface to register a keypress, then prints "ok" to the
; FTDI output.
;
; Note that the processor is expected to be in 8-bit X/Y/A mode before entering this
; subroutine.
;
WAIT_KEY:       ; Wait for a keypress
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

;
; PRNTWORD
; This entry point to this cluster of subroutine entry points is used to write a 16-bit
; word in the 16-bit accumulator to the FTDI serial output.  The value is prefixed with a
; '0x' and is printed as four hexadecimal digits.
;
; Note that the processor is expected to be in 8-bit X/Y/A mode before entering this
; subroutine.
;
; The PRNTWORD subroutine calls and then falls-through to the PRNTBYTE subroutine.
;
PRNTWORD:       XBA                                 ; Swap the MSB to the LSB
                PHA
                LDA     #'0'
                JSR     FTDI_WRITE
                LDA     #'x'
                JSR     FTDI_WRITE                  ; Print the '0x' prefix
                PLA
                JSR     PRNTBYTE                    ; Print the MSB byte…
                XBA                                 ; …swap the original LSB back and fall through…
;
; PRNTBYTE
; This entry point to this cluster of subroutine entry points is used to write an 8-bit
; byte in the lower 8-bits of the accumulator to the FTDI serial output.  The value is
; printed as two hexadecimal digits.
;
; Note that the processor is expected to be in 8-bit X/Y/A mode before entering this
; subroutine.
;
; The PRNTBYTE subroutine calls and then falls-through to the PRNTNIBBLE subroutine.
;
PRNTBYTE:       PHA
                LSR
                LSR
                LSR
                LSR                                 ; Isolate the high nibble…
                JSR     PRNTNIBBLE                  ; …and print it
                PLA
                AND     #$0F                        ; Isolate the low nibble and fall through…
;
; PRNTNIBBLE
; This entry point to this cluster of subroutine entry points is used to write the lower
; 4-bits of the lower 8-bits of the accumulator to the FTDI serial output.  The value is
; printed as a hexadecimal digit.
;
; Note that the processor is expected to be in 8-bit X/Y/A mode before entering this
; subroutine.
;
PRNTNIBBLE:     CMP     #$0A
                BCC     PRNTNIBBLE_LN_LT_10
                CLC
                ADC     #'A'-'0' - 10               ; Shift for [A-F] digits in composition with…
PRNTNIBBLE_LN_LT_10:
                ADC     #'0'                        ; …shift for [0-9] digits
                JSR     FTDI_WRITE                  ; Print the hex digit
                RTS


.export CODE_SIZE = * - CODE_START
