# 
#	Surface.pm
#
#	A package for manipulating SDL_Surface *
#
#	David J. Goehrig Copyright (C) 2000

package SDL::Surface;
use strict;
use SDL::sdlpl;
require SDL::Rect;
require SDL::Palette;

require Exporter;



#
# Surface Constructor / Destructor
#

sub new {
	my $proto = shift;										# Std constructor
	my $class = ref($proto) || $proto;
	my $self = {};
	my %options = @_;									# Usage: new Surface ( 
	if ( exists($options{-name}) ) 
	  {		                         						# -name => "yomama.jpg" ); 	to load and image else
	   $self->{-surface} = SDL::sdlpl::sdl_new_surface($options{-name},0,0,0,0,0,0,0,0);	# Loads, bmp, ppm, pcx, gif, jpeg, png images
	  } 
	elsif (exists($options{-from}))        # create from a memory block (typically another XS lib  (i.e. PDL) with 'fixed' memory locations!
	  {
		my $w = $options{-width} || 0;				# -width => 800, 		to set the width 
		my $h = $options{-height} || 0;				# -height => 600,		to set the height
		my $d = $options{-depth} || 0;				# -depth => 8,			to set the bitsperpixel
		my $p = $options{-pitch} || 0;                          
		my $r = $options{-Rmask} || 0x000000ff;			# -Rmask => 0xff000000,		for big endian machines
		my $g = $options{-Gmask} || 0x0000ff00;			# -Gmask => 0x00ff0000,		ditto
		my $b = $options{-Bmask} || 0x00ff0000;			# -Bmask => 0x0000ff00,		ditto
		my $a = $options{-Amask} || 0xff000000;			# -Amask => 0x000000ff );	ditto
		$self->{-surface} = SDL::sdlpl::sdl_new_surface_from($options{-from},$w,$h,$d,$p,$r,$g,$b,$a);
		
	  }
	else 
	  {
		my $f = $options{-flags} || SDL::sdlpl::sdl_anyformat();	         	# -flags => SDL_ANYFORMAT,	to set the flags
		my $w = $options{-width} || 0;				# -width => 800, 		to set the width 
		my $h = $options{-height} || 0;				# -height => 600,		to set the height
		my $d = $options{-depth} || 0;				# -depth => 8,			to set the bitsperpixel
		my $r = $options{-Rmask} || 0x000000ff;			# -Rmask => 0xff000000,		for big endian machines
		my $g = $options{-Gmask} || 0x0000ff00;			# -Gmask => 0x00ff0000,		ditto
		my $b = $options{-Bmask} || 0x00ff0000;			# -Bmask => 0x0000ff00,		ditto
		my $a = $options{-Amask} || 0xff000000;			# -Amask => 0x000000ff );	ditto
		$self->{-surface} = SDL::sdlpl::sdl_new_surface("",$f,$w,$h,$d,$r,$g,$b,$a);
	}
	bless $self,$class;
	return $self;
}

sub DESTROY {												# Object Destructor
	my $self = shift;	
	SDL::sdlpl::sdl_free_surface($self->{-surface});							# this function free the structure's memory
}

#
# Surface fields	###	READ-ONLY	###
#

sub flags {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_flags($self->{-surface});
}

sub palette {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_palette($self->{-surface});
}

sub bpp {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_bits_per_pixel($self->{-surface});
}

sub bytes_per_pixel {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_bytes_per_pixel($self->{-surface});
}

sub Rshift {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_rshift($self->{-surface});
}

sub Gshift {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_gshift($self->{-surface});
}

sub Bshift {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_bshift($self->{-surface});
}

sub Ashift {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_ashift($self->{-surface});
}

sub Rmask {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_rmask($self->{-surface});
}

sub Gmask {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_gmask($self->{-surface});
}

sub Bmask {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_bmask($self->{-surface});
}

sub Amask {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_amask($self->{-surface});
}

sub color_key {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_colorkey($self->{-surface});
}

sub alpha {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_alpha($self->{-surface});
}

sub width {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_w($self->{-surface});
}

sub height {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_h($self->{-surface});
}

sub clip_minx {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_clip_minx($self->{-surface});
}

sub clip_miny {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_clip_miny($self->{-surface});
}


sub clip_maxx {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_clip_maxx($self->{-surface});
}

sub clip_maxy {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_clip_maxy($self->{-surface});
}

sub pitch {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_pitch($self->{-surface});
}

sub pixels {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_pixels($self->{-surface});
}

#
# Swiss-Army-Chainsaw pixel
#
# 	returns pixel value at (x,y)
#	if given an additional arg, will set pixel to (x,y,c) and will return the color it is set to.
#	FYI: RGB -> 16bit -> RGB does not always return the same number due to lossage
# 
#	*** Warining *** lock before using
#	

sub pixel {
	my $self = shift;
	if ( 3 == @_ ) {										# paranoid
		my ($x, $y, $color) = @_;								# do a write
		return SDL::sdlpl::sdl_surface_pixel($self->{-surface},$x,$y,$color);			# return for verification
	} else {											# else
		my ($x,$y) = @_;									# do just a read
		return SDL::sdlpl::sdl_surface_pixel($self->{-surface},$x,$y);				# return the value
	}
}

sub fill {
	my $self = shift;
	my $rect = shift;
	my $color = shift;
	return SDL::sdlpl::sdl_fill_rect($self->{-surface},$rect->{-rect},$color);
}

#
# Locking and Unlocking
#

sub lockp {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_must_lock($self->{-surface});
}

sub lock {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_lock($self->{-surface});
}

sub unlock {
	my $self = shift;
	return SDL::sdlpl::sdl_surface_unlock($self->{-surface});
}

#
# Updating bliting and the like
#

sub update {
	my $self = shift;
	my @irects = @_;
	my @rects;
	my $rect;
	
	for $rect (@irects) { push @rects, $rect->{-rect}; }
	SDL::sdlpl::sdl_update_rects ($self->{-surface}, @rects );
}

sub flip {
	my $self = shift;
	SDL::sdlpl::sdl_flip($self->{-surface});
}

sub blit {
	my $self = shift;
	my $srect = shift;
	my $dest = shift;
	my $drect = shift;
	return SDL::sdlpl::sdl_blit_surface($self->{-surface},$srect->{-rect},$dest->{-surface},$drect->{-rect});
}

#
# Palette mangling, trans, and alpha
#


sub set_colors {
	my $self = shift;
	my $start = shift;
	return SDL::sdlpl::sdl_set_colors($self->{-surface},$start,@_);
}

sub set_color_key {
	my $self = shift;
	my $flag = shift;
	my $pixel = shift;
	return SDL::sdlpl::sdl_set_color_key($self->{-surface},$flag,$pixel);
}

sub set_alpha {
	my $self = shift;
	my $flag = shift;
	my $alpha = shift;
	return SDL::sdlpl::sdl_set_alpha($self->{-surface},$flag,$alpha);
}


#
# Clipping and format
#

sub clip {
	my $self = shift;
	my $top = shift;
	my $left = shift;
	my $bottom = shift;
	my $right = shift;
	SDL::sdlpl::sdl_set_clipping($self->{-surface},$top,$left,$bottom,$right);
}

sub display_format {
	my $surface = shift;
	my $tmp = SDL::sdlpl::sdl_display_format($surface->{-surface});
	SDL::sdlpl::sdl_free_surface($surface->{-surface});
	$surface->{-surface} = $tmp;
	return $surface;
}

# Font support added Fri May 26 11:00:59 EDT 2000

sub print {
	my $self = shift;
	my $x = shift;
	my $y = shift;
	SDL::sdlpl::sdl_sfont_surface_print( $self->{-surface},
		$x, $y, join('',@_));
}

# Saving surface as BMP

sub save_bmp {
	my $self = shift;
	my $filename = shift;
	return SDL::sdlpl::sdl_save_bmp( $self->{-surface}, $filename);
}

#vid info debug helper
sub video_info {
	my $self = shift;
	return SDL::sdlpl::sdl_video_info ();
}


#helpers 
sub field_report
  {
   my $self=shift;
   my $hex_format="0x%08x";
   my $report="";
   $report.="Flags:      ".sprintf($hex_format,$self->flags())."\n";
   $report.="Pallete:    ".$self->palette()."\n"; 
   $report.="bits pix:   ".$self->bpp()."\n";
   $report.="bytes pix:  ".$self->bytes_per_pixel()."\n";

   $report.="Rshift:     ".$self->Rshift()."\n";
   $report.="Gshift:     ".$self->Gshift()."\n";
   $report.="Bshift:     ".$self->Bshift()."\n";
   $report.="Ashift:     ".$self->Ashift()."\n";

   $report.="Rmask:      ".sprintf($hex_format,$self->Rmask())."\n";
   $report.="Bmask:      ".sprintf($hex_format,$self->Gmask())."\n";
   $report.="Bmask:      ".sprintf($hex_format,$self->Bmask())."\n";
   $report.="Amask:      ".sprintf($hex_format,$self->Amask())."\n";
   $report.="ColourKey:  ".$self->color_key()."\n";
   $report.="Alpha:      ".$self->alpha()."\n";
   $report.="Width:      ".$self->width()."\n";
   $report.="Height:     ".$self->height()."\n";
   $report.="Clip_Min_x: ".$self->clip_minx()."\n";
   $report.="Clip_Min_y: ".$self->clip_miny()."\n";
   $report.="Clip_Max_x: ".$self->clip_maxx()."\n";
   $report.="Clip_Max_y: ".$self->clip_maxy()."\n";
   $report.="Pitch:      ".$self->pitch()."\n";
   return $report;
}


1;

__END__;

=head1 NAME

SDL::Surface - a SDL perl extension

=head1 SYNOPSIS

  use SDL::Surface;
  $image = new SDL::Surface(-name=>"yomama.jpg");

=head1 DESCRIPTION

	
	SDL::Surface->new(-name=>"yomama.jpg"); will load an image named
yomama.jpg, which works equally well with images of type bmp, ppm, pcx,
gif, jpeg, and png. Optionally, if you would like a scratch surface 
to work with, you can createit using this function using the following
syntax:

SDL::Surface->new(-flags=>SDL_SWSURFACE,-width=>666,-height=>666,-depth=>8);

which will produce a software suface, at 666x666x256 colors.  To create an
image using the default depth and flag state simply use:

SDL::Surface->new(-width=>$my_w,-height=>$my_h);

If you are on a big endian machine, or some really funky hardware you can
set the RGBA bitmasks with the keys -Rmask, -Gmask, -Bmask, -Amask.
For example to create a scratch surface on a big endian machine one would
use:
	SDL::Surface->new(-width=>200,-height=>100,
		-Rmask=>0xff000000,-Gmask=>0x00ff0000,
		-Bmask=>0x0000ff00,-Amask=>0x000000ff);

=head2 DESTROY

	When a surface is destroyed, perl will call SDL_FreeSurface() on
it. Hence don't worry about freeing it yourself.  If you must, then 
invoke the function SDL::sdlpl::sdl_free_surface($your_surface);

=head2 Read-only Surface fields

	The SDL_Surface structure has many subfields.  Most of these
fields are accessible in read-only form.  Most of these fields are
useless to a perl hacker anyways, and are provided for a sense
of completeness.

$surface->flags()
	
	This field returns the flags which are applicable to the
current surface.  The possible values for the flags are:

		SDL_ANYFORMAT
		SDL_SWSURFACE
		SDL_HWSURFACE
		SDL_HWPALETTE
		SDL_DOUBLEBUF
		SDL_FULLSCREEN

$surface->palette()
	
	This field returns a pointer to the SDL_Palette
structure for this image if it is an 8 bit image, or NULL
if the image is 16, 24, or 32 bit.  cf. Palette.pm
NB: this should not be passed to any Palette method.
what you need there is to create a new Palette object,
passing it the image as in:

	my $pal = new SDL::Palette $image;

cf Palette.pm for details.

$surface->bpp()

	This field returns the bits per pixel, aka depth,
of the surface.

$surface->bytes_per_pixel()

	This field returns the bytes per pixel, this should
in all cases be the same as bpp/8.  Technically, it reads
that field of the SDL_PixelFormat structure for the surface.

$surface->Rshift(); $surface->Gshift(); ...

	These functions return the Rshift, Gshift, Bshift, and
Ashift respectively for the surface.  To be perfectly honest,
these are not all that useful from perl, but are provided
for future expansion.

$surface->Rmask(), $surface->Gmask() ...

	Like Rshift & friends, Rmask, Gmask, Bmask, and Amask 
return the current byte masks for each component of RGBA 
surfaces.  They are provided for future expansion.

$surface->color_key();

	This returns the pixel value which was set using
$surface->set_color_key(flag,pixel);  This is the transparent
color for the image.

$surface->alpha();

	This returns the alpha value of the surface, usually
set by $surface->set_alpha(flag,alpha);  Alpha values are
not applicable to palettized images.

$surface->width();

	This returns the width of the surface.

$surface->height();

	This returns the height of the surface.

$surface->clip_minx ... clip_miny ... clip_maxx ... clip_maxy

	clip_minx, clip_miny, clip_maxx, and clip_maxy return
	the current clipping values for the surface.

$surface->pitch();

	This returns the pitch of the image, aka the width
of a single row of pixels in bytes.  This should be the same
as $surface->width()*$surface->bytes_per_pixel().
It is provided for future expansion.

=head2 Poking Pixels

	The swiss-army-chainsaw of pixel manipulation, the method
$surface->pixel(x,y,color); can be used to read or set the value
of a pixel at the point (x,y).  If no color value is passed, it
will simply read the value at that point.  If a color is passed, it
will set the point to that value and then return the value to which
it  was actually set.  

	For the speed conscious, this function is SLOW.  It is not
designed for line drawing or other large-scale projects.  It is my
intention to provide a generic drawing system in the future,
and additional low level memory tools, but in the mean time, if you
must this cudgel.

So just to reiterate:
		
	$surface->pixel(12,13);	# returns the pixel at (12,13)
	$surface->pixel(12,13,0xffff); # sets that pixel to 0xffff

=head2 Filling areas

	To fill a larger volume than a single pixel the method:

		$surface->fill($rect,color);

will fill a rectangle with the value of color.  With intelligent
use of Rect objects one can draw buttons and the like.  It is also
useful in clearing the screen.

=head2 Locking, Unlocking, and the like...

	When writing to certain surfaces, notably some SDL_HWSURFACE
flaged surfaces, it is necessary to lock the surface before twiddling
its bits.  To tell if you must do so it is wise to call the function:

	$suface->lockp();

If it returns non-zero you should then call:

	$surface->lock();

and after your write call:

	$surface->unlock();

and everything will be well.  Locking and unlocking a surface which
doesn't require locking only wastes time, so if you have time to
spare, you could just do so by default.

=head2 Bliting & Updating

	To copy image data from one surface to another, the SDL
provides a collection of functions.

	$surface->update(rect,...);

will update any number of Rects of the screen, where as:

	$surface->flip();

will update the entire screen.

	$surface->blit($srect,$dest,$drect);

will copy the contents contained by $srect of the surface
$surface into area specified bye $drect of the surface $dest.
Please see the documents for Rect.pm for the creation of
$srect and $drect.

=head2 So may Colors in the world ...

	To set the colors in a palettized image, the method:

		$surface->set_colors($start,...)

is provided.  It takes 1 or more Color objects, and sets the
consecutive palette entries starting at entry $start.
Hence to set the first ten palette entires one would use:

	$my_surface->set_colors(0,$color1,$color2,...$color10);

where $color1 ... $color10 were created with Color->new(r,g,b);
see Color.pm for details.

	Transperancy and alpha levels for an image can also be set
using the methods:

		$surface->set_color_key(flag,pixel);

				and
		$surface->set_alpha(flag,alpha);

where the flags for set_color_key are: SDL_SRCCOLORKEY and SDL_RLEACCEL,
and the flags for set_alpha are: SDL_SRCALPHA and SDL_MULACCEL.

=head2 Clipping

	To set the clipping rectangle for a source surface the
method $surface->clip(top,left,bottom,right); will prevent
accidental bliting of material outside of this rectangle.

=head2 Format Conversion

	Occasionally it will be necessary to manipulate images in
a format other than that used by the display, to manage the conversion
the method: $surface->display_format(); will produce a new surface
in the format used for display.

=head2 Fonts & Printing

	As of version 1.01, SDLpl now supports SFont style
fonts.  Before printing, one must create and use a new font
as specified in SDL::Font.  For example to load a font stored
in Ionic.png one would use:

	$font = new Font "Ionic.png";
	$font->use;
	
Then to print a string to (10,13) on a surface one would use
the print method of the surface:

	$surface->print(10,13,"Hello World");


=head1 AUTHOR

David J. Goehrig

=head1 SEE ALSO

perl(1) SDL::Rect(3) SDL::Font(3).

=cut

