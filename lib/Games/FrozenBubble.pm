package Games::FrozenBubble;

our $VERSION = '0.001_1';

1;
=pod

=head1 NAME

Games::FrozenBubble - The classic penguin game ported to CPAN

=head1 INSTALL

=head2 Pango headers

Ensure libpango1-dev and pkg-config are installed on your system.

 sudo apt-get install libpango1-dev

Strawberry perl windows users need not worry!

=head2 Alien::SDL

=head3 Unix/Linux/Macs

You may need the following packages

 libpng-dev libvorbis-dev x11proto-xext-dev libxft-dev 

Then B<CRITICAL> select pango support!

 cpan Alien::SDL


=head2 SDL and Games::FrozenBubble

 cpan SDL, Games::FrozenBubble


=head1 CONTRIBUTE

Talk to FROGGS or kthakore on #sdl irc.perl.org.

Fork and hack on http://github.com/kthakore/frozen-bubble

see PORT_TODO that came with this distribution

=head1 AUTHOR
Guillaume Cottenceau and others
L<http://www.frozen-bubble.org/>

=head1 PORTERS

FROGGS, daxim, kthakore, kmx

=cut
