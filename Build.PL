#!perl
use 5.008;
use strict;
use warnings FATAL => 'all';
use lib 'inc';
use Alien::SDL qw();
use File::Spec;
use Config qw(%Config);
use My::Builder;

my $prefix = Alien::SDL->config('prefix');
my $cflags = Alien::SDL->config('cflags');
$cflags = '-I'
  . File::Spec->catfile( $prefix, 'include' )
  ;
$cflags .= ' -fnested-functions' if $^O =~ /darwin/;
###!!! this looks strange, you perhaps meant "$cflags .= ..."
###!!! I intended Alien::SDL to add -I$prefix/include automatically, please tell me when it does not work (kmx)
my $devnull = File::Spec->devnull();

my @linkers = ( Alien::SDL->config('libs'), '-lSDL_mixer', '-lSDL_Pango' );
push @linkers, '-liconv'
  if $^O =~ /win/i;    ###!!! really only Win needs this? (kmx)

die "Cannot find 'iconv.h'"     unless Alien::SDL->check_header('iconv.h');
die "Cannot find 'math.h'"      unless Alien::SDL->check_header('math.h');
die "Cannot find 'SDL.h'"       unless Alien::SDL->check_header('SDL.h');
die "Cannot find 'SDL_mixer.h'" unless Alien::SDL->check_header('SDL_mixer.h');

My::Builder->new(
    add_to_cleanup =>
      [ 'lib/Games/FrozenBubble/CStuff.c', 'lib/Games/FrozenBubble/CStuff.o', ],
    configure_requires => {
        perl                        => '5.008',
        autodie                     => 0,
        'Alien::SDL'                => '1.1',
        Config                      => 0,
        'ExtUtils::ParseXS'         => '2.16',
        'File::Basename'            => 0,
        'File::Spec::Functions'     => 0,
        'IO::File'                  => 0,
        'Locale::Maketext::Extract' => 0,
        'Module::Build'             => '0.36',    # for share_dir
	'SDL'			    => '2.4'
    },
    build_requires => {
        'IO::File'                  => 0,
        'Locale::Maketext::Extract' => 0,
        autodie                     => 0,
        'IPC::System::Simple'       => 0,
	'SDL'			    => '2.4'
    },
    dist_abstract  => 'Puzzle with Bubbles', # taken from openSUSE rpm spec file
    dynamic_config => 1,
    extra_compiler_flags => [ $cflags ],
    extra_linker_flags   => \@linkers,
    license              => 'gpl2',
    meta_merge           => {
        resources => {
            repository => 'http://github.com/kthakore/frozen-bubble',
            bugtracker => 'http://github.com/kthakore/frozen-bubble/issues',
        },
    },
    module_name => 'Games::FrozenBubble',
    requires    => {
        'perl'                     => '5.008',
        Carp                       => 0,
        'Data::Dumper'             => 0,
        DynaLoader                 => 0,
        Errno                      => 0,
        Fcntl                      => 0,
        'Getopt::Long'             => 0,
        'IO::File'                 => 0,
        'IO::Select'               => 0,
        'IO::Socket'               => 0,
        'Locale::Maketext::Simple' => 0,
        'Math::Trig'               => 0,
        parent                     => 0,
        POSIX                      => 0,
        SDL                        => '1.19.0',
        'Time::HiRes'              => 0,
    },
    share_dir => 'share',
)->create_build_script;

