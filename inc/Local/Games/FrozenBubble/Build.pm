package Local::Games::FrozenBubble::Build;
use 5.008;
use strict;
use warnings FATAL => 'all';
use Alien::SDL qw();
use IO::File qw();
use Module::Build '0.36' => qw();
use parent 'Module::Build';

sub ACTION_symbols {
    my ($self) = @_;
    {
        my $out = IO::File->new('lib/Games/FrozenBubble/Symbols.pm', 'w');
        $out->print("package Games::FrozenBubble::Symbols;\n\@syms = qw(");
        {
            my $in = IO::File->new('/usr/include/SDL/SDL_keysym.h', 'r');
            while (defined($_ = $in->getline)) {
                $out->print("$1 ") if /SDLK_(\S+)/;
            }
        }
        $out->print(");\n1;\n");
    }
    return;
}

1;
