#*****************************************************************************
#
#                          Frozen-Bubble
#
# Copyright (c) 2004 Guillaume Cottenceau
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
#
#
#******************************************************************************

package fb_net;

use strict;
use IO::Socket;
use Fcntl;
use Errno qw(:POSIX);
use POSIX qw(uname);
use Time::HiRes qw(gettimeofday sleep);
use fb_stuff;

our $proto_major = '1';
our $proto_minor = '0';
our $timeout = 5;   #- in seconds

my $udp_server_port = 1511;  #- a.k.a 0xF 0xB thx misc

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
        if ($rcvmsg =~ m|^FB/$proto_major\.$proto_minor SERVER HERE AT PORT (\d+)|) {
            push @servers, { host => inet_ntoa($ipaddr), port => $1 };
        } else {
            print STDERR "\nReceive weird/incompatible answer to UDP broadcast looking for LAN servers from $ipaddr:$port:\t$rcvmsg\n";
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
        alarm $timeout;
        while ($results !~ /\n/) {
            my $buf;
            my $bytes = sysread($sock, $buf, 1);
            if (!defined($bytes)) {
                if ($! == EAGAIN) {
                    sleep($ping/1000/3);
                } elsif ($! == ECONNRESET) {
                    disconnect();
                    return $results;
                } else {
                    print STDERR "Oops, system error: $!\n";
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

    my $buf;
    my $bytes = sysread($sock, $buf, 1);
    if (!defined($bytes)) {
        if ($! == EAGAIN) {
            return undef;
        } elsif ($! == ECONNRESET) {
            disconnect();
            return undef;
        } else {
            print STDERR "Oops, system error: $!\n";
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


sub wait4($) {
    my ($regex) = @_;

    while (1) {
        my $msg = fb_net::readline_ifdata();
        if (!$msg) {
            print "Waiting for network...\n";
            sleep 1;
        } else {
            if ($msg =~ /$regex/) {
                return $msg;
            } else {
                my ($command, $message) = fb_net::decode_msg($msg);
                if ($command eq 'PUSH') {
                    print "$message\n";
                } else {
                    print "Unexpected message from server: $msg";
                }
            }
        }
    }
}

sub wait4start() {
    my $msg = fb_net::wait4('GAME_CAN_START');
    $msg =~ /GAME_CAN_START: (.*)/;
    $msg = $1;
    my @mappings;
    while ($msg) {
        my $id = substr($msg, 0, 1);
        $msg = substr($msg, 1);
        my ($nick, undef, $rest) = $msg =~ /([^,]+)(,(.*))?/;
        $msg = $rest;
        push @mappings, { id => $id, nick => $nick };
    }
    return @mappings;
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
        my ($rcv_command, $rcv_message) = fb_net::decode_msg($msg);
        if ($rcv_command eq $command) {
            $answer = $rcv_message;
        } else {
            #- this is not the answer we're waiting. keep that.
            $to_buffer .= $msg;
        }
    }
    $buffered_line = $to_buffer;
    return $answer;
}

sub list() {
    my $msg = send_and_receive('LIST');
    if ($msg =~ /(.*) free:(\d+) games:(\d+)/) {
        my $freegames = $1;
        my $free = $2;
        my $games = $3;
        my @games;
        while ($freegames =~ /\[([^\]]+)\]/g) {
            push @games, [ split /,/, $1 ];
        }
        return ($free, $games, @games);
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

my ($current_host, $current_port);
sub connect {
    my ($host, $port) = @_;

    my $perform_ping = 1;
    if (!defined $host) {
        #- reconnect
        $host = $current_host;
        $port = $current_port;
        $perform_ping = 0;
    } elsif (!defined $port) {
        #- first param was a hash
        my $params = $host;
        $host = $params->{host};
        $port = $params->{port};
        $ping = $params->{ping};
        $perform_ping = 0;
    }

    $current_host = $current_port = undef;

    $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp', Timeout => 2);
    if (!$sock) {
        print STDERR "Couldn't connect to $host:$port: $@\n";
        return { failure => 'Server is down' };
    }
    $sock->autoflush;

    $buffered_line = undef;
    my $msg = readline_();
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
        } else {
            print STDERR "Dropping $host:$port: not a Frozen-Bubble server\n";
            return { failure => 'Not an FB server' };
        }
    }

    if ($perform_ping) {
        $ping = 200;

        my @pings;
        foreach (1..4) {
            my $t0 = gettimeofday;
            send_('PING');
            $msg = readline_();
            my $t1 = gettimeofday;
            if ($msg =~ /INCOMPATIBLE_PROTOCOL/) {
                disconnect();
                print STDERR "Dropping $host:$port: imcompatible Frozen-Bubble server\n";
                return { failure => 'Incompatible server' };
            } elsif ($msg !~ /PONG/) {
                print STDERR "$host:$port answer to PING was not recognized. Server said:\n\t$msg\n";
                disconnect();
                return { failure => 'Incompatible server' };
            }
            push @pings, ($t1-$t0) * 1000;
            if ($_ == 2 && $pings[0] > 150 && $pings[1] > 150) {
                #- don't wait too much on slower servers
                last;
            }
        }

        if (@pings > 2) {  #- keep 2 worst
            @pings = difference2(\@pings, [ min(@pings) ]) while @pings > 2;
        }
        $ping = sprintf("%.1f", sum(@pings)/@pings);
    }

    my $flags = $sock->fcntl(F_GETFL, 0);
    if (!$flags) {
        disconnect();
        return { failure => 'Server is mad' };
    }

    $flags = $sock->fcntl(F_SETFL, $flags|O_NONBLOCK);
    if (!$flags) {
        disconnect();
        return { failure => 'Server is crazy' };
    }

    $current_host = $host;
    $current_port = $port;
    return { ping => $ping, name => $servername, language => $serverlanguage };
}


my @messages;
sub reconnect() {
    if (defined($current_host) && defined($current_port)) {
        disconnect();
        @messages = ();
        my $ret = fb_net::connect();
        return exists $ret->{ping};
    }
}

sub http_download($) {
    my ($url) = @_;

    my ($host, $port, $path) = $url =~ m,^http://([^/:]+)(?::(\d+))?(/\S*)?$,;
    $port ||= 80;

    $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp', Timeout => 5);
    if (!$sock) {
        print STDERR "Couldn't connect to $host:$port:\n\t$@\n";
        return;
    }
    $sock->autoflush;

    my ($sysname, undef, undef, undef, $machine) = uname();
    my $bytes = syswrite($sock, join("\r\n" =>
                                     "GET $path HTTP/1.0",
                                     "Host: $host:$port",
                                     "User-Agent: Frozen-Bubble client version $version (protocol version $proto_major.$proto_minor) on $sysname/$machine",
                                     "", ""));
    if (!$bytes) {
        disconnect();
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
        disconnect();
        return $tmp;
    } else {
        print STDERR "http_download: $@\n";
        disconnect();
        return;
    }
}

sub get_server_list() {
    my @masters = qw(http://www.frozen-bubble.org/servers/serverlist
                     http://frozen-bubble.sourceforge.net/serverlist
                     http://booh.org/fb-serverlist
                     http://zarb.org/~gc/fb-serverlist);
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


#- in game operations

#- data is command:parameters
#- supported commands:
#-   ! (synchro)
#-   a (angle)
#-   b (bubble)
#-   d (drop)
#-   f (fire)
#-   F (finished)
#-   l (leave)
#-   m (malus)
#-   M (malusstick)
#-   n (newgame)
#-   N (nextbubble)
#-   p (ping)
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

my $buffered_buf;
my $ouch;
sub grecv() {
    my @msg = @messages;
    @messages = ();

    if (!defined($sock)) {
        return @msg;
    }

    my $buf;
    my $bytes = sysread($sock, $buf, 1024);
    if (!defined($bytes)) {
        if ($! == EAGAIN) {
            return @msg;
        } elsif ($! == ECONNRESET) {
            disconnect();
            return;
        } else {
            print STDERR "Oops, system error: $!\n";
            return;
        }
    } elsif ($bytes == 0) {
        disconnect();
        return;
    }
    print "received $bytes bytes, adding to buffered ", length($buffered_buf), "\n";
    $buf = $buffered_buf . $buf;
    $buffered_buf = undef;
    my @ascii = unpack("C*", $buf);
    print "bytes in buf: @ascii\n";
    
    #- if previous receive was partial and was cut between \n and \0, we
    #- have a NULL in front of the message now
#    if (substr($buf, 0, 1) eq "\0") {
#        print "********************************************* partial cut between LF and NULL?\n";
#        $buf = substr($buf, 1);
#    }
        
    while ($buf) {
        #- first byte of a "frame" is the id of the sender
        my $id = substr($buf, 0, 1);
        $buf = substr($buf, 1);
#            printf "extracted id: %d\n", ord($id);
#        if (ord($id) < 1 || ord($id) > 10) {     #- this test is temp and helps to find protocol problems as long as there are never more than 5 players on server
#            printf "****** ouch! id %d, buf now <$buf>\n", ord($id);
#            printf "\talready msg: <$_->{msg}> from %d\n", ord($_->{id}) foreach @msg;
#            $ouch = 1;
#        }
        #- match data of a frame (newline terminated)
        if (my ($msg, $rest) = $buf =~ /([^\n]+)\n(.*)?/s) {  #-?
            $buf = $rest;
            push @msg, { id => $id, msg => $msg };
            print "\trecv-msg:", ord($id), ":$msg\n";
        } else {
            #- no match means that we received a partial packet
            print "*** partial receive! for <$buf>, buffering (theoretically harmless)\n";
            $buffered_buf = $id . $buf;
            $buf = undef;
        }
    }

    $ouch and die;
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

sub grecv_get1msg() {
    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
        while (!@messages) {
            sleep($ping/1000/3);
            @messages = grecv();
        }
        alarm 0;
    };
    if ($@) {
        print STDERR "Sorry, we are not received the expected message. If the other ends are legal Frozen-Bubble\n" .
                     "clients, it means your computer or the network is too slow. Giving up.\n";
        die 'quit';
    } else {
        return shift @messages;
    }
}


1;
