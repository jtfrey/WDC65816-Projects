#
# Makefile for the BF16 source project
#

AS	= ca65
ASFLAGS	= --verbose --listing $*.sym

LD	= ld65
LDFLAGS	= -v -C bf16.cfg -D __OBJ_ADDR__=0x500

#
# Explicit rules:
#

.PHONY: all clean

default: bf16.bin

clean::
	$(RM) *.o *.sym bf16.bin

bf16.bin: main.o bf16.o bf16.cfg

#
# Patterned rules:
#

%.bin:
	$(LD) $(LDFLAGS) $(filter %.o, $+) -o $@

%.o: %.asm
	ca65 -o $@ $< --verbose --listing $*.sym
	
