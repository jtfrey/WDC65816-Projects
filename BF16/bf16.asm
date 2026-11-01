
.p816

.include "bf16.inc"

;
; All of the BF16 code is placed in its own segment
;
.segment "BF16_CODE"

BF16_CODE_START:

;
; BF16_CLASSIFY
; Check the 16-bit accumulator to determine what class of
; number is represented.
;
; On return the X register is set to a value from the BF16
; class enumeration.  The value in the accumulator is
; preserved.  Obviously X is clobbered.
;
BF16_CLASSIFY:  .i8
                .a16
                PHA                             ; stash the accumulator so we don't destroy it
                LDX     #BF16_CLASS_DENORM      ; X <= denormalized value
                AND     #BF16_EXP_MASK          ; mask-out all but the exponent…
                BEQ     BF16_CLASSIFY_EXIT      ; exponent = 0 means it's a denormalized value
                INX                             ; X <= X + 1 = normalized value
                EOR     #BF16_EXP_MASK          ; XOR the exponent with the mask — zero implies $FF
                BNE     BF16_CLASSIFY_EXIT      ; It's a normalized value
                INX                             ; X <= X + 1 = infinity
                LDA     #BF16_MANT_MASK         ; A <= mantissa bitmask
                AND     1, S                    ; A <= A & [S+1] (the pushed accumulator)
                BEQ     BF16_CLASSIFY_EXIT      ; matissa is zero, that means ±∞
                INX                             ; X <= X + 1 = NaN
BF16_CLASSIFY_EXIT:
                PLA                             ; restore the accumulator…
                .i8
                .a8
                RTS                             ; …and return to caller

;
; BF16_IS_NAN
; Check the 16-bit accumulator to determine if it represents
; a NaN value.
;
; On return [C]arry is reset if the value is NOT a NaN,
; set it it is.  The value in the accumulator is preserved,
; but X is clobbered.
;
BF16_IS_NAN:    JSR     BF16_CLASSIFY
                CPX     #BF16_CLASS_NAN         ; [C] will be set if X ≥ BF16_CLASS_NAN, reset
                                                ; if X < BF16_CLASS_NAN
                RTS

;
; BF16_IS_INF
; Check the 16-bit accumulator to determine if it represents
; an ∞ value.
;
; On return [C]arry is reset if the value is NOT an ∞,
; set it it is.  The value in the accumulator is preserved,
; but X is clobbered.
;
BF16_IS_INF:    JSR     BF16_CLASSIFY
                CPX     #BF16_CLASS_INF         ; [C] will be set if X ≥ BF16_CLASS_INF, so
                BEQ     BF16_IS_INF_EXIT        ; we return if X == BF16_CLASS_INF
                CLC
BF16_IS_INF_EXIT:
                RTS
 
.proc BF16_ADD
;
; BF16_ADD
; Two 16-bit BF16 values are pushed to the stack and then this
; subroutine is called to add them to each other.
;
BF16_ADD:
                .i8
                .a16
                ;
                ; U is at [S+3], V is at [S+5]
                ;
                LDA     3, S                    ; A <= U
                BNE     BF16_ADD_U_NONZERO
                LDA     5, S                    ; A <= V, since U == 0.0
                JMP     BF16_ADD_EXIT_W_SET
BF16_ADD_U_NONZERO:
                LDA     5, S                    ; A <= V
                BNE     BF16_ADD_V_NONZERO
                ; LDA     3, S                  ; A <= U, since V == 0.0
                JMP     BF16_ADD_EXIT           ; We don't need to load U and store it right
                                                ; back to [S+3], so skip that part of the exit
BF16_ADD_V_NONZERO:
                ;
                ; A is currently holding V; extract its exponent and mantissa:
                ;
                ROL                             ; shift the exponent into the MSB
                XBA                             ; A <= ((A << 1) ROL 8)
                TAY                             ; Y <= LSB(A)
                XBA                             ; A <= (A << 1)
                LSR
                AND     #BF16_MANT_MASK         ; Isolate the mantissa
                PHA                             ; Note that this bumps all stack indices +2, so now
                                                ; V.MANT=[S+1], RET=[S+3], U=[S+5], V=[S+7]
                ;
                ; Do the same with U:
                ;
                LDA     5, S                    ; load the value of U
                ROL                             ; shift the exponent into the MSB
                XBA                             ; A <= ((A << 1) ROL 8)
                TAX                             ; X <= LSB(A)
                XBA                             ; A <= (A << 1)
                LSR
                AND     #BF16_MANT_MASK         ; Isolate the mantissa
                PHA                             ; Note that this bumps all stack indices +2, so now
                                                ; U.MANT=[S+1], V.MANT=[S+3], RET=[S+5], U=[S+7],
                                                ; V=[S+9]
                
                ;
                ; Handle all the special cases for NaN and ∞:
                ;
                CPX     #$FF                    ; U exponent is 255?
                BNE     BF16_ADD_U_NOT_SPCL
                CPY     #$FF                    ; V exponent is 255?
                BNE     __EQ_BF16_ADD_EXIT_SPCL_U; V is a norm/denorm, so we return whatever
                                                ; special value U is
                
                ;
                ; U and V are both special values
                ;
                LDA     1, S                    ; U mantissa
                BNE     __EQ_BF16_ADD_EXIT_NAN  ; non-zero mantissa = NaN
                LDA     3, S                    ; V mantissa
                BNE     __EQ_BF16_ADD_EXIT_NAN  ; non-zero mantissa = NaN
                
                ;
                ; U and V are infinities; check the combination of
                ; signs on the original values:
                ;
                LDA     7, S                    ; A <= U
                EOR     9, S                    ; A <= U ^ V
                BMI     __EQ_BF16_ADD_EXIT_NAN  ; If the sign bits were mixed, result is a NaN
                BRA     __EQ_BF16_ADD_EXIT_SPCL_U
BF16_ADD_U_NOT_SPCL:
                CPY     #$FF                    ; V exponent is 255?
                BEQ     __EQ_BF16_ADD_EXIT_SPCL_V; V is a special but U is a norm/denorm

BF16_ADD_UV_NOT_SPCL:
                ;
                ; X/Y hold the (shifted) exponents of U/V and the stack currently
                ; looks like:
                ;
                ;         V      [S+9]
                ;         U      [S+7]
                ;         RET    [S+5]
                ;         V.MANT [S+3]
                ;         U.MANT [S+1]
                ;
                ; Are the two exponents equal?
                ;
                TYA                             ; A <= $00[Y]
                PHA
                TXA                             ; A <= $00[X]
                SEC
                SBC     1, S                    ; A <= U.EXP - V.EXP
                BNE     __EQ_BF16_ADD_EXPNT_NE  ; Exponents are NOT the same, continue with the
                                                ; full algorithm
BF16_ADD_EXPNT_EQ:
                PLA                             ; Cleanup the stack from the exp equal check
                ;
                ; The exponents are equal making both a norm/denorm value
                ; that can be directly added.  The mantissas need to be adjusted
                ; with the implicit 1-bit (or not, for denorms) and negated if
                ; necessary:
                ;
                LDA     1, S                    ; A <= U.MANT
                CPX     #$00                    ; Denorm?
                BEQ     BF16_ADD_EXPNT_EQ_U_NO_IMPLCT
                ORA     #$0080                  ; Implicit 1 becomes explicit
                STA     1, S                    ; Overwrite U.MANT on stack
BF16_ADD_EXPNT_EQ_U_NO_IMPLCT:
                LDA     7, S                    ; A <= U
                BPL     BF16_ADD_EXPNT_EQ_U_NO_NEG
                LDA     #$FFFF
                EOR     1, S                    ; A <= ~A
                INC                             ; A <= ~A + 1 = -A
                STA     1, S                    ; Overwrite U.MANT on stack

BF16_ADD_EXPNT_EQ_U_NO_NEG:
                LDA     3, S                    ; A <= V.MANT
                CPY     #$00                    ; Denorm?
                BEQ     BF16_ADD_EXPNT_EQ_V_NO_IMPLCT
                ORA     #$0080                  ; Implicit 1 becomes explicit
                STA     3, S                    ; Overwrite V.MANT on stack
BF16_ADD_EXPNT_EQ_V_NO_IMPLCT:
                LDA     9, S                    ; A <= V
                BPL     BF16_ADD_EXPNT_EQ_V_NO_NEG
                LDA     #$FFFF
                EOR     3, S                    ; A <= ~A
                INC                             ; A <= ~A + 1 = -A
                BRA     BF16_ADD_EXPNT_EQ_SUM
;
; Relative re-branch slots for labels not reachable from above:
;
__EQ_BF16_ADD_EXIT_NAN:
                BRA     BF16_ADD_EXIT_NAN
__EQ_BF16_ADD_EXIT_SPCL_U:
                BRA     BF16_ADD_EXIT_SPCL_U
__EQ_BF16_ADD_EXIT_SPCL_V:
                BRA     BF16_ADD_EXIT_SPCL_V
__EQ_BF16_ADD_EXPNT_NE:
                BRA     BF16_ADD_EXPNT_NE
;
; Continue with the special-case handling -- V was positive so no
; negation was necessary:
;
BF16_ADD_EXPNT_EQ_V_NO_NEG:
                LDA     3, S                    ; A <= V.MANT
BF16_ADD_EXPNT_EQ_SUM:
                CLC
                ADC     1, S                    ; A <= V.MANT + U.
                STA     7, S                    ; Drop the sum into the U slot on the stack
                BEQ     BF16_ADD_EXIT_SPCL_U    ; If the result is zero, we have our answer
                BPL     BF16_ADD_EXPNT_EQ_NO_NEGATE
                EOR     #$FFFF                  ; Negate the result since we only store the
                INC                             ; magnitude of the mantissa
                STA     1, S                    ; Save the sum over U.MANT…
                LDA     #BF16_SIGN_MASK         ; …load the basis for a negative BF16…
                BRA     BF16_ADD_EXPNT_EQ_CHKMANT
BF16_ADD_EXPNT_EQ_NO_NEGATE:
                STA     1, S                    ; Save the sum over U.MANT…
                LDA     #$0000                  ; …load the basis for a positive BF16…
BF16_ADD_EXPNT_EQ_CHKMANT:
                STA     3, S                    ; …and overwrite V.MANT with the basis for the
                                                ; result value.
                LDA     1, S                    ; Restore the sum to A
BF16_ADD_EXPNT_EQ_CHKMANT_PRELOAD:
                ;
                ; We now have the mantissa sum in A.  Since the two
                ; input values were 8-bit values, at most the result will
                ; be 9-bit.  So if bit 8 is set, we need to shift the result
                ; to the right by 1 position and increment the shared exponent.
                ;
                BIT     #$0100
                BEQ     BF16_ADD_EXPNT_EQ_LSHFT
                ;
                ; Shift right one position and adjust exponent:
                ;
                CPX     #$FF                    ; Are we already at the max exponent?
                BEQ     BF16_ADD_EXIT_OVERFLOW
                LSR                             ; We are go to shift right and increment the
                INX                             ; exponent
                BRA     BF16_ADD_EXPNT_EQ_SETMANT
BF16_ADD_EXPNT_EQ_LSHFT:
                ;
                ; No right shift was necessary, but now we need to left-shift the result
                ; until bit 7 is occupied by a 1 OR the exponent reaches zero.
                ;
                BIT     #$0080
                BNE     BF16_ADD_EXPNT_EQ_SETMANT
                CPX     #0
                BEQ     BF16_ADD_EXPNT_EQ_SETMANT
                ASL                             ; We are go to shift left and decrement the
                DEX                             ; exponent
                BNE     BF16_ADD_EXPNT_EQ_LSHFT ; Go check again if the exponent hasn't reached 0
BF16_ADD_EXPNT_EQ_SETMANT:
                ;
                ; The repositioned (normalized or not) mantissa sum is in A
                ; and the exponent is in Y.  Set the fields in the result:
                ;
                AND     #BF16_MANT_MASK         ; mask-out the implied bit et al.
                ORA     3, S                    ; OR in the basis bit pattern
                STA     3, S                    ; Place the result back in [S+3]
                TXA                             ; Exponent in A <= [00000000][EEEEEEEE]
                XBA                             ; A <= [EEEEEEEE][00000000]
                CLC
                ROR                             ; A <= 0[EEEEEEEE]0000000
                ORA     3, S                    ; A <= [S][EEEEEEEE][MMMMMMM]
                STA     3, S                    ; Drop the result in the V.MANT slot in the stack
                PLA                             ; Remove the mantissas from the stack, pulling
                PLA                             ; the result on the second PLA (!)
                ;
                ; …and fall through to BF16_ADD_EXIT_W_SET and return to the caller
                ;
BF16_ADD_EXIT_W_SET:
                STA     3, S                    ; overwrite the second argument with the result
BF16_ADD_EXIT:
                PLA                             ; A <= return address
                STA     3, S                    ; overwrite first argument with return address
                PLA                             ; A <= the result
                RTS                             ; pop the return address and back we go
BF16_ADD_EXIT_NAN:
                PLA
                PLA                             ; pull the mantissas off the stack
                LDA     #BF16_POS_NAN           ; return a NaN
                BRA     BF16_ADD_EXIT_W_SET     ; finish out the return
BF16_ADD_EXIT_SPCL_U:
                PLA
                PLA                             ; pull the matissas off the stack
                ; At BF16_ADD_EXIT we overwrite V with the return address and pull
                ; U off the stack as the return value -- that's exactly what we need
                ; and it requires no additional work!
                BRA     BF16_ADD_EXIT           ; finish out the return
BF16_ADD_EXIT_SPCL_V:
                PLA
                PLA                             ; pull the matissas off the stack
                LDA     5, S                    ; we want to return V
                BRA     BF16_ADD_EXIT_W_SET     ; finish out the return
BF16_ADD_EXIT_OVERFLOW:
                AND     #BF16_SIGN_MASK         ; retain just the sign bit
                ORA     #BF16_POS_INF           ; OR-in the pattern for infinity
                STA     7, S                    ; drop it into the U slot on the stack
                PLA
                PLA                             ; pull the mantissas off the stack
                BRA     BF16_ADD_EXIT           ; finish out the return

BF16_ADD_EXPNT_NE:
                ;
                ; On entry from the exponent check above, the difference
                ; U.EXP - V.EXP is in the accumulator.  The flags are also
                ; still set from the subtraction, so we know which exponent
                ; was larger:
                ;
                ;    result is positive:        U.EXP > V.EXP
                ;    result is negative:        V.EXP > U.EXP
                ;
                ; Let's choose the former as our preferable ordering for a
                ; unified single code path — meaning if the latter is true,
                ; we need to swap all the occurrences of components of the
                ; operands.  We will end up replacing the U.EXP on the
                ; stack with the ∆EXP value:
                ;
                ;         V      [S+11]
                ;         U      [S+9]
                ;         RET    [S+7]
                ;         V.MANT [S+5]
                ;         U.MANT [S+3]
                ;         ∆EXP   [S+1]
                ;
                BPL     BF16_ADD_EXPNT_NE_NOSWAP    
                EOR     #$FFFF
                INC                             ; A <= -∆EXP
                STA     1, S                    ; Overwrite U.EXP on stack with the -∆EXP
                ;
                PHX
                PHY
                PLX
                PLY                             ; Swap the X/Y = U.EXP/V.EXP
                ;
                LDA     9, S                    ; A <= U
                PHA                             ; U on stack, add +2 to all stack addresses above
                LDA     13, S                   ; A <= V
                STA     11, S                   ; [(S+9)+2] <= V
                PLA                             ; U off stack
                STA     11, S                   ; [(S+11)+0] <= U
                ;
                LDA     3, S                    ; A <= U.MANT
                PHA                             ; U.MANT on stack, add +2 to all stack addresses
                LDA     7, S                    ; A <= V.MANT
                STA     5, S                    ; [(S+3)+2] <= V.MANT
                PLA                             ; U.MANT off stack
                STA     5, S                    ; [(S+5)+0] <= U
                LDA     1, S                    ; Put the |∆EXP| back in A
                BRA     BF16_ADD_EXPNT_NE_VZERO
__NE_BF16_ADD_EXIT_SPCL_U:
                BRA     BF16_ADD_EXIT_SPCL_U
BF16_ADD_EXPNT_NE_NOSWAP:
                STA     1, S                    ; Overwrite U.EXP on stack with the ∆EXP
BF16_ADD_EXPNT_NE_VZERO:
                ;
                ; The value with the larger exponent is U and V has the
                ; smaller exponent.  The |∆EXP| is in [S+1].  There's no way
                ; that U.EXP=0 because then U.EXP > V.EXP cannot be satisfied,
                ; so it implies U.MANT needs an implied 1 bit.  The implied bit
                ; on V.MANT is determined by V.EXP's being $00 or not.
                ;
                ; For the sake of simplicity (haha) we want to shift U.MANT as
                ; high as we can in the 16-bit register:
                ;
                ;         000000001MMMMMMM => 001MMMMMMM000000
                ;
                ; This means the V will have to be shifted either left or right or
                ; not at all as indicated by (6 - |∆EXP|).
                ;
                ; The mantissas are 8-bit (7 explicit + 1 implied) so any V.MANT
                ; shift in excess of -7 will zero V.MANT completely:
                ;
                ;         (6 - |∆EXP|) < -8
                ;         -|∆EXP| < -14
                ;         |∆EXP| ≥ 14
                ;
                CMP     #14
                BCC     BF16_ADD_EXPNT_NE_CHKSHFT ; |∆EXP| < 14
                PLA
                BRA     BF16_ADD_EXIT_SPCL_U    ; Exponents differ by too much, U + V = U
BF16_ADD_EXPNT_NE_CHKSHFT:
                ;
                ; Calculate the shift we need to apply to V.MANT:
                ;
                SEC
                SBC     #6                      ; A <= |∆EXP| - 6
                XBA                             ; Swap the order so that when we pull
                                                ; off the stack as 2 x 8-bit values the
                                                ; LSB will come off second
                STA     1, S                    ; Stash on the stack while we prep the
                                                ; V.MANT with the implied bit
                LDA     5, S                    ; A <= V.MANT
                CPY     #$00                    ; Is V a denormalized value?
                BEQ     BF16_ADD_EXPNT_NE_VIMPLD0
                ORA     #$0080
BF16_ADD_EXPNT_NE_VIMPLD0:
                PLY                             ; We don't need the absolute exponent on V
                PLY                             ; anymore, so pull the MSB then LSB of the
                                                ; computed |∆EXP| - 6 off the stack
                ; 
                ; This leaves the stack looking like:
                ;
                ;         V      [S+9]
                ;         U      [S+7]
                ;         RET    [S+5]
                ;         V.MANT [S+3]
                ;         U.MANT [S+1]
                ;
                ; and A still holds the V.MANT value with the implicit bit set.
                ;
                ; Y holds the shift and the N/Z flags will be set accordingly.
                ; This is actually the negative of the shift value, so our directions
                ; will be reversed.  Zero is still zero, though:
                ;
                BEQ     BF16_ADD_EXPNT_NE_NO_VSHFT
                ;
                ; A negative value is a left shift:
                ;
                BMI     BF16_ADD_EXPNT_NE_VLSHFT
                ;
                ; A positive value is a right shift:
                ;
BF16_ADD_EXPNT_NE_VRSHFT:
                LSR
                DEY
                BNE     BF16_ADD_EXPNT_NE_VRSHFT
                BRA     BF16_ADD_EXPNT_NE_NO_VSHFT
BF16_ADD_EXPNT_NE_VLSHFT:
                ASL
                INY
                BNE     BF16_ADD_EXPNT_NE_VLSHFT
BF16_ADD_EXPNT_NE_NO_VSHFT:
                STA     3, S                    ; Overwrite V.MANT on the stack
                LDA     9, S                    ; A <= V
                BIT     #BF16_SIGN_MASK         ; Was the original negative?
                BEQ     BF16_ADD_EXPNT_NE_VNONEG
                LDA     3, S
                EOR     #$FFFF
                INC                             ; V.MANT = -V.MANT
                STA     3, S                    ; Replace V.MANT on the stack
BF16_ADD_EXPNT_NE_VNONEG:
                ;
                ; We're looking to shift U.MANT left 6-bits such that:
                ;
                ;         000000001MMMMMMM
                ;         001MMMMMMM000000
                ;
                LDA     1, S                    ; A <= U.MANT
                ORA     #$0080                  ; A <= U.MANT | 0b10000000 (implied 1)
                ASL                             ; Shift left 1 bit…
                ASL                             ; …and another bit…
                ASL                             ; …and another bit…
                ASL                             ; …and another bit…
                ASL                             ; …and another bit…
                ASL                             ; …and one more bit.
                STA     1, S                    ; Overwrite U.MANT on the stack
                ;
                ; Does U.MANT need to be negated?
                ;
                LDA     7, S
                BIT     #BF16_SIGN_MASK         ; Sign bit on original U value
                BPL     BF16_ADD_EXPNT_NE_UNONEG
                LDA     1, S
                EOR     #$FFFF
                INC                             ; Load and negate U.MANT
                STA     1, S
BF16_ADD_EXPNT_NE_UNONEG:
                ;
                ; We're ready to actually perform and addition!
                ;
                LDA     1, S                    ; A <= U.MANT
                CLC
                ADC     3, S                    ; A <= U.MANT + V.MANT
                STA     7, S                    ; Drop the result into the U slot on the stack
                BEQ     __NE_BF16_ADD_EXIT_SPCL_U ; If the result is zero, we have our answer
                BPL     BF16_ADD_EXPNT_NE_NO_NEGATE
                EOR     #$FFFF                  ; Negate the result since we only store the
                INC                             ; magnitude of the mantissa
                STA     1, S                    ; Overwrite U.MANT
                LDA     #BF16_SIGN_MASK         ; Load the basis for the negative result
                BRA     BF16_ADD_EXPNT_NE_CHKMANT
BF16_ADD_EXPNT_NE_NO_NEGATE:
                STA     1, S                    ; Overwrite U.MANT
                LDA     #$0000                  ; Load the basis for the positive result
BF16_ADD_EXPNT_NE_CHKMANT:
                STA     7, S                    ; Overwrite U with the basis value
                LDA     1, S                    ; A <= SUM.MANT
                LSR                             ; Shift the result…
                LSR                             ; …back down into the range…
                LSR                             ; …where the equal exponent…
                LSR                             ; …finalization expects the…
                LSR                             ; …mantissa sum to be.
                LSR
                JMP     BF16_ADD_EXPNT_EQ_CHKMANT_PRELOAD
                .i8
                .a8
                
                

.export BF16_CODE_SIZE = * - BF16_CODE_START

.export BF16_CLASSIFY
.export BF16_IS_NAN
.export BF16_IS_INF
.export BF16_ADD

.endproc

