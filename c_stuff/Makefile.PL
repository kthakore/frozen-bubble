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
  die_ 'SDL development environment seems to be missing (sdl-config command reports an error)';


ccompile('#include <SDL/SDL.h>
          #include <SDL/SDL_mixer.h>',
	 '',
	 `sdl-config --cflags`,
	 chomp_(`sdl-config --libs`) . ' -lSDL_mixer')
  or
  die_ 'SDL_mixer is needed (and, by the way, version >= 1.2.2 will be needed)';


ccompile('#include <SDL/SDL.h>
          #include <SDL/SDL_mixer.h>',
	 'Mix_FadeInMusicPos(NULL, 0, 0, 0);',
	 `sdl-config --cflags`,
	 chomp_(`sdl-config --libs`) . ' -lSDL_mixer')
  or
  die_ 'SDL_mixer >= 1.2.2 is needed (function Mix_FadeInMusicPos is missing)';


WriteMakefile(
    'NAME'         => 'fb_c_stuff',
    'LIBS'         => [ chomp_(`sdl-config --libs`) . ' -lSDL_mixer'],
    'VERSION_FROM' => 'fb_c_stuff.pm', # finds VERSION
    'OBJECT'       => 'fb_c_stuff.o',
    'INC'          => chomp_(`sdl-config --cflags`) . ' -I.',
    'OPTIMIZE'     => '-O2 -Wall',
    'MAKEFILE'     => 'Makefile_c',
);
