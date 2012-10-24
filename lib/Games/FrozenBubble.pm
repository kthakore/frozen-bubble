package Games::FrozenBubble;

our $VERSION = '2.213'; #Cpan version

1;

__END__

=encoding UTF-8

=head1 NAME

Games::FrozenBubble - arcade/reflex game - THIS IS A BETA VERSION

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


=head1 TROUBLESHOOTING

=head2 Having problems running Frozen Bubble?

If you are colourblind, we already have what you're looking for: please use the
C<-cb>commandline parameter, and bubbles will be printed with little geometrical
symbols inside.

=head2 Fix your problems

Most of the problems you can encounter with Frozen-Bubble don't require
contacting us directly, and actually we can't fix most of them.

First, please notice that we have developed this software on the
GNU/Linux platform. There are ports to other operating systems, but we
can't and don't want to support them. If you happen to be using
Frozen-Bubble on FreeBSD, NetBSD, Windows or Mac OS X, please contact
the authors of this "port" if you have trouble
installing/running/whatever. Thank you.

Then, if you use Linux and
installed a package provided by your distribution, you have to contact
the guys of your distribution. We don't know the intrinsics of every
Linux distributions and neither the patches they have applied to
Frozen-Bubble when packaging.

=head2 Troubleshoot most common problems on GNU/Linux

First, please notice that we are not a GNU/Linux vendor, we are not
Debian, Red Hat, Ubuntu, Mandriva or Gentoo. So if you can't install it with
apt-get, emerge, urpmi, yum or whatever, or if you managed to install it but it
won't start or won't run properly, there are much higher chances this is a
problem with your vendor, not with us. Try to think before contacting us: is
your problem really with our software? or with how your vendor
compiled/integrated it with the system?

Now, to ease your life, we provide links to common problems you may encounter.

=over

=item C<...cannot handle TLS data...> message at startup

It seems this is related with buggy or badly installed nvidia drivers. Debian
has a bugreport and a fix (L<http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=223096>)
for this one.

=item C<Can't locate SDL.pm in @INC...> message at startup

Either you didn't install sdlperl, or you installed it at the wrong location.
Check where the file F<SDL.pm> was installed on your system and what is the
C<@INC> search path of perl, there are chances they don't match.

    perl -e 'print join("\n", @INC)

=item crash with a C<SIGILL> when trying to start a new game

You're probably using buggy C<SDL-1.2.6> on an Intel processor; please update to
C<SDL-1.2.7> or more recent.

=item C<Not a HASH reference at /usr/games/frozen-bubble line 310> message at startup

It seems that you're using an incompatible (too recent) version of perl-SDL on
FB1. Either downgrade or apply this patch. L<http://www.frozen-bubble.org/perl-SDL.patch>

=back

If you have more to add, you may want to contact us: C<contact2 @ frozen-bubble.org>,
L<http://github.com/kthakore/frozen-bubble/issues>


=head1 FREQUENTLY ASKED QUESTIONS

=head2 Help! I am unable to download Frozen-Bubble from your website!

Uh, the downloads page (L<http://www.frozen-bubble.org/downloads/>) should be
fairly understandable…

If you're using Windows, or Mac OS X, read the I<Ports> section of the
downloads page (L<http://www.frozen-bubble.org/downloads/#Ports>)!
man, you can do it, I am sure you can, don't quit trying so fast!

=head2 Help! Frozen-Bubble doesn't work!

Easy, go to the troubleshooting page (L<http://www.frozen-bubble.org/troubleshooting/>).
And don't forget we B<don't know> your system
or distribution, help yourself or ask your vendor.

=head2 Hey, why not porting Frozen-Bubble to <my favorite phone or whatever>?

Simple! Because we aren't interested in this. Ask the authors of
other ports, maybe they will be. But no use emailing us about it.
Thanks.

=head2 I'd suggest adding mouse aiming to the game

Yes, but, see, it would not be fair to players using keyboard,
because mouse aiming is analog-based, whereas keys are not. So, no
mouse, sorry.

=head2 My joystick doesn't work!

If you're not using Linux, sorry we don't know and support your system.

If you're using Linux, maybe we can help. When trying to use your
joystick in Frozen-Bubble, if nothing comes up, most probably your
joystick isn't configured correctly (or supported in Linux), use
C<--joysticks-info> commandline parameter to verify that FB
detects your joystick properly: if it does, information about your
joystick(s) will be printed in console on startup, and you should
have no problem using your joystick in FB - just trigger a direction
or a button in the "change keys" dialog; if not, try to load the
proper kernel modules etc - for example, the kernel module
C<joydev> is needed for all joysticks, but it is sometimes not
automatically loaded when plugging in a joystick (even in modern
distros and with USB joysticks) - after loading this kernel module,
retry in FB.

=head2 Special keys

In the 3p/4p/5p network game, you can see F1, F2, F3 and F4 printed
in the game screen - one function key per remote player. These keys
allow you to aim at a particular remote player instead of everyone
at the same time. Indeed, by default, when you create malus bubbles
to be sent to your opponents (by exploding a larger group or when
bubbles were sticked to exploding bubbles), they are distributed
evenly among all of the (living) opponents. If you hit the, say, F2
key before (you can verify you did because F2 is then printed in
white on the game screen), next time you will create malus bubbles, they
will all be sent to the top-right opponent. This feature can allow
you to team up or to aim at the strongest opponent. You can hit F10 to
request back an evenly distribution. Notice that when using at least
version 2.1.0, you can see who's attacking you at any time by looking
at at pinguins left to your igloo (L<http://www.frozen-bubble.org/data/fb2.1-attackmaterialized.png>).

The keys F11 and F12 are also useful (version 2.1.0 minimum): F11 allows one to
toggle the music, and F12 allows one to toggle the sound (music plus sound effects).
Additionally, keypad's minus and plus keys allow to alter sound volume.

=head2 It is a shame, I cannot toggle sound in the game!

Easy, read the L</"Special keys"> FAQ item.

=head2 Why not 2 or more players on the same computer, and still a 3/4/5 player game in network?

Because in 3p/4p/5p game, there is room for only one player with full size
graphics. For the other players, the graphics are smaller
(L<http://www.frozen-bubble.org/downloads/data/fb2-5p.png>), so more than one
local player is not possible.

=head2 What are chain reactions?

When you pop some bubbles, and another bubble was being held up by
the bubbles you popped, that other bubble falls and becomes a malus
bubble.  In chain reaction mode, that other bubble can also rise up and
pop some other bubbles, if you have a pair of bubbles on your screen
that are the same color as it with a free position next to it.  This might, in turn, release more
bubbles, which can also rise up and pop pairs of their own color, in a
big chain reaction. Let's illustrate that:

=over

=item 1. First, you pop some bubbles of the same color, yellow in our example,
which release some extra bubbles of a different color (black and purple).

L<http://www.frozen-bubble.org/data/cr1-0.png>

=item 2. The purple bubble just falls.  The black bubble would fall too, but
this is chain-reaction mode.  So instead of falling, the black bubble sees a
group of other black bubble with a free position next to it, and swoops back up
to be with them.

L<http://www.frozen-bubble.org/data/cr1-1.png>

=item 3. The black bubbles pop, releasing several other bubbles.  The orange
bubble sees a group of other orange bubbles with a free position next to it,
and swoops back up to be with them.

L<http://www.frozen-bubble.org/data/cr1-2.png>

=item 4. The orange bubbles pop, releasing a couple of other bubbles.

L<http://www.frozen-bubble.org/data/cr1-3.png>

=item 5. But there are no more groups for these bubbles, so the chain reaction
is over.

L<http://www.frozen-bubble.org/data/cr1-4.png>

=back

=head2 What's single player targetting?

Easy, read the L</"Special keys"> FAQ item.

=head2 Can I meet the game designers or other players on IRC?

Sure! Please join the IRC channel C<#fb2-en> for English, or C<#fb2-fr> for
French, on irc.freenode.net (L<http://freenode.net/>) - though we're rarely
there. Best is to send a mail.


=head1 CONTRIBUTE

Talk to FROGGS or kthakore on #sdl irc.perl.org.

Fork and hack on L<http://github.com/kthakore/frozen-bubble>
