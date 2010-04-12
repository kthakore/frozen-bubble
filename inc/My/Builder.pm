package My::Builder;
use 5.008;
use strict;
use warnings FATAL => 'all';
use autodie qw(:all);
use File::Basename qw(fileparse);
use File::Spec::Functions qw(catdir catfile rootdir);
use IO::File qw();
use Module::Build '0.36' => qw();
use parent 'Module::Build';
use Locale::Maketext::Extract;

sub ACTION_run {
    my ($self) = @_;
    $self->depends_on('code');
    my $bd = $self->{properties}->{base_dir};

    # prepare INC
    local @INC = @INC;
    unshift @INC, (File::Spec->catdir($bd, $self->blib, 'lib'), File::Spec->catdir($bd, $self->blib, 'arch'));

    if (scalar @{$self->args->{ARGV}}) {
      # scenario: ./Build run bin/scriptname param1 param2
      $self->do_system($^X, @{$self->args->{ARGV}});
    }
    else {    
      # scenario: ./Build run
      my ($first_script) = ( glob('bin/*'), glob('script/*')); # take the first script in bin or script subdir
      print STDERR "No params given to run action - gonna start: '$first_script'\n";
      $self->do_system($^X, $first_script);
    }
}

sub ACTION_build {
    my ($self) = @_;
    #$self->depends_on('messages'); #temporarily disabled by kmx, the new ACTION_messages() needs more testing
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

1;
