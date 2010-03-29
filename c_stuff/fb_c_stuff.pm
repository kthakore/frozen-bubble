package fb_c_stuff;

use strict;
use vars qw($VERSION @ISA);
use SDL::Pango;
use SDL::Pango::Context;

require DynaLoader;

@ISA = qw(DynaLoader);
$VERSION = '1.0';

bootstrap fb_c_stuff $VERSION;

sub sdlpango_init{ SDL::Pango::init(); }
sub sdlpango_createcontext{
	my $color     = shift;
	my $font_desc = shift;
	my $context   = SDL::Pango::Context->new($font_desc);
	SDL::Pango::set_default_color($context, $color == "white" ? 0xFFFFFFFF : 0x000000FF, 0x00000000);
	
	return $context;
}

sub sdlpango_getsize{
	my $context = shift;
	my $text    = shift;
	my $width   = shift;
	
	SDL::Pango::set_minimum_size($context, $width, 0);
	SDL::Pango::set_text($context, $text, -1);
	my $w = SDL::Pango::get_layout_width($context);
	my $h = SDL::Pango::get_layout_height($context);
	
	return [$w, $h];
}


1;

