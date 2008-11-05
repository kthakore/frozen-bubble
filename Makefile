include settings.mk

DIRS = c_stuff po server

all: prepare dirs

prepare:
	echo 'package fb_config;' > c_stuff/lib/fb_config.pm
	echo 'use vars qw(@ISA @EXPORT $$FPATH $$FLPATH);' >> c_stuff/lib/fb_config.pm
	echo '@ISA = qw(Exporter);' >> c_stuff/lib/fb_config.pm
	echo '@EXPORT = qw($$FPATH $$FLPATH);' >> c_stuff/lib/fb_config.pm
	echo '$$FPATH = "$(DATADIR)/frozen-bubble";' >> c_stuff/lib/fb_config.pm
	echo '$$FLPATH = "$(LIBDIR)/frozen-bubble";' >> c_stuff/lib/fb_config.pm
	perl -ne "print \$$1 if m|\\\$$version = '(.*)';|" c_stuff/lib/fb_stuff.pm > VERSION

dirs:
	@if ! perl -e 'use SDL'; then echo -e "\n    *** I need perl-SDL installed"; false; fi
	@if ! perl -e 'use SDL; ($$mj, $$mn, $$mc) = split /\./, $$SDL::VERSION; exit 0 if $$mj > 1 || $$mn >= 19; exit 1'; then echo -e "\n    *** I need perl-SDL version 1.19.0 or upper"; false; fi
	@for n in . $(DIRS); do \
		[ "$$n" = "." ] || $(MAKE) -C $$n || exit $$? ;\
	done


install: $(ALL)
	@for n in $(DIRS); do \
		(cd $$n; $(MAKE) install) \
	done
	install -d $(DESTDIR)$(BINDIR)
	install frozen-bubble frozen-bubble-editor $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(DATADIR)/frozen-bubble
	cp -a gfx snd data $(DESTDIR)$(DATADIR)/frozen-bubble
	install -d $(DESTDIR)$(MANDIR)/man6
	install doc/*.6 $(DESTDIR)$(MANDIR)/man6

clean: 
	@for n in $(DIRS); do \
		(cd $$n; $(MAKE) clean) \
	done
	@rm -f c_stuff/lib/fb_config.pm

