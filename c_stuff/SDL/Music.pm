#!/usr/bin/perl -w

# *** I need this because DESTROY is bugged in official SDL-sdlpl distro ***
# ***                                           --gc                     ***

#       Music.pm
#
#       a SDL_mixer data module
#
#       David J. Goehrig Copyright (C) 2000

package SDL::Music;
use strict;
use SDL::sdlpl;

#
# Music Constructor / Destructor
#

sub new {
        my $proto = shift;
        my $class = ref($proto) || $proto;
        my $self = {};
        my $filename = shift;
        $self->{-data} = SDL::sdlpl::sdl_mix_load_music($filename);
        bless $self,$class;
        return $self;
}

sub DESTROY {
        my $self = shift;
        SDL::sdlpl::sdl_mix_free_music($self->{-data});
}

1;

__END__;


