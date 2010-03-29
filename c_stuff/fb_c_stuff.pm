package fb_c_stuff;

use strict;
use vars qw($VERSION @ISA);
use SDL::Pango;

require DynaLoader;

@ISA = qw(DynaLoader);
$VERSION = '1.0';

bootstrap fb_c_stuff $VERSION;

sub sdlpango_init{ SDL::Pango::init(); }

#/* only "white" and "black" are supported in the color parameter */
#SDLPango_Context* sdlpango_createcontext_(char* color, char* font_desc)
#{
#        SDLPango_Context * context = SDLPango_CreateContext_GivenFontDesc(font_desc);
#        if (!strcmp(color, "white")) {
#                SDLPango_SetDefaultColor(context, MATRIX_TRANSPARENT_BACK_WHITE_LETTER);
#        } else {
#                SDLPango_SetDefaultColor(context, MATRIX_TRANSPARENT_BACK_BLACK_LETTER);
#        }
#        return context;
#}

1;

