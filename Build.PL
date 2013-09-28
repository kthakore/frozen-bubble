#!perl
use 5.008;
use strict;
use warnings FATAL => 'all';
use lib 'inc';
use Alien::SDL qw();
use SDL::Config;
use File::Spec;
use Config qw(%Config);
use My::Builder;
use ExtUtils::CBuilder qw();

use lib 'lib';
use Games::FrozenBubble;

my $prefix = Alien::SDL->config('prefix');
my $cflags = '-I'
  . File::Spec->catfile( $prefix, 'include' )
  ;
$cflags .= ' -fnested-functions' if $^O =~ /darwin/;
###!!! this looks strange, you perhaps meant "$cflags .= ..."
###!!! I intended Alien::SDL to add -I$prefix/include automatically, please tell me when it does not work (kmx)
my $devnull = File::Spec->devnull();
my @cflags =  ExtUtils::CBuilder->new->split_like_shell( $cflags );
my @linkers = ( ExtUtils::CBuilder->new->split_like_shell( Alien::SDL->config('libs', '-lSDL_mixer', '-lSDL_Pango') ) );
push @linkers, '-liconv'
  if $^O =~ /win/i;    ###!!! really only Win needs this? ; BEWARE this matches also 'darwin', 'cygwin'!!!!

  my $CPAN_test_NA;

$CPAN_test_NA =  "Cannot find 'iconv.h'"     unless Alien::SDL->check_header('iconv.h');
$CPAN_test_NA =  "Cannot find 'math.h'"      unless Alien::SDL->check_header('math.h');
$CPAN_test_NA =  "Cannot find 'SDL.h'"       unless Alien::SDL->check_header('SDL.h');
$CPAN_test_NA =  "Cannot find 'SDL_mixer.h'" unless Alien::SDL->check_header('SDL_mixer.h');

$CPAN_test_NA =  "SDL_perl needs to be built with SDL_image (png) support" unless SDL::Config->has('SDL_image');
$CPAN_test_NA =  "SDL_perl needs to be built with SDL_mixer (ogg) support" unless SDL::Config->has('SDL_mixer');
$CPAN_test_NA =  "SDL_perl needs to be built with SDL_Pango support" unless SDL::Config->has('SDL_Pango');
$CPAN_test_NA =  "SDL_perl needs to be built with SDL_ttf   support" unless SDL::Config->has('SDL_ttf');

if( $CPAN_test_NA ){ warn $CPAN_test_NA; exit(0) }


My::Builder->new(
    add_to_cleanup => [
        'lib/Games/FrozenBubble/CStuff.c',
        'lib/Games/FrozenBubble/CStuff.o',
        'server/fb-server.c',  #preprocessed by perl from $cfile_tmp
        'server/net.c',
        'server/fb-server.o',
        'server/game.o',
        'server/log.o',
        'server/net.o',
        'server/tools.o',
        'bin/fb-server',
    ],
    dist_abstract  => 'Puzzle with Bubbles', # taken from openSUSE rpm spec file
    dynamic_config => 1,
    extra_compiler_flags => \@cflags ,
    extra_linker_flags   => \@linkers,
    license              => 'gpl2',
    meta_merge           => {
        resources => {
            repository => 'http://github.com/kthakore/frozen-bubble',
            bugtracker => 'https://github.com/kthakore/frozen-bubble/issues',
        },
    },
    module_name => 'Games::FrozenBubble',
    dist_version => $Games::FrozenBubble::VERSION,
    share_dir => 'share',
    no_index  => { directory => [ 'server' ] }, # tell PAUSE to not index 'server' subdirectory
    configure_requires => { #need to have for running: perl Buil.PL
        'perl'                      => '5.008',
        'Errno'                     => 0,
        'Data::Dumper'              => 0,
        'Getopt::Long'              => 0,
        'IO::Socket'                => '1.24', # part od IO distribution
        'Math::Trig'                => 0,
        'parent'                    => 0,
        'Alien::SDL'                => '1.412',
        'SDL'                       => '2.511',
        'ExtUtils::CBuilder'        => 0,
        'Time::HiRes'               => 0,
        'Locale::Maketext::Simple'  => 0,
        'Module::Build'             => '0.36', # for share_dir
        'Locale::Maketext::Extract' => 0,
        'autodie'                   => 0,
        'ExtUtils::ParseXS'         => '2.16',
        'File::Basename'            => 0,
        'File::Spec::Functions'     => 0,
        'ExtUtils::CBuilder'        => 0,
        'File::Copy'                => 0,
        'File::Slurp'               => 0,
        'IPC::System::Simple'       => 0,
    },
    build_requires => { #need to have for running: ./Build (install|test), basically should be a superset of 'requires' as we run testsuite
        'perl'                      => '5.008',
        'Errno'                     => 0,
        'Data::Dumper'              => 0,
        'Getopt::Long'              => 0,
        'IO::Socket'                => '1.24', # part od IO distribution
        'Math::Trig'                => 0,
        'parent'                    => 0,
        'Alien::SDL'                => '1.413',
        'SDL'                       => '2.511',
        'Time::HiRes'               => 0,
        'Locale::Maketext::Simple'  => 0,
        'Module::Build'             => '0.36', # for share_dir
        'Locale::Maketext::Extract' => 0,
        'autodie'                   => 0,
        'ExtUtils::ParseXS'         => '2.16',
        'File::Basename'            => 0,
        'File::Spec::Functions'     => 0,
        'ExtUtils::CBuilder'        => 0,
        'File::Copy'                => 0,
        'File::Slurp'               => 0,
        'Compress::Bzip2'           => 0,
        'IPC::System::Simple'       => 0,

    },
    requires    => {
        'perl'                      => '5.008',
        'POSIX'                     => 0,
        'Carp'                      => 0,
        'DynaLoader'                => 0,
        'Fcntl'                     => 0,
        # now non-core modules
        'Errno'                     => 0,
        'Data::Dumper'              => 0,
        'Getopt::Long'              => 0,
        'IO::Socket'                => '1.24', # part of IO distribution
        'Math::Trig'                => 0,
        'parent'                    => 0,
        'Alien::SDL'                => '1.413',
        'SDL'                       => '2.511',
        'Time::HiRes'               => 0,
        'Locale::Maketext::Simple'  => 0,
	'Locale::Maketext::Extract'  => 0,
        'File::Glob'                => 0,
	'File::Which'		    => 0,
        'Compress::Bzip2'           => 0,
        'IPC::System::Simple'       => 0,

    },
)->create_build_script;
