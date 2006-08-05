DIRS = c_stuff po server

PREFIX = /usr/local
DATADIR = $(PREFIX)/share
LIBDIR = $(PREFIX)/lib
BINDIR = $(PREFIX)/bin
MANDIR = $(DATADIR)/man

all: prepare dirs

prepare:
	perl -ne "print \$$1 if m|\\\$$version = '(.*)';|" frozen-bubble > VERSION
	@if [ "$(DEJAVUPATH)" = "" ]; then echo -e "\n    *** You need to set DEJAVUPATH. Read INSTALL to learn what to set there."; false; fi
	@if [ "$(DEJAVUOBLIQUEPATH)" = "" ]; then echo -e "\n    *** You need to set DEJAVUOBLIQUEPATH. Read INSTALL to learn what to set there."; false; fi
	@if [ "$(SAZANAMIGOTHICPATH)" = "" ]; then echo -e "\n    *** You need to set SAZANAMIGOTHICPATH. Read INSTALL to learn what to set there."; false; fi

dirs:
	@if ! perl -e 'use SDL'; then echo -e "\n    *** I need perl-SDL installed"; false; fi
	@if ! perl -e 'use SDL; ($$mj, $$mn, $$mc) = split /\./, $$SDL::VERSION; exit 1 if $$mj<1 || $$mn<19'; then echo -e "\n    *** I need perl-SDL version 1.19.0 or upper"; false; fi
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || $(MAKE) -C $$n ;\
	done
	@if [ ! -d save_virgin ]; then mkdir save_virgin; cp c_stuff/lib/fb_stuff.pm save_virgin; fi
	cp -f save_virgin/fb_stuff.pm c_stuff/lib/fb_stuff.pm
	perl -pi -e 's|\@DATADIR\@|$(DATADIR)|' c_stuff/lib/fb_stuff.pm
	perl -pi -e 's|\@LIBDIR\@|$(LIBDIR)|' c_stuff/lib/fb_stuff.pm
	@if [ "$(DEJAVUPATH)" = "internal" ]; then \
	    perl -pi -e 's|\@DEJAVUPATH\@|$(DATADIR)/frozen-bubble/data/DejaVuSans.ttf|' c_stuff/lib/fb_stuff.pm; \
        else \
	    perl -pi -e 's|\@DEJAVUPATH\@|$(DEJAVUPATH)|' c_stuff/lib/fb_stuff.pm; \
	    rm -f data/DejaVuSans.ttf; \
	fi
	@if [ "$(DEJAVUOBLIQUEPATH)" = "internal" ]; then \
	    perl -pi -e 's|\@DEJAVUOBLIQUEPATH\@|$(DATADIR)/frozen-bubble/data/DejaVuSans-Oblique.ttf|' c_stuff/lib/fb_stuff.pm; \
        else \
	    perl -pi -e 's|\@DEJAVUOBLIQUEPATH\@|$(DEJAVUOBLIQUEPATH)|' c_stuff/lib/fb_stuff.pm; \
	    rm -f data/DejaVuSans-Oblique.ttf; \
	fi
	@if [ "$(SAZANAMIGOTHICPATH)" = "internal" ]; then \
	    perl -pi -e 's|\@SAZANAMIGOTHICPATH\@|$(DATADIR)/frozen-bubble/data/sazanami-gothic.ttf|' c_stuff/lib/fb_stuff.pm; \
        else \
	    perl -pi -e 's|\@SAZANAMIGOTHICPATH\@|$(SAZANAMIGOTHICPATH)|' c_stuff/lib/fb_stuff.pm; \
	    rm -f data/sazanami-gothic.ttf; \
	fi


install: $(ALL)
	@for n in $(DIRS); do \
		(cd $$n; $(MAKE) install) \
	done
	install -d $(BINDIR)
	install frozen-bubble frozen-bubble-editor $(BINDIR)
	install -d $(DATADIR)/frozen-bubble
	cp -a gfx snd data $(DATADIR)/frozen-bubble
	rm -f $(DATADIR)/frozen-bubble/gfx/shoot/create.pl
	install -d $(LIBDIR)/frozen-bubble
	install server/fb-server $(LIBDIR)/frozen-bubble
	install -d $(MANDIR)/man6
	install doc/*.6 $(MANDIR)/man6

clean: 
	@for n in $(DIRS); do \
		(cd $$n; $(MAKE) clean) \
	done
	@if [ -d save_virgin ]; then cp -f save_virgin/fb_stuff.pm c_stuff/lib/fb_stuff.pm; rm -rf save_virgin; fi

