use strict;
use warnings;
use Test::More;

BEGIN {
        my @modules = (
        'Games::FrozenBubble',
        'Games::FrozenBubble::CStuff',
#       'Games::FrozenBubble::LevelEditor',
#       'Games::FrozenBubble::MDKCommon',
#       'Games::FrozenBubble::Net',
#       'Games::FrozenBubble::NetDiscover',
#       'Games::FrozenBubble::Stuff',
#       'Games::FrozenBubble::Symbols',
        );

        plan tests => scalar @modules;

        use_ok $_ foreach @modules;
}
