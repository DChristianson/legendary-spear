
DEFAULT_TARGET: all

ROMDIR = roms
ASMS = LegendarySpear.asm LegendarySpear4k.asm
SYSTEMS = NTSC PAL60
ROMS = $(foreach ASM, $(ASMS), $(foreach SYSTEM,$(SYSTEMS),$(ROMDIR)/$(ASM:.asm=)_$(SYSTEM).bin))

all: $(ROMDIR) $(ROMS)

$(ROMDIR):
	mkdir -p $@
	touch $@

$(ROMS): $(ASMS)
	$(eval ASM := $(word 2,$(subst _, ,$(subst /, ,$@))))
	$(eval SYSTEM := $(word 2,$(subst ., ,$(subst _, ,$@))))
	dasm $(ASM).asm -Iinclude -f3 -v4 -o$@ -s$(@:.bin=.sym) -l$(@:.bin=.lst) -MSYSTEM=$(SYSTEM) > $(@:.bin=.log)
	cat $(SYSTEM).script > $(@:.bin=.script)

.PHONY: clean
clean:
	rm $(ROMDIR)/*
