# Integer division on the 65816

The [idiv.asm](./idiv.asm) file contains two subroutines using the 16-bit accumulator to perform integer division.  The subroutines return the quotient and remainder, so they also function as a modulus function.

The `DIDIV16` subroutine uses pseudo-registers in the direct page of memory for its operands and scratch storage.  All ALU instructions implement direct page mode; more notably, the bit shift and increment/decrement instructions operate directly on the value in the direct page location without explicitly having to load them into the accumulator and perform a write-back.  This variant is 62 bytes in size.

The `SIDIV16` subroutine expects the dividend and divisor to be pushed to the stack before it is called.  Only storage on the stack is used in conjunction with the 65816 stack-relative addressing mode; since that mode is not available to all ALU operations, data need to be moved in and out of the accumulator more frequently.  Addresses are single-byte offsets (relative to the stack pointer) and incur a one cycle penalty to compute the target address.  The subroutine is 73 bytes in size.

Both subroutines check for divide by zero; dividend equal to divisor; and divisor greater than the dividend; and return appropriate values.  In particular, on divide by zero the quotient returned is zero and the remainder is max int (`$FFFF`).


## Background

The procedure for long division requires that the divisor be aligned with the left-most digit of the dividend for which some non-zero multiple of the divisor is less-than or equal to the eclipsed portion of the dividend.  For example, when dividing 5555 by 5 this would be the thousands position; for division by 11 it would be the hundreds position.  In base ten the multiple will be valued in the range [0…9]; in binary, the multiple is necessarily just 0 or 1.  Otherwise, the procedure for binary long division is the same:

```
          1000000001101 R 0
      _________________
1101 | 1101000010101001
       1101
       ----
          0000010101
                1101
                ----
                10000
                 1101
                 ----
                   1101
                   1101
                   ----
                      0
```

An example with division by 2 may be more easily illustrated; the first step is aligning the divisor with the dividend such that one more position would cause it to exceed the dividend:

```
dividend    1101001101011011                 0   quotient
                  10 << 15
divisor    10000000000000000 >>  1
divisor     1000000000000000
```

A one is shifted into the quotient and the divisor is subtracted from the dividend; the divisor is shifted right one position, too:

```
dividend    1101001101011011                01   quotient
divisor    -1000000000000000
            ----------------
dividend     101001101011011
divisor      100000000000000
```

The process is repeated until the divisor is half its original value:

```
dividend    1101001101011011                01   quotient
divisor    -1000000000000000
            ----------------
dividend     101001101011011               011   quotient
divisor     -100000000000000
             ---------------
dividend       1001101011011              0110   quotient
divisor       10000000000000
              --------------
dividend       1001101011011             01101   quotient
divisor       -1000000000000
               -------------
dividend          1101011011            011010   quotient
divisor         100000000000
                ------------
dividend          1101011011           0110100   quotient
divisor          10000000000
                 -----------
dividend          1101011011          01101001   quotient
divisor          -1000000000
                  ----------
dividend           101011011         011010011   quotient
divisor           -100000000
                   ---------
dividend             1011011        0110100110   quotient
divisor             10000000
                    --------
dividend             1011011       01101001101   quotient
divisor             -1000000
                     -------
dividend               11011      011010011010   quotient
divisor               100000
                      ------
dividend               11011     0110100110101   quotient
divisor               -10000
                       -----
dividend                1011    01101001101011   quotient
divisor                -1000
                        ----
dividend                  11   011010011010110   quotient
divisor                  100
                         ---
dividend                  11  0110100110101101   quotient
divisor                  -10
                          --
                           1
```

The quotient is `0b110100110101101` with a remainder of `1` — which makes sense since division by 2 shifts right and drops the bit off the right-hand end.

The `DIDIV16` and `SIDIV16` subroutines implement 16-bit binary long division.
