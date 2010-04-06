package Local::Games::FrozenBubble::Build;
use 5.008;
use strict;
use warnings FATAL => 'all';
use autodie qw(:all);
use File::Basename qw(fileparse);
use File::Spec::Functions qw(catdir catfile rootdir);
use IO::File qw();
use Module::Build '0.36' => qw();
use parent 'Module::Build';

sub ACTION_build {
    my ($self) = @_;
    $self->depends_on('messages');
    $self->SUPER::ACTION_build;
    return;
}

sub ACTION_symbols {
    my ($self) = @_;
    {
        my $out = IO::File->new(catfile(qw(lib Games FrozenBubble Symbols.pm)), 'w');
        $out->print("package Games::FrozenBubble::Symbols;\n\@syms = qw(");
        {
            my $in = IO::File->new(catfile(rootdir, qw(usr include SDL SDL_keysym.h)), 'r');
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
    unlink $pot;
    system "xgettext --keyword=t --language=perl --default-domain=frozen-bubble --from-code=UTF-8 -o $pot bin/frozen-bubble";
    for (glob(catfile(qw(share locale), '*.po'))) {
        system qq(msgmerge -q "$_" "$pot" > "${_}t");
        rename "${_}t", $_;
        my $mo = catfile(@{[fileparse($_, qr/\.po \z/msx)]}[1, 0]) . '.mo';
        system qq(msgfmt "$_" -o "$mo");
    }
    return;
}

1;
