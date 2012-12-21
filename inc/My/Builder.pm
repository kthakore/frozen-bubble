package My::Builder;
use 5.008;
use strict;
use warnings FATAL => 'all';
use ExtUtils::CBuilder qw();
use File::Basename qw(fileparse);
use File::Copy qw(move);
use File::Slurp qw(read_file write_file);
use File::Spec::Functions qw(catdir catfile rootdir);
use IO::File qw();
use Module::Build '0.36' => qw();
use autodie qw(:all move read_file write_file);
use parent 'Module::Build';
use Locale::Maketext::Extract;

use lib 'lib';
use Games::FrozenBubble;

sub ACTION_run {
    my ($self) = @_;
    $self->depends_on('code');
    $self->depends_on('installdeps');
    my $bd = $self->{properties}->{base_dir};

    # prepare INC
    local @INC = @INC;
    local @ARGV = @{$self->args->{ARGV}};
    my $script = shift @ARGV;
    unshift @INC, (File::Spec->catdir($bd, $self->blib, 'lib'), File::Spec->catdir($bd, $self->blib, 'arch'));

    if ($script) {
      # scenario: ./Build run bin/scriptname param1 param2
      do($script);
    }
    else {
      # scenario: ./Build run
      my ($first_script) = ( glob('bin/*'), glob('script/*')); # take the first script in bin or script subdir
      print STDERR "No params given to run action - gonna start: '$first_script'\n";
      do($first_script);
    }
}

sub ACTION_build {
    my ($self) = @_;
    #$self->depends_on('messages'); #temporarily disabled by kmx, the new ACTION_messages() needs more testing
    $self->depends_on('server');
    $self->SUPER::ACTION_build;
    return;
}

sub ACTION_symbols {
    my ($self) = @_;
    {
        my $out = IO::File->new(catfile(qw(lib Games FrozenBubble Symbols.pm)), 'w');
        $out->print("package Games::FrozenBubble::Symbols;\n\@syms = qw(");
        {
            my $in = IO::File->new(catfile(Alien::SDL->config('prefix'), qw(include SDL SDL_keysym.h)), 'r');
            while (defined($_ = $in->getline)) {
                $out->print("$1 ") if /SDLK_(\S+)/;
            }
        }
        $out->print(");\n1;\n");
    }
    return;
}

sub ACTION_messages {
    my ($self) = @_;
    my $pot = catfile(qw(share locale frozen-bubble.pot));
    my $script = catfile(qw(bin frozen-bubble));

    return if (-e $pot) && ((-M $pot) < (-M $script)); # frozen-bubble.pot is newer than bin/frozen-bubble

    unlink $pot if -f $pot;
    print "Gonna extract all translation strings\n";
    my $ex1 = Locale::Maketext::Extract->new(verbose => 1, warnings  => 0);
    $ex1->extract_file($script);
    $ex1->compile(1);
    $ex1->write_po($pot);

    for my $lang (glob(catfile(qw(share locale), '*.po'))) {
        print "Processing $lang\n";
        my $ex2 = Locale::Maketext::Extract->new();
        $ex2->read_po('share/locale/frozen-bubble.pot');
        $ex2->read_po($lang);
        $ex2->compile(1);
        $ex2->write_po($lang);
    }

    return;
}

sub ACTION_server {
    if($^O =~ /(w|W)in/ or $^O =~ /darwin/)
    {
        print STDERR "###Cannot build fb-server on windows or darwin need glib\n";
        return;
    }
    my ($self) = @_;
    my $server_directory = 'server';
    my $otarget          = 'fb-server';
	return if (-e 'bin/'.$otarget );
    # CBuilder doesn't take shell quoting into consideration,
    # so the -DVERSION macro does not work like in the former Makefile.
    # Instead, I'll just preprocess the two files with perl.
    {
        my $version = $Games::FrozenBubble::VERSION;
        # perl -pie again has problems with shell quoting for the -e'' part.
        for my $cfile (
            map {catfile($server_directory, $_)} qw(fb-server.c_tmp net.c_tmp)
        ) {
            my $csource = read_file($cfile);
            $csource =~ s{" VERSION "}{$version};
            $cfile =~ s/_tmp//;
            write_file($cfile, $csource);
        }
    }

    {
        my $cbuilder = ExtUtils::CBuilder->new;
        my @ofiles;
        for my $cfile (qw(fb-server.c log.c tools.c game.c net.c)) {
            push @ofiles, $cbuilder->compile(
                source               => catfile($server_directory, $cfile),
                extra_compiler_flags => [
                    qw(-g -Wall -Werror -pipe), # verbatim from Makefile
                    '-I' . $server_directory, # does not seem to be necessary
                    $cbuilder->split_like_shell(`pkg-config glib-2.0 --cflags`),
                    $cbuilder->split_like_shell(`pkg-config glib-2.0 --libs`),
                ],
            );
        }
        $cbuilder->link_executable(
            objects            => \@ofiles,
            exe_file           => catfile($server_directory, $otarget),
            extra_linker_flags => [
                $cbuilder->split_like_shell(`pkg-config glib-2.0 --libs`),
            ],
        );
    }

    move(catfile($server_directory, $otarget), 'bin');
    return;
}

1;
