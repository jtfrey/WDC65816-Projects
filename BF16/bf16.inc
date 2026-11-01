;
; The BF16 type is a truncation of the Float32; the lower
; 16-bits of the mantissa are discarded, leaving just the
; most-significant 7 bits.
;
; The MSb of the 16-bit word remains the sign indicator,
; as does the 8-bit 127-biased exponent directly below
; it in the word.  The lowest 7 bits represent the
; mantissa:
;
.define BF16_SIGN_MASK          $8000
.define BF16_EXP_MASK           $7F80
.define BF16_EXP_SHIFT          7
.define BF16_MANT_MASK          $007F

;
; There exist some specific bit patterns that are given
; special significance.  In the standard, if the exponent
; is $FF it indicates a special value; if the mantissa
; is exactly zero, the value is infinity, otherwise it is
; a NaN.
;
.define BF16_POS_INF            $7F80
.define BF16_NEG_INF            $FF80
.define BF16_POS_NAN            $7FC0
.define BF16_NEG_NAN            $FFC0

;
; Some additional numerical constants:
;
.define BF16_0                  $0000
.define BF16_1_8                $3E00
.define BF16_1_5                $3E4C
.define BF16_1_4                $3E80
.define BF16_1_3                $3EAA
.define BF16_1_2                $3F00
.define BF16_1                  $3F80
.define BF16_2                  $4000
.define BF16_4                  $4080
.define BF16_8                  $4180
.define BF16_PI_4               $3F49
.define BF16_PI_2               $3FC9
.define BF16_PI                 $4049
.define BF16_2PI                $40C9
.define BF16_1_PI               $3EA2
.define BF16_2_PI               $3F22
.define BF16_EULER              $402D
.define BF16_SQRT2              $3FB5
.define BF16_1_SQRT2            $3F35

;
; For the sake of classifying values, there are these
; enumerated codes:
;
.define BF16_CLASS_DENORM       $00
.define BF16_CLASS_NORM         $01
.define BF16_CLASS_INF          $02
.define BF16_CLASS_NAN          $03
