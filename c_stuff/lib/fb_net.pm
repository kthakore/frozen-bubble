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
use Time::HiRes qw(gettimeofday sleep);
use fb_stuff;


#- before game operations

my $proto_major = '1';
my $proto_minor = '0';
my $sock;
my $ping = 50;

sub send_($) {
    my ($msg) = @_;
    print $sock "FB/$proto_major.$proto_minor $msg\n";
}

sub readline_() {
    my $results = '';
    do {
        my $buf;
        sysread($sock, $buf, 1);
        if ($!) {
            if ($! == EAGAIN) {
                sleep($ping/1000/3);
            } else {
                print STDERR "Oops, system error: $!\n";
                return;
            }
        }
        $results .= $buf;
    } while ($results !~ /\n/);

#    print STDERR "$results";
    return $results;
}

sub readline_ifdata() {
    my $buf;
    sysread($sock, $buf, 1);
    if ($!) {
        if ($! == EAGAIN) {
            return;
        } else {
            print STDERR "Oops, system error: $!\n";
            return;
        }
    }

    if ($buf eq "\n") {
        return $buf;
    } else {
#        print STDERR $buf;
        return $buf . readline_();
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
                print "Server said:\n\t$msg";
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

sub list() {
    send_('LIST');
    my $msg = readline_();
    if ($msg =~ /LIST: (.*) free:(\d+)/) {
        my $games = $1;
        my $free = $2;
        my @games;
        while ($games =~ /\[([^\]]+)\]/g) {
            push @games, [ split /,/, $1 ];
        }
        return ($free, @games);
    } else {
        print STDERR "Answer to LIST was not recognized. Server said:\n\t$msg\n";
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
        print STDERR "Could not create game. Server said:\n\t$msg\n";
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
        print STDERR "Could not join game. Server said:\n\t$msg\n";
        return 0;
    }
}

sub connect($$) {
    my ($host, $port) = @_;

    $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp', Timeout => 10);
    if (!$sock) {
        print STDERR "Couldn't connect to $host:$port:\n\t$@\n";
        return;
    }
    $sock->autoflush;

    my $flags = $sock->fcntl(F_GETFL, 0);
    if (!$flags) {
        print STDERR "Couldn't fcntl socket from $host:$port:\n\t$@\n";
        return;
    }
    $flags = $sock->fcntl(F_SETFL, $flags|O_NONBLOCK);
    if (!$flags) {
        print STDERR "Couldn't fcntl socket from $host:$port:\n\t$@\n";
        return;
    }

    my $msg = readline_();
    my ($remote_major, $remote_minor, $isready) = $msg =~ m|^FB/(\d+).(\d+) (.*)|;
    if ($isready !~ /SERVER_READY/) {
        print STDERR "$host:$port not an FB server. Server said:\n\t$msg\n";
        return;
    }

    if ($remote_major != $proto_major || $remote_minor < $proto_minor) {
        print STDERR "$host:$port an imcompatible FB server. Server said:\n\t$msg\n";
        return;
    }

    $ping = 1;
    my $t0 = gettimeofday;
    send_('PING');
    $msg = readline_();
    my $t1 = gettimeofday;
    if ($msg !~ /PONG/) {
        print STDERR "$host:$port answer to PING was not recognized. Server said:\n\t$msg\n";
        return;
    }

    $ping = sprintf("%3.1f", ($t1-$t0)*1000);
    print "$host:$port is a protocol $remote_major.$remote_minor FB server with a ping of ${ping}ms.\n";

    return $ping;
}



#- in game operations

sub gsend($) {
    my ($msg) = @_;
    print $sock "$msg\n";
}

my @messages;
sub grecv() {
    my @msg = @messages;
    @messages = ();

    my $buf;
    sysread($sock, $buf, 1024);
    if ($!) {
        if ($! == EAGAIN) {
            return @msg;
        } else {
            print STDERR "Oops, system error: $!\n";
            return;
        }
    }

    my $id;
    while ($buf) {
        #- first byte of a "frame" is the id of the sender
        if (!$id) {
            $id = substr($buf, 0, 1);
            $buf = substr($buf, 1);
        }
        #- then loop for messages, each one ending with a newline; several can be
        #- sent at once: if the sender sent several messages before server reacted
        my ($msg, $rest) = $buf =~ /([^\n]+)\n(.*)?/s;
        $buf = $rest;
        push @msg, { id => $id, msg => $msg };
#        print "recv-msg:$msg\n";
        #- look for a NULL: it terminates a frame sent by the server from a given
        #- sender; but we might have some more data if we're reacting only after
        #- the server sent more than one frame
        if (substr($buf, 0, 1) eq "\0") {
            $id = undef;
            $buf = substr($buf, 1);
        }
    }

    return @msg;
}

sub grecv_get1msg() {
    if (!@messages) {
        @messages = grecv();
#        print "Waiting...\n";
        sleep($ping/1000/3);
        return grecv_get1msg();
    } else {
        return shift @messages;
    }
}


1;
