#*****************************************************************************
#
#                          Frozen-Bubble
#
# Copyright (c) 2008 The Frozen-Bubble Team
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
# fb_net_discover - high performance server discovery plugin for frozen bubble
# 
# SYNOPSIS
# 
#     my $discover = fb_net_discover->new(
#         { host => "1.2.3.4", port => 1511 },
#         { host => "5.6.7.8", port => 1512 }, ...);
#     while($discover->pending()) {
#         my @servers = $discover->found();
#         for(my $server = 0; $server < @servers; $server++) {
#             printf("%02i: ip %s ping %i\n",
#                 $server, $servers[$server]{ip}, $servers[$server]{ping});
#         }
#         $discover->work(0.1); # sit in a select loop for 100ms
# 
#         # update your screen, and all of that stuff, here.
#     }
# 
# 
# DESCRIPTION
# 
# fb_net_discover checks a list of servers, finding their versions, ping times,
# and number of current clients.  It uses nonblocking IO and select, to
# connect to multiple servers in parallel, thus reducing the total amount of
# time elapsed.  This, in turn, allows the user to begin playing frozen bubble
# more quickly. :)
# 
# This module is designed to be called from a GUI loop.  It has to spend sit in
# a select loop for most of its life in order to get accurate ping times, but
# it will return back to your loop at intervals you specify, so you can check
# for keystrokes and refresh the screen and so forth.
# 
# In order to get consistent results on slow dialup links, this module will only
# attempt to connect to one server per each 200ms.  This means for 18 servers
# that there are 3.4 seconds of extra guaranteed lag, but it also means packets
# from multiple servers are less likely to bump into eachother in the queue, so
# ping reply times will be more reliable.
# 
# In the source script, there are two configuration parameters: $number_of_pings
# and $time_between_connections.  These are set to 2 and 0.2, respectively.
# These two parameters will determine the amount of bandwidth used, and the
# amount of time taken before the user can select a server.  Assuming the user's
# internet connection can handle the traffic without extra latency from queueing
# or retransmissions, the worst case latency will be, in seconds:
# 
#     N*L + T*(S-1)
# 
# where
# 
#     N = $number_of_pings
#     L = the roundtrip time of the slowest server in the list, in seconds
#     T = $time_between_connections
#     S = the number of servers in the list
# 
# 
# CONSTRUCTOR
# 
#     ...->new ({host => "server1", port => port}, {host => "server2", port => port}, ...)
# 
# Takes a list of servers as arguments.  Each server argument should be a hash
# reference, consisting of {host => host, port => port}.  Returns a
# fb_net_discover object, which can be used within a GUI loop to discover all of
# your servers.
# 
# The host string should ideally be an IP address.  A hostname string should work
# too, but DNS lookups will introduce extra, unpredictable latency later on.
# 
#
# METHODS
# 
# These methods define the public API for instances of this class.
# 
#   found
# 
# Returns a list of 0 or more servers found.  Each return value is a hash
# reference, containing the following keys:
# 
#     host: the IP address of the server
#     port: the TCP port of the server
#     pingtimes: array reference, contains the actual result times of 4 pings
#     ping: the average roundtrip latency of the server, in ms
#     freenicks: the list of players connected
#     freegames: the list of open games (not yet started)
#     free: the number of idle clients connected to this server
#     games: the number of clients connected to this server, who are playing games
#     playing: the list of players in games
#     geolocs: the geolocations of players in games
#     name: the self-proclaimed "name" reported by the server
#     language: the preferred language reported by the server
# 
#   pending
# 
# Returns non-zero if we are still waiting for a response from one or more
# servers; returns 0 if processing is complete.
# 
#   work(seconds)
# 
# Enters the main loop of this module.  This method requires one argument, a
# numeric count of seconds to work for.  This is expected to be a floating point
# decimal, for sub-second precision.  Returns the number of servers pending, just
# like the pending method does.
#
# 
# INTERNAL METHODS
# 
# These methods are only meant to be called from within the module.  They are
# subject to change without notice.
# 
#   try_connect
# 
# Attempts to connect to a server.  Moves the first "not_started" server to the
# "pending" list, and creates a non-blocking IO::Socket::INET object for it.
# Updates the begin_time timestamp, to determine when the next server should be
# connected.
# 
#   server_sm(connection_number)
#
# Implements a simple state machine.  Called with an index into the pending
# array, to indicate that data is available for reading from this server.
# 
#   give_up_on(connection_number, reason)
# 
# Called if select reports a socket as has_exception.  Also called if the
# server has a bogus version, times out, or we can't parse the IP address or
# something.  Removes the entry from further processing, and emits an error
# message on stderr.
# 
#
# EXPORT
# 
# None.
#
# 
# BUGS
# 
# implement some sort of timeout, for servers which don't respond within 5 seconds.
# 
#
# AUTHOR
# 
# Mark Glines, <mark@glines.org>.
# 
#
# COPYRIGHT AND LICENSE
# 
# This code is donated to the frozen bubble project, www.frozen-bubble.org, so
# they can do whatever they want with it.  Copyright is therefore assigned to
# those guys.
# 
#******************************************************************************

package fb_net_discover;

use strict;
use warnings;
use IO::Socket;
use IO::Select;
use Time::HiRes qw(gettimeofday tv_interval);
use Carp;

use fb_net;
my $proto_hdr = "FB/" . $fb_net::proto_major . "." .$fb_net::proto_minor;

# configuration parameters
my $number_of_pings = 2;   # ping each server this many times
my $time_between_connections = 0.1; # 100ms, 10 connections per second
my $connection_timeout = 5;

# note: the ping-averaging code below assumes $number_of_pings >= 2.


sub new {
    my ($package, @servers) = @_;
    my $time = [gettimeofday];
    # force the first connection immediately
    $$time[0]--;
    my $self = {
        begin_time  => $time, # used to sequence the connect()s
        not_started => {},    # server entries move from here...
        pending     => {},    # ... to here ...
        complete    => {},    # ... to here.
        revmapping  => {},    # used after select(), to map handles to hashkeys
    };
    my $servid = 1;
    foreach my $server (@servers) {
        croak "server $server is not a hash reference" unless ref $server eq 'HASH';
        croak "server has no 'host' field" unless exists $$server{host};
        croak "server has no 'port' field" unless exists $$server{port};
        $$server{pingtimes} = []; # we will average these results together
        $$self{not_started}{$servid++} = $server;
    }
    return bless($self, $package);
}


sub found {
    my $self = shift;
    return values %{$$self{complete}};
}

sub pending {
    my $self = shift;
    return scalar(keys %{$$self{pending}})
         + scalar(keys %{$$self{not_started}});
}

sub work {
    my ($self, $timeout) = @_;
    my $starttime = [gettimeofday];
    # run through it once quickly, even if $timeout is 0.
    do {
        # try connect if not_started servers exist, and timestamp says its time
         $self->try_connect()
             if(scalar(keys %{$$self{not_started}})
             && tv_interval($$self{begin_time}) >= $time_between_connections);

        # do a select, to see who has connected, and who has sent data to us
        my $select = IO::Select->new();
        $select->add( map { $$_{sock} } (values %{$$self{pending}}));
        my $thistime = $timeout - tv_interval($starttime);
        $thistime = 0 if $thistime < 0;
        my @ready = $select->can_read($thistime);
        foreach my $sock (@ready) {
            # the revmapping table maps stringified sockets to hash keys, so
            # we don't have to do a search for it.
            my $key = $$self{revmapping}{"$sock"};
            $self->server_sm($key);
        }
        my @dead = $select->has_exception(0);
        foreach my $sock (@dead) {
            my $key = $$self{revmapping}{"$sock"};
            $self->give_up_on($key, "Select exception");
        }
    } while(tv_interval($starttime) < $timeout);
    # rip those which have connection timeout
    foreach my $pending (keys %{$$self{pending}}) {
        if (tv_interval($$self{pending}{$pending}{begin_time}) >= $connection_timeout
            && !$$self{pending}{$pending}{name}) {
            $self->give_up_on($pending, "Connection timeout (${connection_timeout}s)");
        }
    }
    return $self->pending();
}

sub try_connect {
    my $self = shift;
    my @newkeys = sort keys %{$$self{not_started}};
    croak "try_connect called, but everything is already connected!"
        unless scalar @newkeys;
    # just pull the first entry off the list
    my $key = shift(@newkeys);
    # move server entry from not_started hash to pending hash
    my $ref = $$self{not_started}{$key};
    $$self{pending}{$key} = $ref;
    delete($$self{not_started}{$key});
    my $sock = IO::Socket::INET->new(
        PeerAddr => $$ref{host},
        PeerPort => $$ref{port},
        Proto    => 'tcp',
        Blocking => 0,
    );
    if(defined($sock)) {
        $$ref{sock} = $sock;
        $$self{revmapping}{"$sock"} = $key;
        $$ref{begin_time} = $$self{begin_time} = [gettimeofday];
    } else {
        $self->give_up_on($key, "Could not create socket");
    }
}

sub server_sm {
    my ($self, $connid) = @_;
    my $conn = $$self{pending}{$connid};
    if(!defined($$conn{state})) {
        # new connection!
        $$conn{state} = 'connected';
        $$conn{rxdata} = '';
        return; # the first "PUSH" line might not arrive at the same moment as
                # the connection.  When it comes in, we'll will come back here.
    } else {
        # read some data.
        my $newdata = '';
        my $sock = $$conn{sock};
        if (!defined($sock->recv($newdata, 1024, 0))) {
            # an error occurred, give up
            $self->give_up_on($connid, $!);
            return;
        }
        $$conn{rxdata} .= $newdata;
    }

    my $index;
    while(($index = index($$conn{rxdata}, "\n")) > -1) {
        my $str = substr($$conn{rxdata}, 0, $index);
        $$conn{rxdata} = substr($$conn{rxdata}, $index+1);

        # strip off the protocol header.
        if(substr($str, 0, length($proto_hdr)+1) eq "$proto_hdr ") {
            $str = substr($str, length($proto_hdr) + 1);
        } else {
            # protocol mismatch, give up.
            $self->give_up_on($connid, "Frozen-Bubble protocol mismatch");
        }

        if ($str =~ /^PUSH: SERVER_READY (.*) (.*)/) {
            $$conn{name}     = $1;
            $$conn{language} = $2;
            $$conn{sock}->send("$proto_hdr PING\n");
            $$conn{ping_time} = [gettimeofday];
        } elsif($str =~ /^PING: PONG/) {
            # nothing to parse.  take a time measurement, send another one if
            # necessary.
            my $reply_time = tv_interval($$conn{ping_time});
            push(@{$$conn{pingtimes}}, tv_interval($$conn{ping_time}));
            if(scalar @{$$conn{pingtimes}} >= $number_of_pings) {
                $$conn{sock}->send("$proto_hdr LIST\n");
                delete($$conn{ping_time});
            } else {
                $$conn{sock}->send("$proto_hdr PING\n");
                $$conn{ping_time} = [gettimeofday];
            }
        } elsif($str =~ /LIST: (\S*) (\S*) free:(\d+) games:(\d+) playing:(\d+) at:(\S*)/) {
            $$conn{freenicks} = $1;
            $$conn{freegames} = $2;
            $$conn{free}      = $3;
            $$conn{games}     = $4;
            $$conn{playing}   = $5;
            $$conn{geolocs}   = $6;
            # we're done, get out of here.
            # move connection to "complete" list
            delete($$self{pending}{$connid});
            $$self{complete}{$connid} = $conn;
            # clean up temporary stuff
            delete($$conn{state});
            delete($$conn{rxdata});
            # disconnect from server
            delete($$conn{sock});
            # calculate average ping time from worst 2 pings
            my @pingtimes = reverse sort @{$$conn{pingtimes}};
            $pingtimes[0] += $pingtimes[1];
            $$conn{ping} = $pingtimes[0] / 2;
            $$conn{ping} = sprintf("%.1f", $$conn{ping} * 1000); # time in ms
            return;
        } else {
            # drop the line, for now
        }
    }
}

sub give_up_on {
    my ($self, $connid, $reason) = @_;
    print STDERR "Problem with server $$self{pending}{$connid}{host}:$$self{pending}{$connid}{port}: $reason.\n";
    $$self{pending}{$connid}{sock}->shutdown(2);
    delete($$self{pending}{$connid});
}

1;
