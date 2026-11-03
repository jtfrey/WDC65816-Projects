# BF16 on the 65816

The WDC 65816 is a descendent of the 6502 and 65C02 microprocessor that expands the three registers (X/Y/A) to 16-bits.  The arithmetic and logic instructions — add/subtract/increment/decrement, and/or/xor, bit test and shift — modally-function in either 8-bit or 16-bit.  With a native 16-bit accumulator, a 16-bit floating-point type is more easily implemented.

The [bf16.asm](./bf16.asm) file contains the 65816 source that implements numeric introspection subroutines and an addition subroutine.  All are expected to be called in native mode with the accumulator in 16-bit mode.  The [bf16.inc](./bf16.inc) file contains constant definitions.



## Background

The [BFLOAT16](https://arxiv.org/abs/1905.12322) or `BF16` type essentially truncates a `FP32` to its most-significant byte (MSB), retaining the sign bit, 8-bit exponent, and just 7 mantissa bits rather than 23.  The `FP16` type uses a more-balanced 5-bit exponent with 10 mantissa bits, but for target applications `BF16`'s sacrifice of precision for the sake of range is in some cases deemed acceptable (yes, AI).

A `BF16` value is decomposed as:

```
1 1
5 4      7 6     0
□|□□□□□□□□|□□□□□□□
S   EXP     MANT
```

The MSb of the value (`S`) indicates a positive (0) or negative (1) value.  The mantissa (`MANT`) is a binary number with a single implicit digit to the left of the decimal and seven binary digits to the right.  For _normalized_ finite values, an implicit `1` is used:

```
MANT = 1.□□□□□□□
```

The value can be thought of as being in scientific notation, with the exponent being a biased power of 2:

```
|VALUE| = MANT • 2^(EXP - 127)
```

A value like `0.0110000 • 2^-126` can still be represented, but as a _denomalized_ number with an implicit `0` digit on the mantissa:

```
MANT = 0.□□□□□□□
```

Thus, `0.0110000 • 2^-126` is represented as the `BF16` value

```
1 1
5 4      7 6     0
0|00000000|0110000  = 0x0030
S   EXP     MANT
```

and the negative of that value would have the MSb toggled to `0x8030`.  That value in decimal:

```
VALUE = (-1) • (1/4 + 1/8) • 2^-126
      = -(0.25 + 0.125) • 2^-126
      = -0.375 • 2^-126
      = -4.40810 • 10^-39
```

Working the other direction, how would the square root of two be represented?

```
Sqrt(2) = 1.414213562373095
        = 1 + 0.414213562373095
        = 1 + 0.25 + 0.164213562373095
        = 1 + 0.25 + 0.125 + 0.039213562373095
        = 1 + 0.25 + 0.125 + 0.03125 + 0.007963562373095
        = 1 + 0.25 + 0.125 + 0.03125 + 0.0078125 + 0.000151062373095
        = 1 + 0.25 + 0.125 + 0.03125 + 0.0078125 + 0.0001220703125 + 0.000028992060595
        = 2^0 + 2^-2 + 2^-3 + 2^-5 + 2^-7 + 2^-13 + 0.000028992060595
        = (1.0110101000001 • 2^0) + 0.000028992060595
```

With some loss of precision (0.00205%), the biased exponent is `(127 + 0)` and the mantissa to seven digits (with the leading `1`) is `1.0110101`.  Thus, dropping the implicit `1`:

```
1 1
5 4      7 6     0
0|01111111|0110101  = 0x3FB5
S   EXP     MANT
```

which negated would be `0xBFB5`.

### Infinities

When the biased exponent on the number exceeds `0xFE` (254) the value has overflowed and effectively becomes infinite.  The two infinities use an exponent of `0xFF` and a mantissa of zero:

```
     1 1
     5 4      7 6     0
+∞ = 0|11111111|0000000  = 0x7F80
-∞ = 1|11111111|0000000  = 0xFF80
     S   EXP     MANT
```

### Not a number

Any non-sensical value is given the not a number (NaN) classification.  NaNs can be positive or negative, but are usually returned solely in the positive form.  Like infinities, the exponent is `0xFF`, but the mantissa must contain at least one set bit to distinguish a NaN from an infinity:


```
         1 1
         5 4      7 6     0
+NaN = 0|11111111|1000000  = 0x7FC0 †
            :
+NaN = 0|11111111|0000001  = 0x7F81
-NaN = 1|11111111|1000000  = 0xFFC0 †
            :
-NaN = 1|11111111|0000001  = 0xFF81
         S   EXP     MANT
```

The `†` indicates the typical canonical form used to represent ±NaN.

## Math

### Multiplication

Consider two `BF16` values, `U` and `V`.  Both represent a signed product of components:

```
U = S_U • MANT_U • 2^(EXP_U-127)
V = S_V • MANT_V • 2^(EXP_V-127)
```

The product of `U` and `V` is then

```
U • V = S_U • MANT_U • 2^(EXP_U-127) • S_V • MANT_V • 2^(EXP_V-127)
      = (S_U • S_V) • (MANT_U • MANT_V) • 2^(EXP_U + EXP_V - 254)
```

Logically, the product of the signs is the exclusive OR of the two bits, `S_U ^ S_V` — if both are positive (`0`) or both are negative (`1`) the result is positive (`0`), but for a combination of positive and negative the result is negative (`1`).

The resulting exponent is no longer biased, so when the result is packed as a `BF16` the exponent must be re-biased (thus, `EXP_U + EXP_V - 127`).

Finally, the product of the mantissas is the product of two 8-bit values (thanks to the implicit leading digit on each) which is itself at most a 16-bit value:

```
MANT_U • MANT_V = 0b000000001.UUUUUUU • 0b000000001.VVVVVVV
                = 0bPP.PPPPPPPPPPPPPP
```

If the MSb is `1`, then the product must be shifted **right** one bit and the final exponent incremented by 1:

```
MANT_U • MANT_V = 0b1P.PPPPPPPPPPPPPP • 2^EXP
                = 0b01.PPPPPPPPPPPPPP • 2^(EXP + 1)
```

Naturally, if the exponent increments to 255 (`0xFF`), the result have overflowed and an infinity must be returned.  If the MSb was not set, then the product must be shifted **left** until a `1` occupies bit 14 and the exponent decremented each time::

```
MANT_U • MANT_V = 0b00.001PPPPPPPPPPP • 2^EXP
                = 0b00.01PPPPPPPPPPP0 • 2^(EXP - 1)
                = 0b00.1PPPPPPPPPPP00 • 2^(EXP - 2)
                = 0b01.PPPPPPPPPPP000 • 2^(EXP - 3)
```

If the exponent will decrement to 0, the value is denomalized and a leading `0` will be accepted:

```
MANT_U • MANT_V = 0b00.001PPPPPPPPPPP • 2^2
                = 0b00.01PPPPPPPPPPP0 • 2^1
                = 0b00.1PPPPPPPPPPP00 • 2^0
```

Special rules exist for products of infinities and NaNs.

### Addition

Multiplication was cited first because it is actually the simpler operation in `BF16`.  No binary point alignment is necessary:  since the mantissas are both aligned with a single implicit binary digit to the left of the point the position of the point in the product is defined to occur between bits 13 and 14.  Unlike multiplication, where the signs can be factored-out, the mantissas must be properly-signed before their addition.  Thus, preparing the two mantissas for addition requires:

1. Determine the difference in exponent between the two values.
    - Any difference greater than 15 in magnitude puts one value completely out of the 16-bit accumulator, and there result is the larger-magnitude value unaltered.
2. For the larger-magnitude value:
    1. OR-in the appropriate implicit digit based on its exponent
    2. Shift **left** until the implicit digit as at index 14 (7 bits)
    3. The result exponent is set to match that of this value.
3. For the smaller-magnitude value:
    1. OR-in the appropriate implicit digit based on its exponent
    2. Given the value of N=(7 - the difference in exponent betwen the two values):
        - Shift **left** N bits if N > 0
        - Shift **right** N bits if N < 0
4. Add the two shifted values.
    1. If the result is exactly zero, return that.
    2. If the overflow flag is set and carry is set, the result is negative and overflowed the 16-bit register.
        - Negate the register and prepare the signed-result to be negative (`0x8000`)
    3. Otherwise, prepare the signed-result to be positive (`0x0000`)
5. Shift the result **right** to place the point back between bits 7 and 6.
6. If bit 8 is set, shift **right** one more time and increment the result exponent.
    - If the result exponent reaches 255, return ±Infinity.
7. As long as bit 7 is NOT set and the result exponent is non-zero, shift **left** and decrement the result exponent.
    - If exponent reaches zero, the value is denormalized.
8. Fill-in the fields of the `BF16` result:
    - Signed-result OR with
    - ((Exponent + 127) << 7) OR with
    - (Mantissa & 0x7F)

As an example, to subtract 0.0625 from 1.5 to get 1.4375, the `BF16` values must first be determined:

```
U = 1 + 0.5 = 2^0 + 2^-1    = 2^0 • (1.1000000)     = 0b0.01111111.1000000 = 0x3FC0
V = 0.0625  = 2^-4          = 2^-4 • (1.0000000)    = 0b0.01111011.0000000 = 0x3B80
```

The addition of the negative:

```
U + (-V) = 0|01111111|1000000 + 1|01111011|0000000
∆EXP     = 127 - 123 = 4
U.MANT   = 1.1000000 << 7           = 0b0110000000000000
V.MANT   = 1.0000000 << (7 - 4 = 3) = 0b0000010000000000
-V.MANT                             =~0b0000010000000000 + 1
                                    = 0b1111101111111111 + 1
                                    = 0b1111110000000000
                     1 11 
U.MANT + (-V.MANT) = 0b0110000000000000
                   + 0b1111110000000000
                   --------------------
                   1 0b0101110000000000
```

The exclusive OR of the carry-in and carry-out of bit 15 is 0, so overflow is not set.  The result is positive:

```
SUM = 01.01110000000000
SUM.MANT = SUM >> 7 = 01.0111000
01.0111000 & 10.0000000 => 0…, bit 8 not set, no right shift/increment
01.0111000 & 01.0000000 => 01…, bit 7 is set, no left shift/decrement
SUM.MANT = 1.0111000, SUM.EXP = U.EXP = 127
```

Since the value is positive, the `BF16` form for the result is

```
SUM = 0|01111111|0111000
    = 0b0011.1111.1011.1000
    = 0x3FB8
```

To validate the result,

```
1.0111 • 2^0 = 2^0 + 2^-2 + 2^-3 + 2^-4 = 1 + 0.25 + 0.125 + 0.0625 = 1.4375
```

Success!

Special rules exist for sums with infinities and NaNs.




## API

### Introspection

The `BF16_CLASSIFY` subroutine inspects the `BF16` value in the accumulator and on return the 8-bit X register contains an enumerated value identifying what kind of value it is.  The function is non-destructive with respect to the accumulator.  The possible categories are:

- `BF16_CLASS_DENORM` (0): denormalized number containing a biased exponent of zero, an implied leading digit of zero, and some number of non-zero bit in the mantissa
- `BF16_CLASS_NORM` (1): a normalized number containing a biased exponent in the range [1,254]
- `BF16_CLASS_INF` (2): biased exponent 255 and a mantissa of zero
- `BF16_CLASS_NAN` (3): biased exponent 255 and a mantissa with some number of non-zero bits

Example:

```
        REP     #$20
        .a16
        LDA     #$F4E9
        JSR     BF16_CLASSIFY
        ;
        ; On return the accumulator still contains $F4E9 and the
        ; X register contains the value 1 (BF16_CLASS_NORM)
        ;
```

#### Is it a NaN?

The `BF16_IS_NAN` subroutine couples a call to `BF15_CLASSIFY` with a check for a result of `BF16_CLASS_NAN`.  On return, if the **C**arry bit is set the number is a NaN.  The X register is clobbered.

Example:

```
        REP     #$20
        .a16
        LDA     #$FFC0
        JSR     BF16_IS_NAN
        BCC     DO_COMPUTATION
        ;
        ; On return the accumulator still contains $FFC0 and the
        ; X register contains the value 3 (BF16_CLASS_NAN), and
        ; the [C]arry bit will be set so we can halt the computation
        ; here.
        ;
```

#### Is it an infinity?

The `BF16_IS_INF` subroutine couples a call to `BF15_CLASSIFY` with a check for a result of `BF16_CLASS_INF`.  On return, if the **C**arry bit is set the number is an infinity.  The X register is clobbered.

Example:

```
        REP     #$20
        .a16
        LDA     #$7F80
        JSR     BF16_IS_INF
        BCS     ALREADY_BIG_ENOUGH
        ;
        ; On return the accumulator still contains $7F80 and the
        ; X register contains the value 2 (BF16_CLASS_INF), and
        ; the [C]arry bit will be set so we can halt the computation
        ; here.
        ;
```

### Addition

Two `BF16` numbers are added by the `BF16_ADD` subroutine.  Before calling the subroutine, the two 16-bit operands to the addition must be pushed to the stack.  On return, the sum is held in the accumulator.

The addition of special values will produce the expected result.  The sum of same-signed infinity is the same signed infinity and the sum of opposite-sign infinities is a NaN.  Denormalized values participate in the sum and are handled as the result of a sum.  The algorithm extends the 7-bit mantissas to 14 bits for intermediate computation of the result.  Values differing on the order of 13 magnitudes of 2 can be properly summed.

Example:

```
        REP     #$20
        .a16
        LDA     #BF16_1_5
        PHA
        LDA     #BF16_1_8
        PHA
        JSR     BF16_ADD
        ;
        ; On return the accumulator will contain the BF16 value of 1/5 + 1/8:
        ;
        ;       0x3E4C + 0x3E00 = 0x3EA6
        ;
```

Example:

```
        REP     #$20
        .a16
        LDA     #BF16_1 | BF16_SIGN_MASK     ; -1
        PHA
        LDA     #BF16_2 | BF16_SIGN_MASK     ; -2
        PHA
        JSR     BF16_ADD
        ;
        ; On return the accumulator will contain the BF16 value of (-1) + (-2) = -3:
        ;
        ;       0xBF80 + 0xC000 = 0xC040
        ;
```

## Example program

The [main.asm](./main.asm) program makes use of the `BF16_ADD` subroutine to sum 40 values from a table and display the results on the 65816 serial console.  See [main.out](./main.out) for the output.
