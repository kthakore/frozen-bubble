package Games::FrozenBubble::CStuff;

use strict;
use vars qw(@ISA);
use Games::FrozenBubble;
use SDL::Pango;
use SDL::Pango::Context;
use Alien::SDL;

require DynaLoader;

@ISA = qw(DynaLoader);

# Dynaloader dark magic implemented by kmx, this is needed as we are
# using Alien::SDL and required dynamic libraries are saved in Alien::SDL's
# distribution share dir - therefore we need to load them explicitely
# for more details see SDL::Internal::Loader (code stolen from there)
my $shlib_map = Alien::SDL->config('ld_shlib_map');
if($shlib_map) {
  foreach my $n (qw(SDL SDL_mixer)) {
    my $file = $shlib_map->{$n};
    next unless $file;
    my $libref = DynaLoader::dl_load_file($file, 0);
    push(@DynaLoader::dl_librefs, $libref) if $libref;
  }
}

bootstrap Games::FrozenBubble::CStuff $Games::FrozenBubble::VERSION;

sub sdlpango_init{ SDL::Pango::init(); }
sub sdlpango_createcontext{
        my $color     = shift || '';
        my $font_desc = shift;
        my $context   = SDL::Pango::Context->new($font_desc);
       
       
        #context, fr, fg, fb, fa, br, bg, bb, ba
        if ($color eq "white")  
        { 
                SDL::Pango::set_default_color($context, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00) 
        }
        else 
        {
                SDL::Pango::set_default_color($context, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00)
        }
       
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
        my $alignment = shift || '';
        SDL::Pango::set_minimum_size($context, $width, 0);
        SDL::Pango::set_text($context, $text, -1, $alignment eq "left" ? SDLPANGO_ALIGN_LEFT
                                                                       : $alignment eq "center" ? SDLPANGO_ALIGN_CENTER
                                                                                                : SDLPANGO_ALIGN_RIGHT );
        return SDL::Pango::create_surface_draw($context);
}

1;
