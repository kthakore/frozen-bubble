#!/usr/bin/perl -w
#	Sound.pm
#
#	a SDL_mixer data module
#
#	David J. Goehrig Copyright (C) 2000

package SDL::Sound;
use strict;
use SDL::sdlpl;

#
# Sound Constructor / Destructor
#

sub new {
	my $proto = shift;	
	my $class = ref($proto) || $proto;
	my $self = {};
	my $filename = shift;
	$self->{-data} = SDL::sdlpl::sdl_mix_load_wav($filename);
	bless $self,$class;
	return $self;
}

sub DESTROY {
	my $self = shift;
	SDL::sdlpl::sdl_mix_free_chunk($self->{-data});
}

#
# Sound->volume
#

sub volume {
	my $self = shift;
	my $volume = shift;
	return SDL::sdlpl::sdl_mix_chunk_volume($self->{-data},$volume);
}

1;

__END__;


