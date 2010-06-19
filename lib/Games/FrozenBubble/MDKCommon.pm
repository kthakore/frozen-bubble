package Games::FrozenBubble::MDKCommon;
use 5.006;
use strict;
use warnings;

our @ISA    = 'Exporter';
our @EXPORT = qw{
    $PI cat_ member difference2 any even odd sqr to_bool to_int if_
    fold_left output append_to_file min max backtrace basename cp_af all
};

our $PI = 3.1415926535897932384626433832795028841972;

sub cat_ {
    local *F;
    open F, $_[0] or return;
    my @l = <F>;
    wantarray ? @l : join '', @l;
}

sub member {
    my $e = shift;
    foreach (@_) { $e eq $_ and return 1 }
    0;
}

sub difference2 {
    my %l;
    @l{ @{ $_[1] } } = ();
    grep { !exists $l{$_} } @{ $_[0] };
}

sub any(&@) {
    my $f = shift;
    $f->($_) and return 1 foreach @_;
    0;
}

sub even { $_[0] % 2 == 0 }

sub odd { $_[0] % 2 == 1 }

sub sqr { $_[0] * $_[0] }

sub to_bool { $_[0] ? 1 : 0 }

sub to_int { $_[0] =~ /(\d*)/; $1 }

sub if_($@) {
    my $b = shift;
    $b or return ();
    wantarray || @_ <= 1
      or die( "if_ called in scalar context with more than one argument "
          . join( ":", caller() ) );
    wantarray ? @_ : $_[0];
}

sub fold_left(&@) {
    my ( $f, $initial, @l ) = @_;
    local ( $::a, $::b );
    $::a = $initial;
    foreach $::b (@l) { $::a = &$f() }
    $::a;
}

sub output {
    my $f = shift;
    local *F;
    open F, ">$f" or die "output in file $f failed: $!\n";
    print F foreach @_;
}

sub append_to_file {
    my $f = shift;
    local *F;
    open F, ">>$f" or die "output in file $f failed: $!\n";
    print F foreach @_;
    1;
}

sub min { my $n = shift; $_ < $n and $n = $_ foreach @_; $n }

sub max { my $n = shift; $_ > $n and $n = $_ foreach @_; $n }

sub backtrace {
    my $s;
    for ( my $i = 1 ; caller($i) ; $i++ ) {
        my ( $package, $file, $line, $func ) = caller($i);
        $s .= "$func() called from $file:$line\n";
    }
    $s;
}

sub basename { local $_ = shift; s|/*\s*$||; s|.*/||; $_ }

sub cp_af {
    my $dest = pop @_;

    @_ or return;
    @_ == 1 || -d $dest
      or die
"cp: copying multiple files, but last argument ($dest) is not a directory\n";

    foreach my $src (@_) {
        my $dest = $dest;
        -d $dest and $dest .= '/' . basename($src);

        unlink $dest;

        if ( -d $src ) {
            -d $dest
              or mkdir $dest, ( stat($src) )[2]
              or die "mkdir: can't create directory $dest: $!\n";
            cp_af( glob_($src), $dest );
        }
        elsif ( -l $src ) {
            unless (
                symlink(
                    ( readlink($src) || die "readlink failed: $!" ), $dest
                )
              )
            {
                warn "symlink: can't create symlink $dest: $!\n";
            }
        }
        else {
            local *F;
            open F, $src or die "can't open $src for reading: $!\n";
            local *G;
            open G, "> $dest";
            local $_;
            while (<F>) { print G $_ }
            chmod( ( stat($src) )[2], $dest );
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

1;

__END__

=encoding UTF-8

=head1 DESCRIPTION

This is extracted from MDK::Common, a helper library that
extends perl capabilities for very common use when programming
perl, especially with functional style programming (but what
other style one could decently adopt? ;p).

This extract is provided here because only Mandrake distro
includes the whole MDK::Common, so you're not obliged to
install it.

That said, if you're a perl programmer, I strongly advice you
to have a look at this library and use it, it would
dramatically increase the efficiency and readability of your
perl programs.

Go to google and type in "perl-MDK-Common" if interested.
