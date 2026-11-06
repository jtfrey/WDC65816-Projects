# WDC65816 Projects

The Western Design Center [65C816 microprocessor](https://www.westerndesigncenter.com/wdc/w65c816s-chip.php) is a 16-bit extension of the classic MOS 6502.  This repository collects various projects I've written for that MPU.

All programs can be assembled with the [ca65](https://cc65.github.io/doc/ca65.html) tools using the include Makefiles.  In some cases I've had success building SNES ROM images from the code, which makes them executable (with fantastic debugging control) in the [Mesen emulator](https://www.mesen.ca).

A more fun alternative is the [WD65C816SXB single board computer](https://wdc65xx.com/Single-Board-Computers/w65c816sxb/).  The other hardware on the system bus is (naturally) not simulated by Mesen and makes for additional project possibilities beyond algorithm design and testing.

## BF16

The `BFLOAT16` floating-point type can represent real numbers with the same exponent range as an `FP32` but much less precision (7 bits vs. 23 bits for `FP32`).  That imprecision is often acceptable in AI applications, for example.

I'm not going to be porting ChatGPT to a 65816, but it was a fun project anyway.  The source includes an implementation of addition and multiplication as well as basic introspection of a value.

## IDIV

Adding a division subroutine to `BF16` requires that I have a good handle on 16-bit integer division first.  The `IDIV` subproject produced two subroutines that vary only in how they utilize memory.  One relies completely on the stack, the other uses direct page words.

