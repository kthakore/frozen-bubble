
CFLAGS ?= -Wall -Werror -pipe `glib-config --cflags`
LIBS ?= `glib-config --libs`

all: fb-server

fb-server: fb-server.o log.o tools.o
	$(CC) $(LIBS) -o $@ $^

.c.o:
	$(CC) -I. $(CFLAGS) -c $<

clean: 
	rm -f fb-server *.o

.depend:
	$(CPP) $(CFLAGS) -M $(ALLSRC) > .depend

ifeq (.depend,$(wildcard .depend))
include .depend
endif
