#!/bin/sh

#- run to generate latest keysyms out of /usr/include/SDL/SDL_keysym.h
perl -ne 'BEGIN { print "package fbsyms;\n\@syms = qw(" } END { print ");\n" } /SDLK_(\S+)/ and print "$1 "' /usr/include/SDL/SDL_keysym.h > ../c_stuff/lib/fbsyms.pm
