
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
	dasm $(SRC) -Iinclude -f3 -v4 -o$@ -s$(@:.bin=.sym) -DSYSTEM=$(word 2,$(subst ., ,$(subst _, ,$@))) > $(@:.bin=.log)

.PHONY: clean
clean:
	rm $(ROMDIR)/*
