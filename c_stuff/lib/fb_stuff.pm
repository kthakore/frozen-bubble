#*****************************************************************************
#
#                          Frozen-Bubble
#
# Copyright (c) 2000, 2001, 2002, 2003, 2004 The Frozen-Bubble Team
#
# Sponsored by MandrakeSoft <http://www.mandrakesoft.com/>
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

package fb_stuff;

use fb_c_stuff;
use vars qw(@ISA @EXPORT $FPATH $FBLEVELS $colourblind %POS_1P %POS_2P %POS_MP $BUBBLE_SIZE $ROW_SIZE
            $PI);
@ISA = qw(Exporter);
@EXPORT = qw($FPATH $colourblind $FBLEVELS %POS_1P %POS_2P %POS_MP $BUBBLE_SIZE $ROW_SIZE
             $PI cat_ member difference2 any every even odd sqr to_bool to_int if_ chomp_
             fold_left output append_to_file min max backtrace basename cp_af all partition ssort sum);

$FPATH = '@DATADIR@/frozen-bubble';

%POS_2P = ( p1 => { left_limit => 30, right_limit => 286, top_limit => 40, 'initial_bubble_y' => 390,
                    canon => { x => 108, 'y' => 356 },
                    simpleshooter => { x => 157, 'y' => 405, diameter => 60 },
                    pinguin => { x => 168, 'y' => 437 },
                    next_bubble => { x => 112, 'y' => 440 },
                    on_top_next_relpos => { x => -4, 'y' => -3 },
                    hurry => { x => 10, 'y' => 265 },
                    malus => { x => 308, 'y' => 408 },
                    scores => { x => 293, 'y' => 428 } },
	    p2 => { left_limit => 354, right_limit => 610, top_limit => 40, 'initial_bubble_y' => 390,
                    canon => { x => 432, 'y' => 356 },
                    simpleshooter => { x => 481, 'y' => 405, diameter => 60 },
                    pinguin => { x => 32,  'y' => 437 },
                    next_bubble => { x => 112, 'y' => 440 },
                    on_top_next_relpos => { x => -4, 'y' => -3 },
                    hurry => { x => 10, 'y' => 265 },
                    malus => { x => 331, 'y' => 408 },
                    scores => { x => 341, 'y' => 428 } },
	    centerpanel => { x => 153, 'y' => 190 },
	  );

%POS_1P = ( p1 => { left_limit => 190, right_limit => 446, top_limit => 44, 'initial_bubble_y' => 390,
                    canon => { x => 268, 'y' => 356 },
                    simpleshooter => { x => 317, 'y' => 405, diameter => 60 },
                    pinguin => { x => 168, 'y' => 437 },
                    next_bubble => { x => 112, 'y' => 440 },
                    on_top_next_relpos => { x => -4, 'y' => -3 },
                    hurry => { x => 10, 'y' => 265 },
                    scores => { x => 180, 'y' => 432 } },
	    centerpanel => { x => 149, 'y' => 190 },
	    pause_clip => { x => 263, 'y' => 212 },
            compressor_xpos => 321,
	  );

%POS_MP = ( p1 => { left_limit => 190, right_limit => 446, top_limit => 44, 'initial_bubble_y' => 390,
                    canon => { x => 268, 'y' => 356 },   #- (left_limit + right_limit) / 2 - 50  |  initial_bubble_y + 16 - 50  (50x50 is half dimensions of gfx/shoot/base)
                    simpleshooter => { x => 317, 'y' => 405, diameter => 60 },
                    pinguin => { x => 168, 'y' => 437 },
                    next_bubble => { x => 112, 'y' => 440 },
                    on_top_next_relpos => { x => -4, 'y' => -3 },
                    hurry => { x => 10, 'y' => 265 },
                    malus => { x => 450, 'y' => 408 },
                    scores => { x => 180, 'y' => 440 } },
            rp1 => { left_limit => 20, right_limit => 148, top_limit => 18, 'initial_bubble_y' => 190,
                     canon => { x => 59, 'y' => 174 },
                     simpleshooter => { x => 83, 'y' => 197, diameter => 30 },
                     pinguin => { x => 18, 'y' => 211 },
                     next_bubble => { x => 56, 'y' => 216 },
                     on_top_next_relpos => { x => -2, 'y' => -1 },
                     hurry => { x => 5, 'y' => 128 },
                     malus => { x => 180, 'y' => 180 },
                     scores => { x => 150, 'y' => 170 },
                     nick => { x => 150, 'y' => 190 } },
            rp2 => { left_limit => 492, right_limit => 620, top_limit => 18, 'initial_bubble_y' => 190,
                     canon => { x => 531, 'y' => 174 },
                     simpleshooter => { x => 555, 'y' => 197, diameter => 30 },
                     pinguin => { x => 18, 'y' => 211 },
                     next_bubble => { x => 56, 'y' => 216 },
                     on_top_next_relpos => { x => -2, 'y' => -1 },
                     hurry => { x => 5, 'y' => 128 },
                     malus => { x => 470, 'y' => 208 },
                     scores => { x => 480, 'y' => 170 },
                     nick => { x => 480, 'y' => 190 } },
            rp3 => { left_limit => 20, right_limit => 148, top_limit => 235, 'initial_bubble_y' => 408,
                     canon => { x => 59, 'y' => 392 },
                     simpleshooter => { x => 83, 'y' => 415, diameter => 30 },
                     pinguin => { x => 18, 'y' => 429 },
                     next_bubble => { x => 56, 'y' => 433 },
                     on_top_next_relpos => { x => -2, 'y' => -1 },
                     hurry => { x => 5, 'y' => 345 },
                     malus => { x => 180, 'y' => 408 },
                     scores => { x => 150, 'y' => 400 },
                     nick => { x => 150, 'y' => 420 } },
            rp4 => { left_limit => 492, right_limit => 620, top_limit => 235, 'initial_bubble_y' => 408,
                     canon => { x => 531, 'y' => 392 },
                     simpleshooter => { x => 555, 'y' => 415, diameter => 30 },
                     pinguin => { x => 18, 'y' => 429 },
                     next_bubble => { x => 56, 'y' => 433 },
                     on_top_next_relpos => { x => -2, 'y' => -1 },
                     hurry => { x => 5, 'y' => 345 },
                     malus => { x => 470, 'y' => 408 },
                     scores => { x => 480, 'y' => 400 },
                     nick => { x => 480, 'y' => 420 } },
	    centerpanel => { x => 149, 'y' => 190 },
	  );

$FBLEVELS = "$ENV{HOME}/.fblevels";

$BUBBLE_SIZE = 32;
$ROW_SIZE = $BUBBLE_SIZE * 7/8;

# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=--
# This is extracted from MDK::Common, a helper library that
# extends perl capabilities for very common use when programming
# perl, especially with functional style programming (but what
# other style one could decently adopt? ;p).
#
# This extract is provided here because only Mandrake distro
# includes the whole MDK::Common, so you're not obliged to
# install it.
#
# That said, if you're a perl programmer, I strongly advice you
# to have a look at this library and use it, it would
# dramatically increase the efficiency and readability of your
# perl programs.
#
# Go to google and type in "perl-MDK-Common" if interested.
#
$PI = 3.1415926535897932384626433832795028841972;
sub cat_ { local *F; open F, $_[0] or return; my @l = <F>; wantarray ? @l : join '', @l }
sub member { my $e = shift; foreach (@_) { $e eq $_ and return 1 } 0 }
sub difference2 { my %l; @l{@{$_[1]}} = (); grep { !exists $l{$_} } @{$_[0]} }
sub any(&@) {
    my $f = shift;
    $f->($_) and return 1 foreach @_;
    0;
}
sub every(&@) {
    my $f = shift;
    $f->($_) or return 0 foreach @_;
    1;
}
sub even { $_[0] % 2 == 0 }
sub odd  { $_[0] % 2 == 1 }
sub sqr  { $_[0] * $_[0] }
sub to_bool { $_[0] ? 1 : 0 }
sub to_int { $_[0] =~ /(\d*)/; $1 }
sub if_($@) {
    my $b = shift;
    $b or return ();
    wantarray || @_ <= 1 or die("if_ called in scalar context with more than one argument " . join(":", caller()));
    wantarray ? @_ : $_[0];
}
sub fold_left(&@) {
    my ($f, $initial, @l) = @_;
    local ($::a, $::b);
    $::a = $initial;
    foreach $::b (@l) { $::a = &$f() }
    $::a
}
sub output { my $f = shift; local *F; open F, ">$f" or die "output in file $f failed: $!\n"; print F foreach @_; }
sub append_to_file { my $f = shift; local *F; open F, ">>$f" or die "output in file $f failed: $!\n"; print F foreach @_; 1 }
sub min { my $n = shift; $_ < $n and $n = $_ foreach @_; $n }
sub max { my $n = shift; $_ > $n and $n = $_ foreach @_; $n }
sub backtrace {
    my $s;
    for (my $i = 1; caller($i); $i++) {
	my ($package, $file, $line, $func) = caller($i);
	$s .= "$func() called from $file:$line\n";
    }
    $s;
}
sub basename { local $_ = shift; s|/*\s*$||; s|.*/||; $_ }
sub cp_af {
    my $dest = pop @_;

    @_ or return;
    @_ == 1 || -d $dest or die "cp: copying multiple files, but last argument ($dest) is not a directory\n";

    foreach my $src (@_) {
	my $dest = $dest;
	-d $dest and $dest .= '/' . basename($src);

	unlink $dest;

	if (-d $src) {
	    -d $dest or mkdir $dest, (stat($src))[2] or die "mkdir: can't create directory $dest: $!\n";
	    cp_af(glob_($src), $dest);
	} elsif (-l $src) {
	    unless (symlink((readlink($src) || die "readlink failed: $!"), $dest)) {
		warn "symlink: can't create symlink $dest: $!\n";
	    }
	} else {
	    local *F; open F, $src or die "can't open $src for reading: $!\n";
	    local *G; open G, "> $dest";
	    local $_; while (<F>) { print G $_ }
	    chmod((stat($src))[2], $dest);
	}
    }
    1;
}
sub all {
    my $d = shift;

    local *F;
    opendir F, $d or return;
    my @l = grep { $_ ne '.' && $_ ne '..' } readdir F;
    closedir F;

    @l;
}
sub partition(&@) {
    my $f = shift;
    my (@a, @b);
    foreach (@_) {
	$f->($_) ? push(@a, $_) : push(@b, $_);
    }
    \@a, \@b;
}
sub chomp_ { my @l = map { my $l = $_; chomp $l; $l } @_; wantarray() ? @l : $l[0] }
sub ssort(&@) {
    my $f = shift;
    sort { local $_ = $a; my $fa = $f->($a); local $_ = $b; $fa <=> $f->($b) } @_;
}
sub sum { my $n = 0; $n += $_ foreach @_; $n }
# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=--

