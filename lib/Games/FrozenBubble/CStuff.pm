package Games::FrozenBubble::CStuff;

use strict;
use vars qw(@ISA);
use Games::FrozenBubble;
use SDL::Pango;
use SDL::Pango::Context;

require DynaLoader;

@ISA = qw(DynaLoader);

bootstrap Games::FrozenBubble::CStuff $Games::FrozenBubble::VERSION;

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

sub sdlpango_draw{ return sdlpango_draw_givenalignment(shift, shift, shift, "left"); }
sub sdlpango_draw_givenalignment{
	my $context   = shift;
	my $text      = shift;
	my $width     = shift;
	my $alignment = shift;
	SDL::Pango::set_minimum_size($context, $width, 0);
	SDL::Pango::set_text($context, $text, -1, $alignment == "left" ? SDLPANGO_ALIGN_LEFT
	                                                               : $alignment == "center" ? SDLPANGO_ALIGN_CENTER
	                                                                                        : SDLPANGO_ALIGN_RIGHT );
	return SDL::Pango::create_surface_draw($context);
}

1;

