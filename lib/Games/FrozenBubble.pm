package Games::FrozenBubble;

our $VERSION = '2.202'; #Mostly playable version

1;

__END__

=encoding UTF-8

=head1 NAME

Games::FrozenBubble - The classic penguin game ported to CPAN

=head1 DISCLAIMER

This release is under review and is not an official release of Frozen Bubble

=head1 TIPS

During net/lan game choose, there is a chat system. Here are the
available keys and tips:

=over

=item just type and hit enter to send a message

=item page up and page down allow you to view history as in IRC programs

=item arrow up and down allow you to recall previous messages you've sent

=item the TAB key triggers nick completion on listening players

=item in the pre-game chat, the following commands are available:

    /me <action>: sends an action message instead of sending a regular message
    /nick <new_nick>: change your nick
    /server: query the name of the server you're connected to
    /fs: toggle fullscreen
    /list: view list of listening players
    /geolocate: geolocate yourself again
    /autokick <nick> [<text>]: add/remove that nick to autokick list

=item in the in-game chat, the following commands are available:

    /kick <nick> [<text>]: kick a joiner from your game (if you're
                           creator), optionally with an explanatory text

=back

During a game, the following default key shortcuts are
available:

=over

=item TAB: next playlist music (if sound available and when playlist is used)

=item F11: toggle music

=item F12: toggle sound

=item Keypad Minus: lower music/sound volume

=item Keypad Plus: raise music/sound volume

=back

When in multiplayer with 3+ players:

=over

=item F1: send malus to top left player

=item F2: send malus to top right player

=item F3: send malus to bottom left player

=item F4: send malus to bottom right player

=item F10: send malus to all opponents

=back

Notice: you can see who you attack because the F1..F4 little text
next to the player turns white - you can see who is attacking by
the presence of the small pinguins of the opponent on the left of
your igloo.


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

    cpan SDL Games::FrozenBubble


=head1 CONTRIBUTE

Talk to FROGGS or kthakore on #sdl irc.perl.org.

Fork and hack on L<http://github.com/kthakore/frozen-bubble>

see PORT_TODO that came with this distribution

=head1 AUTHOR

Guillaume Cottenceau and others
L<http://www.frozen-bubble.org/>

=head1 PORTERS

FROGGS, daxim, kthakore, kmx
