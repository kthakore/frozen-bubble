use inc::Module::Install 0.91;

all_from 'lib/Games/FrozenBubble.pm';
requires 'SDL' => '2.002003001';
install_share;

WriteAll;
