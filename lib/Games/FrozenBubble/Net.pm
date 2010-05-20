package Games::FrozenBubble::Net;

use strict;
use IO::Socket;
use Fcntl;
use Errno qw(:POSIX);
use POSIX qw(uname);

use Time::HiRes qw(gettimeofday sleep);
use Games::FrozenBubble::Stuff;

our $proto_major = '1';  #- this is our protocol level
our $proto_minor = '2';  #-

my $udp_server_port = 1511;  #- a.k.a 0xF 0xB thx misc
$SIG{PIPE} = 'IGNORE';  #- stupid send/write low-level API sending SIGPIPE when server closes connection, and stupid Perl
                        #- not allowing flags in syswrite

#- UDP discover LAN servers with broadcast

sub discover_lan_servers {
    my $socket = IO::Socket::INET->new(Proto => 'udp');
    if (!$socket) {
        print STDERR "Cannot create socket: $!\n";
        return { failure => 'Cannot send broadcast.' };
    }

    if (!$socket->setsockopt(SOL_SOCKET, SO_BROADCAST, 1)) {
        print STDERR "Cannot setsockopt: $!\n";
        return { failure => 'Cannot send broadcast.' };
    }

    my $destpaddr = sockaddr_in($udp_server_port, INADDR_BROADCAST());
    if (!$socket->send("FB/$proto_major\.$proto_minor SERVER PROBE", 0, $destpaddr)) {
        print STDERR "Cannot send broadcast: $!\n";
        return { failure => 'Network is down/no network?' };
    }

    my $inmask = '';
    vec($inmask, fileno($socket), 1) = 1;
    my @servers;
    while (select(my $outmask = $inmask, undef, undef, 2)) {
        my ($srcpaddr, $rcvmsg);
        if (!defined($srcpaddr = $socket->recv($rcvmsg, 128, 0))) {
            print STDERR "Cannot receive from socket: $!\n";
            return { failure => 'Cannot read answer from broadcast.' };
        }
        my ($port, $ipaddr) = sockaddr_in($srcpaddr);
        $ipaddr = inet_ntoa($ipaddr);
        if ($rcvmsg =~ m|^FB/$proto_major\.\d SERVER HERE AT PORT (\d+)|) {
            push @servers, { host => $ipaddr, port => $1 };
        } else {
            print STDERR "\nReceive weird/incompatible answer to UDP broadcast looking for LAN servers from $ipaddr:$port:\n\t$rcvmsg\n";
        }
    }

    return { servers => \@servers };
}



#- before game operations

our $sock;
our $ping = 200;

our $masterserver;  #- for forcing the masterserver on commandline

sub send_($) {
    my ($msg) = @_;
    if (defined($sock)) {
        my $bytes = syswrite($sock, "FB/$proto_major.$proto_minor $msg\n");
        !$bytes and disconnect();
    }
}

sub disconnect() {
    if (defined($sock)) {
        close $sock;
        $sock = undef;
    }
}

sub isconnected() {
    return defined($sock);
}

my $buffered_line;
sub readline_() {
    if (!defined($sock)) {
        return undef;
    }

    my $results = $buffered_line;
    $buffered_line = undef;
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm 5;  #- in seconds
        while ($results !~ /\n/) {
            my $buf;

                        if($^O eq 'MSWin32' && !defined IO::Select->new($sock)->can_read(0.00001)) {
                                sleep($ping/1000/3);
                                next;
                        }

                        my $bytes = sysread($sock, $buf, 1);
            if (!defined($bytes)) {
                if (0 + $! == EAGAIN) {
                    sleep($ping/1000/3);
                } elsif ($! == ECONNRESET) {
                    disconnect();
                    return $results;
                } else {
                    printf STDERR "Oops, system error: " .(0+$!). " at line %d, %s\n", __LINE__, $^E;
                    return undef;
                }
            } elsif ($bytes == 0) {
                disconnect();
                return $results;
            } else {
                $results .= $buf;
            }
        }
        alarm 0;
        ($results, $buffered_line) = $results =~ /([^\n]+\n)(.*)?/s;
    };
    if ($@) {
        print STDERR "Sorry, your computer or the network is too slow, giving up.\n";
        disconnect();
        die 'quit';
    } else {
        return $results;
    }
}

sub readline_ifdata() {
    $buffered_line and return readline_();

    if (!defined($sock)) {
        return undef;
    }

        return undef if $^O eq 'MSWin32' && !defined IO::Select->new($sock)->can_read(0.00001);

    my $buf;
        my $bytes = sysread($sock, $buf, 1);
    if (!defined($bytes)) {
        if (0 + $! == EAGAIN) { # nothing there to read
            return undef;
        } elsif (0 + $! == ECONNRESET) {
            disconnect();
            return undef;
        } else {
            printf STDERR "Oops, system error: " .(0+$!). " at line %d, %s\n", __LINE__, $^E;
            return undef;
        }
    } elsif ($bytes == 0) {
        disconnect();
        return;
    } else {
        if ($buf eq "\n") {
            return $buf;
        } else {
            return $buf . readline_();
        }
    }
}


sub decode_msg($) {
    my ($msg) = @_;
    my ($command, $message) = $msg =~ m|^FB/\d+\.\d+ (\w+): (.*)|;
    return ($command, $message);
}

sub send_and_receive($;$) {
    my ($command, $rest) = @_;
    send_("$command $rest");
    my $answer = undef;
    my $to_buffer;
    while (!defined($answer)) {
        my $msg = readline_();
        !defined($msg) and $answer = '';
        my ($rcv_command, $rcv_message) = Games::FrozenBubble::Net::decode_msg($msg);
        if ($rcv_command eq $command) {
            $answer = $rcv_message;
        } else {
            #- this is not the answer we're waiting. keep that.
            $to_buffer .= $msg;
        }
    }
    $buffered_line .= $to_buffer;
    return $answer;
}

sub list() {
    my $msg = send_and_receive('LIST');
    if ($msg =~ /(\S*) (\S*) free:(\d+) games:(\d+) playing:(\d+) at:(\S*)/) {
        my $freenicks = $1;
        my $freegames = $2;
        my $free = $3;
        my $games = $4;
        my $playing = $5;
        my $playing_geolocs = $6;
        my @games;
        while ($freegames =~ /\[([^\]]+)\]/g) {
            push @games, [ split /,/, $1 ];
        }
        return ($free, $games, $freenicks, $playing, $playing_geolocs, @games);
    } else {
        return;
    }
}

sub create($) {
    my ($nick) = @_;
    send_("CREATE $nick");
    my $msg = readline_();
    if ($msg =~ /CREATE: OK/) {
        return 1;
    } else {
        $msg and print STDERR "Could not create game. Server said:\n\t$msg\n";
        return 0;
    }
}

sub join($$) {
    my ($leader, $nick) = @_;
    send_("JOIN $leader $nick");
    my $msg = readline_();
    if ($msg =~ /JOIN: OK/) {
        return 1;
    } else {
        $msg and print STDERR "Could not join game. Server said:\n\t$msg\n";
        return 0;
    }
}

my $buffered_buf;  #- the in game buffer. not to be read before game.
my @messages;      #- the in game messages. same.

my ($current_name, $current_host, $current_port);
sub connect {
    my ($host, $port) = @_;

    my $perform_ping = 1;
    my $tried_name;
    if (!defined $host) {
        #- reconnect
        $host = $current_host;
        $port = $current_port;
        $tried_name = $current_name;
        $perform_ping = 0;
    } elsif (!defined $port) {
        #- first param was a hash
        my $params = $host;
        $host = $params->{host};
        $port = $params->{port};
        $ping = $params->{ping};
        $perform_ping = 0;
        $tried_name = $params->{name};
    }

    $current_host = $current_port = undef;

    $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp', Timeout => 5);
    if (!$sock) {
        #print STDERR "Couldn't connect to $host:$port: $@\n";
        return { failure => 'Server is down' };
    }
    $sock->autoflush;

    $buffered_line = undef;
    $buffered_buf = undef;
    @messages = ();
    my $msg;
    eval { $msg = readline_(); };
    $@ and return { failure => 'Server or computer too slow' };
    my ($remote_major, $remote_minor, $isready) = $msg =~ m|^FB/(\d+).(\d+) (.*)|;
    my ($servername, $serverlanguage);
    if ($isready =~ /^PUSH: SERVER_READY (.*) (.*)/) {
        $servername = $1;
        $serverlanguage = $2;
    } else {
        disconnect();
        if ($isready eq 'PUSH: SERVER_IS_FULL') {
            print STDERR "Dropping $host:$port: server is full\n";
            return { failure => 'Server is full' };
        } elsif ($isready eq 'PUSH: SERVER_IS_OVERLOADED') {
            print STDERR "Dropping $host:$port: server is overloaded\n";
            return { failure => 'Server overloaded' };
        } elsif ($remote_minor < $proto_minor) {
            print STDERR "Dropping $host:$port: deprecated protocol $remote_major.$remote_minor\n";
            return { failure => 'Server deprecated' };
        } else {
            print STDERR "Dropping $host:$port: not a Frozen-Bubble server\n";
            return { failure => 'Not an FB server' };
        }
    }

    if ($perform_ping) {
        $ping = 200;

        my @pings;
        foreach (1..4) {
          reping:
            my $t0 = gettimeofday;
            send_('PING');
            eval { $msg = readline_(); };
            $@ and return { failure => 'Server or computer too slow' };
            my $t1 = gettimeofday;
            if ($msg =~ /INCOMPATIBLE_PROTOCOL/) {
                disconnect();
                print STDERR "Dropping $host:$port: imcompatible Frozen-Bubble server\n";
                return { failure => 'Incompatible server' };
            } elsif ($msg =~ /PUSH/) {
                #- drop PUSHes, server might be sending TALK messages which we don't care at that point
                goto reping;
            } elsif ($msg !~ /PONG/) {
                print STDERR "$host:$port answer to PING was not recognized. Server said:\n\t$msg\n";
                disconnect();
                return { failure => 'Incompatible server' };
            }
            push @pings, ($t1-$t0) * 1000;
            if ($_ == 2 && $pings[0] > 250 && $pings[1] > 250) {
                #- don't wait too much on slower servers
                last;
            }
        }

        if (@pings > 2) {  #- keep 2 worst
            @pings = difference2(\@pings, [ min(@pings) ]) while @pings > 2;
        }
        $ping = sprintf("%.1f", sum(@pings)/@pings);
    }

    #BEWARE non-blocking sockets work on Win32 only with IO-1.24 or higher
        # http://www.codeguru.com/forum/showthread.php?t=468281
        # http://perldoc.perl.org/IO/Select.html
        $sock->blocking(0);
        return { failure => 'Cannot set unblocking '.(0+$!) } if 0+$!;

    $current_host = $host;
    $current_port = $port;
    $current_name = $tried_name;
    return { ping => $ping, name => $servername, language => $serverlanguage };
}

sub current_server_name {
    return $current_name;
}
sub current_server_hostport {
    return "$current_host:$current_port";
}

sub reconnect() {
    if (defined($current_host) && defined($current_port)) {
        disconnect();
        my $ret = Games::FrozenBubble::Net::connect();
        return exists $ret->{ping};
    }
}

sub http_download($) {
    my ($url) = @_;

    my ($host, $port, $path) = $url =~ m,^http://([^/:]+)(?::(\d+))?(/\S*)?$,;
    $port ||= 80;

    my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp', Timeout => 5);
    if (!$sock) {
        print STDERR "Couldn't connect to $host:$port:\n\t$@\n";
        return;
    }
    $sock->autoflush;

    my ($sysname, undef, undef, undef, $machine) = uname();
    my $bytes = syswrite($sock, join("\r\n",
                                     "GET $path HTTP/1.0",
                                     "Host: $host:$port",
                                     "User-Agent: Frozen-Bubble client version $Games::FrozenBubble::VERSION (protocol version $proto_major.$proto_minor) on $sysname/$machine",
                                     "", ""));
    if (!$bytes) {
        close $sock;
        return;
    }

    #- skip until empty line
    my ($now, $last, $buf, $tmp) = 0;
    my $read = sub {
        my $got = sysread($sock, $buf, 1);
        if ($got == 0) {
            die 'eof';
        } elsif (!defined($got)) {
            die "sys error: $!";
        } else {
            $tmp .= $buf;
        };
    };
    eval {
        do {
            $last = $now;
            &$read; &$read if $buf =~ /\015/;
            $now = $buf =~ /\012/;
        } until $now && $last;

        if ($tmp =~ m|^HTTP/\d\.\d (.*\b(\d+)\b.*)| && $2 == 200) {
            $tmp = '';
            while (1) { &$read }
        } else {
            die "HTTP error fetching http://$host:$port$path: $1\n";
        }
    };

    if ($@ =~ /^eof/) {
        close $sock;
        return $tmp;
    } elsif ($@ =~ /^alarm/) {
        die;
    } else {
        print STDERR "http_download: $@\n";
        close $sock;
        return;
    }
}

sub get_server_list() {
    my @masters = qw(http://www.frozen-bubble.org/servers/serverlist
                     http://frozen-bubble.sourceforge.net/serverlist
                     http://webother.linuxfr.org/serverlist
                     http://fb.mandrivalinux.org/serverlist);
    foreach ($masterserver || map { "$_-$proto_major" } @masters) {
        my $serverlist = http_download($_);
        defined $serverlist and return $serverlist;
    }
    return;
}

our $myid;
sub setmyid($) {
    $myid = $_[0];
}

sub sleep_reasonably {
    sleep($ping/1000/3);
}


#- in game operations

#- data is command:parameters
#- supported commands:
#-   ! (synchro)      [this one is special, server propagates also to emitter]
#-   a (angle)
#-   A (attack)
#-   b (bubble)
#-   f (fire)
#-   F (finished)
#-   g (generatemalus)
#-   l (leave)
#-   m (malus)
#-   M (malusstick)
#-   n (newgame)
#-   N (nextbubble)
#-   r (rotate)
#-   p (ping)         [this one is special, server doesn't propagate back]
#-   s (stick)
#-   t (talk)
#-   T (tobelaunchedbubble)
sub gsend($) {
    my ($msg) = @_;
    if (defined($sock)) {
        my $bytes = syswrite($sock, $myid . "$msg\n");
        !$bytes and disconnect();
    }
}

sub grecv() {
    my @msg = @messages;
    @messages = ();

    if (!defined($sock)) {
        return @msg;
    }

        return @msg if $^O eq 'MSWin32' && !defined IO::Select->new($sock)->can_read(0.00001);

    my $buf;
    my $bytes = sysread($sock, $buf, 1024);
    if (!defined($bytes)) {
        if ($! == EAGAIN) {
            return @msg;
        } elsif ($! == ECONNRESET) {
            disconnect();
            return;
                } else {
                        printf STDERR "Oops, system error: " .(0+$!). " at line %d, %s\n", __LINE__, $^E;
                        return undef;
                }
    } elsif ($bytes == 0) {
        disconnect();
        return;
    }
#    print "received $bytes bytes, adding to buffered ", length($buffered_buf), "\n";
    $buf = $buffered_buf . $buf;
    $buffered_buf = undef;
#    my @ascii = unpack("C*", $buf);
#    print "bytes in buf: @ascii\n";

    while ($buf) {
        #- first byte of a "frame" is the id of the sender
        my $id = substr($buf, 0, 1);
        $buf = substr($buf, 1);
        #- match data of a frame (NUL terminated)
        if (my ($msg, $rest) = $buf =~ /([^\n]+)\n(.*)?/s) {  #-?
            $buf = $rest;
            push @msg, { id => $id, msg => $msg };
#            print "\trecv-msg:", ord($id), ":$msg\n";
        } else {
            #- no match means that we received a partial packet
 #           print "*** partial receive! for <$buf>, buffering (theoretically harmless)\n";
            $buffered_buf = $id . $buf;
            $buf = undef;
        }
    }

    return @msg;
}

sub gdelay_messages(@) {
    push @messages, @_;
}

sub grecv_get1msg_ifdata() {
    my ($msg, @rest) = grecv();
    push @messages, @rest;
    return $msg;
}

sub grecv_get1msg {
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm 10;
        while (!@messages) {
            sleep($ping/1000/3);
            @messages = grecv();
        }
        alarm 0;
    };
    if ($@) {
        print STDERR "Sorry, we are not receiving the expected message. If the other ends are legal Frozen-Bubble\n" .
                     "clients, it means your computer or the network is too slow. Giving up.\n";
        disconnect();
        die 'quit';
    } else {
        return shift @messages;
    }
}

1;

__END__

=encoding UTF-8

=head1 Frozen-Bubble

Copyright © 2004 Guillaume Cottenceau

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License version 2, as
published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
