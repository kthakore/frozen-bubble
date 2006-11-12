include ../settings.mk

.PHONY: clean

fb_c_stuff: %: %.xs
	test -e Makefile_c || perl Makefile.PL INSTALLDIRS=$(INSTALLDIRS)
	$(MAKE) -f Makefile_c

install:
	test -e Makefile_c || perl Makefile.PL INSTALLDIRS=$(INSTALLDIRS)
	$(MAKE) -f Makefile_c install

clean:
	test ! -e Makefile_c || $(MAKE) -f Makefile_c clean
	rm -f *~ *.o
