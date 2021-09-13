
DEFAULT_TARGET: all

ROMDIR = roms
SRC = $(wildcard *.asm)
SYSTEMS = NTSC PAL60
ROMS = $(foreach SYSTEM,$(SYSTEMS),$(ROMDIR)/$(SRC:.asm=)_$(SYSTEM).bin)

all: $(ROMDIR) $(ROMS)

$(ROMDIR):
	mkdir -p $@
	touch $@

$(ROMS): $(SRC)
	$(eval SYSTEM := $(word 2,$(subst ., ,$(subst _, ,$@))))
	dasm $(SRC) -Iinclude -f3 -v4 -o$@ -s$(@:.bin=.sym) -l$(@:.bin=.lst) -MSYSTEM=$(SYSTEM) > $(@:.bin=.log)
	cat $(SYSTEM).script > $(@:.bin=.script)

.PHONY: clean
clean:
	rm $(ROMDIR)/*
