include ../settings.mk

CFLAGS ?= -g -Wall -Werror -pipe
CPPFLAGS += -I. `pkg-config glib-2.0 --cflags` -DVERSION=\"$(shell cat ../VERSION)\"
LDLIBS = `pkg-config glib-2.0 --libs`

ALLSRC = fb-server.c log.c tools.c game.c net.c
ALLOBJ = $(subst .c,.o,$(ALLSRC))

ifeq (1, $(DEBUG))
CFLAGS := $(CFLAGS) $(ADDCFLAGS) -DDEBUG -g
else
CFLAGS := $(CFLAGS) $(ADDCFLAGS)
endif

all: .depend fb-server

fb-server: $(ALLOBJ)

clean: 
	rm -f fb-server *.o .depend

install:
	install -d $(DESTDIR)$(LIBDIR)/frozen-bubble
	install fb-server $(DESTDIR)$(LIBDIR)/frozen-bubble

.depend:
	$(CPP) $(CFLAGS) $(CPPFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif
