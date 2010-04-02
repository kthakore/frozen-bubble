#!perl
use 5.008;
use strict;
use warnings FATAL => 'all';
use lib 'inc';
use Alien::SDL qw();
use File::Spec ;
use Config qw(%Config);
use Devel::CheckLib qw(check_lib_or_exit);
use My::Builder;

sub chomped {
    my $value = $_[0];
    chomp $value;
    return $value;
}

my $prefix = Alien::SDL->config('prefix'); 
my $cflags = Alien::SDL->config('cflags');
   $cflags = '-I'.File::Spec->catfile($prefix, 'include');
my $devnull = File::Spec->devnull();
my $iconv;
$iconv = '-liconv' if $^O =~ /win/i;

my @linkers = (Alien::SDL->config('libs'), '-lSDL_mixer', '-lSDL_Pango');

push @linkers, $iconv if $iconv;


check_lib_or_exit(header => 'iconv.h');
check_lib_or_exit(header => 'math.h');
die "Cannot find 'SDL.h'" unless Alien::SDL->check_header('SDL.h');
die "Cannot find 'SDL_mixer.h'" unless Alien::SDL->check_header('SDL_mixer.h');

My::Builder->new(
    add_to_cleanup     => [
        'lib/Games/FrozenBubble/CStuff.c',
        'lib/Games/FrozenBubble/CStuff.o',
    ],
    configure_requires => {
        perl                => '5.008',
        'Alien::SDL'        => '1.1',
        Config              => 0,
        'Devel::CheckLib'   => '0.6',
        'ExtUtils::ParseXS' => '2.16',
        'IO::File'          => 0,
        'Module::Build'     => '0.36',    # for share_dir
    },
    build_requires       => {
    },
    dist_abstract        => 'Puzzle with Bubbles',    # taken from openSUSE rpm spec file
    dynamic_config       => 1,
    extra_compiler_flags => [
    	$cflags
    ],
    extra_linker_flags => \@linkers,
    license    => 'gpl2',
    meta_merge => {
        resources => {
            repository => 'http://github.com/kthakore/frozen-bubble',
            bugtracker => 'http://github.com/kthakore/frozen-bubble/issues',
        },
    },
    module_name => 'Games::FrozenBubble',
    requires    => {
        'perl'            => '5.008',
        Carp              => 0,
        'Data::Dumper'    => 0,
        DynaLoader        => 0,
        Errno             => 0,
        Fcntl             => 0,
        'Getopt::Long'    => 0,
        'IO::File'        => 0,
        'IO::Select'      => 0,
        'IO::Socket'      => 0,
        'Locale::Maketext::Simple' => 0,
        'Math::Trig'      => 0,
        parent            => 0,
        POSIX             => 0,
        SDL               => '1.19.0',
        'Time::HiRes'     => 0,
    },
    share_dir => 'share',
)->create_build_script;
