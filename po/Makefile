PREFIX = /usr/local
DATADIR = $(PREFIX)/share
LOCALEDIR = $(DATADIR)/locale

PGOAL = frozen-bubble

# files to search translatable strings in
PL_FILES = ../frozen-bubble

POFILES = $(wildcard *.po)
MOFILES = $(POFILES:%.po=%.mo)

all: $(MOFILES)

$(PGOAL).pot: $(PL_FILES)
	rm -f $@
	xgettext --keyword=t --language=perl --default-domain=frozen-bubble --from-code=UTF-8 -o $@ $(PL_FILES)

merge: $(PGOAL).pot
	@for n in $(POFILES); do \
		echo "Merging $$n"; \
		msgmerge "$$n" $< > "$$n"t; \
		mv -f "$$n"t "$$n"; \
	done

%.mo: %.po
	msgfmt $< -o $@

install: $(MOFILES)
	install -d $(DESTDIR)$(LOCALEDIR)
	@for n in $(MOFILES); do \
		echo install $$n $(DESTDIR)$(LOCALEDIR)/`echo $$n | sed -e 's/.mo//'`/LC_MESSAGES/frozen-bubble.mo; \
		install -d $(DESTDIR)$(LOCALEDIR)/`echo $$n | sed -e 's/.mo//'`; \
		install -d $(DESTDIR)$(LOCALEDIR)/`echo $$n | sed -e 's/.mo//'`/LC_MESSAGES; \
		install -m 0644 $$n $(DESTDIR)$(LOCALEDIR)/`echo $$n | sed -e 's/.mo//'`/LC_MESSAGES/frozen-bubble.mo; \
	done

clean:
	@rm -rf $(PGOAL).pot *.mo
