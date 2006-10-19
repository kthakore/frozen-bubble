use ExtUtils::MakeMaker;
use Config;

# Taken from Makefile.PL from Gtk-Perl
sub ccompile {
	my ($headers, $main, $cflags, $libs) = @_;
	my $fname = "temctest";
	my $r;
	chomp($cflags, $libs);
	open(CTEST, ">$fname.c") || return 0;
	print CTEST <<"EOTEST";
$headers

int main (int argc, char* argv[]) {
$main;
}
EOTEST
	close(CTEST);
	$r = system("$Config{cc} -o $fname $fname.c $cflags $libs 2>/dev/null 1>/dev/null");
	warn("RUNNING: $Config{cc} -o $fname $fname.c $cflags $libs\n") if $ENV{VERBOSE};
	unlink($fname, "$fname.c");
	return $r == 0;
}

sub chomp_ { my @l = map { my $l = $_; chomp $l; $l } @_; wantarray ? @l : $l[0] }
sub die_ { die "\n   **ERROR**: @_\n\n" }


system("sdl-config --cflags 2>/dev/null 1>/dev/null") == 0
  or
  die_ 'SDL development environment seems to be missing ("sdl-config --cflags" reports an error)';


ccompile('#include <SDL.h>
          #include <SDL_mixer.h>',
	 '',
	 chomp_(`sdl-config --cflags`),
	 chomp_(`sdl-config --libs`) . ' -lSDL_mixer')
  or
  die_ 'SDL_mixer is needed (and, version >= 1.2.2)';


ccompile('#include <SDL.h>
          #include <SDL_mixer.h>',
	 'Mix_FadeInMusicPos(NULL, 0, 0, 0);',
	 chomp_(`sdl-config --cflags`),
	 chomp_(`sdl-config --libs`) . ' -lSDL_mixer')
  or
  die_ 'SDL_mixer >= 1.2.2 is needed (impossible to create an executable with function Mix_FadeInMusicPos)';


system("pkg-config SDL_Pango --cflags 2>/dev/null 1>/dev/null") == 0
  or
  die_ 'SDL_Pango development environment seems to be missing ("pkg-config SDL_Pango" reports an error)';


ccompile('#include <SDL_Pango.h>',
	 'SDLPango_Context *context;',
	 chomp_(`sdl-config --cflags`) . ' ' . chomp_(`pkg-config SDL_Pango --cflags`) . ' ',
	 chomp_(`sdl-config --libs`) . ' ' . chomp_(`pkg-config SDL_Pango --libs`) . ' ')
  or
  die_ 'SDL_Pango is needed (impossible to create an executable containing an SDLPango_Context pointer.';


ccompile('#include <SDL_Pango.h>',
	 'SDLPango_Context * context = SDLPango_CreateContext_GivenFontDesc(NULL);',
	 chomp_(`sdl-config --cflags`) . ' ' . chomp_(`pkg-config SDL_Pango --cflags`) . ' ',
	 chomp_(`sdl-config --libs`) . ' ' . chomp_(`pkg-config SDL_Pango --libs`) . ' ')
  or
  die_ 'Frozen-Bubble patches are needed in SDL_Pango (impossible to create an executable calling the function SDLPango_CreateContext_GivenFontDesc)';



WriteMakefile(
    'NAME'         => 'fb_c_stuff',
    'LIBS'         => [ '-lm ' . chomp_(`sdl-config --libs`) . ' -lSDL_mixer ' . chomp_(`pkg-config SDL_Pango --libs`)],
    'VERSION_FROM' => 'fb_c_stuff.pm', # finds VERSION
    'OBJECT'       => 'fb_c_stuff.o',
    'INC'          => chomp_(`sdl-config --cflags`) . ' ' . chomp_(`pkg-config SDL_Pango --cflags`) . ' -I.',
    'OPTIMIZE'     => '-O2 -Wall',
    'MAKEFILE'     => 'Makefile_c',
);
