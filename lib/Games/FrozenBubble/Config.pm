package Games::FrozenBubble::Config;
use File::ShareDir qw(dist_dir);
use vars qw(@ISA @EXPORT $FPATH $FLPATH);
@ISA = qw(Exporter);
@EXPORT = qw($FPATH $FLPATH);
$FPATH = dist_dir('Games-FrozenBubble');
$FLPATH = "/usr/local/lib/frozen-bubble";
1;
