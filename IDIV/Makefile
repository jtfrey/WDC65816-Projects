#
# Makefile for the IDIV source project
#

AS	= ca65
ASFLAGS	= --verbose --listing $*.sym

LD	= ld65
LDFLAGS	= -v -C idiv.cfg -D __OBJ_ADDR__=0x2100

#
# Explicit rules:
#

.PHONY: all clean

default: idiv.bin

clean::
	$(RM) *.o *.sym idiv.bin

idiv.bin: idiv.o idiv.cfg

#
# Patterned rules:
#

%.bin:
	$(LD) $(LDFLAGS) $(filter %.o, $+) -o $@

%.o: %.asm
	ca65 -o $@ $< --verbose --listing $*.sym
	
