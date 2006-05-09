
CFLAGS ?= -Wall -Werror -pipe `glib-config --cflags`
LIBS ?= `glib-config --libs`

ALLSRC = fb-server.c log.c tools.c game.c net.c
ALLOBJ = $(subst .c,.o,$(ALLSRC))

ifeq (1, $(DEBUG))
CFLAGS := $(CFLAGS) $(ADDCFLAGS) -DDEBUG -g
else
CFLAGS := $(CFLAGS) $(ADDCFLAGS)
endif

all: .depend fb-server

fb-server: $(ALLOBJ)
	$(CC) $(LIBS) -o $@ $^

.c.o:
	$(CC) -I. $(CFLAGS) -c $<

fb-server.o:
	$(CC) -I. $(CFLAGS) -DVERSION=#VERSION# -c $<

clean: 
	rm -f fb-server *.o .depend

install:
	@echo Installed from main Makefile

.depend:
	$(CPP) $(CFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif
