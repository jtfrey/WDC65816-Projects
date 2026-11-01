# BF16 on the 65816

The WDC 65816 is a descendent of the 6502 and 65C02 microprocessor that expands the three registers (X/Y/A) to 16-bits.  The arithmetic and logic instructions — add/subtract/increment/decrement, and/or/xor, bit test and shift — modally-function in either 8-bit or 16-bit.  With a native 16-bit accumulator, a 16-bit floating-point type is more easily implemented.

The [BFLOAT16](https://arxiv.org/abs/1905.12322) or `BF16` type essentially truncates a `FP32` to its most-significant byte (MSB), retaining the sign bit, 8-bit exponent, and just 7 mantissa bits rather than 23.  The `FP16` type uses a more-balanced 5-bit exponent with 10 mantiassa bits, but for target applications `BF16`'s sacrifice of precision for the sake of range was acceptable.

The [bf16.asm](./bf16.asm) file contains the 65816 source that implements numeric introspection subroutines and an addition subroutine.  All are expected to be called in native mode with the accumulator in 16-bit mode.  The [bf16.inc](./bf16.inc) file contains constant definitions.

## Introspection

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

### Is it a NaN?

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

### Is it an infinity?

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

## Addition

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

### Example program

The [main.asm](./main.asm) program makes use of the `BF16_ADD` subroutine to sum 40 values from a table and display the results on the 65816 serial console.  See [main.out](./main.out) for the output.
