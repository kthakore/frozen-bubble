#!/usr/bin/perl -w
#	Mixer.pm
#
#	a SDL module for manipulating the SDL_mixer lib.
#
#	David J. Goehrig Copyright (C) 2000

package SDL::Mixer;
use strict;
use SDL::sdlpl;
require SDL::Music;
require SDL::Sound;

BEGIN {
	use Exporter();
	use vars qw(@EXPORT @ISA);
	@ISA = qw(Exporter);
	@EXPORT = qw(&MIX_MAX_VOLUME &MIX_DEFAULT_FREQUENCY &MIX_DEFAULT_FORMAT
			&MIX_DEFAULT_CHANNELS &MIX_NO_FADING &MIX_FADING_OUT
			&MIX_FADING_IN &AUDIO_U8 &AUDIO_S8 &AUDIO_U16 
			&AUDIO_S16 &AUDIO_U16MSB &AUDIO_S16MSB );
}

#
# Constants and the like you know
#

sub MIX_MAX_VOLUME { return SDL::sdlpl::sdl_mix_max_volume(); }
sub MIX_DEFAULT_FREQUENCY { return SDL::sdlpl::sdl_mix_default_frequency(); }
sub MIX_DEFAULT_FORMAT { return SDL::sdlpl::sdl_mix_default_format(); }
sub MIX_DEFAULT_CHANNELS { return SDL::sdlpl::sdl_mix_default_channels(); }
sub MIX_NO_FADING { return SDL::sdlpl::sdl_mix_no_fading(); }
sub MIX_FADING_OUT { return SDL::sdlpl::sdl_mix_fading_out(); }
sub MIX_FADING_IN { return SDL::sdlpl::sdl_mix_fading_in(); }
sub AUDIO_U8 { return SDL::sdlpl::sdl_audio_U8(); }
sub AUDIO_S8 { return SDL::sdlpl::sdl_audio_S8(); }
sub AUDIO_U16 { return SDL::sdlpl::sdl_audio_U16(); }
sub AUDIO_S16 { return SDL::sdlpl::sdl_audio_S16(); }
sub AUDIO_U16MSB { return SDL::sdlpl::sdl_audio_U16MSB(); }
sub AUDIO_S16MSB { return SDL::sdlpl::sdl_audio_S16MSB(); }



#
# Mixer Constructor / Destructor
#

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	my %options = @_;
	my $frequency = $options{-frequency} || $options{-rate} 
				|| MIX_DEFAULT_FREQUENCY();
	my $format = $options{-format} || MIX_DEFAULT_FORMAT();
	my $channels = $options{-channels} || MIX_DEFAULT_CHANNELS();
	my $size = $options{-size} || 4096;
	if ( SDL::sdlpl::sdl_mix_open_audio($frequency,$format,$channels,$size )) { 
		die SDL::sdlpl::sdl_get_error(); 
	}
	bless $self,$class;
	return $self;
}	

sub DESTROY {
	my $self = shift;

	#XXX: is this implying that this class should be  a signleton?
	SDL::sdlpl::sdl_mix_close_audio();
}


sub query_spec {
	my ($status,$freq,$format,$channels) = SDL::sdlpl::sdl_mix_query_spec();
	my %hash = ( -status => $status, -frequency => $freq, 
			-format => $format, -channels => $channels );
	return \%hash;
}

sub reserve_channels {
	my $self = shift;
	my $channels = shift;
	return SDL::sdlpl::sdl_mix_reserve_channels($channels);
}

sub allocate_channels {
	my $self = shift;
	my $channels = shift;
	return SDL::sdlpl::sdl_mix_allocate_channels($channels);
}

sub group_channel {
	my $self = shift;
	my $channel = shift;
	my $group = shift;
	return SDL::sdlpl::sdl_mix_group_channel($channel, $group);
}

sub group_channels {
	my $self = shift;
	my $from = shift;
	my $to = shift;
	my $group = shift;
	return SDL::sdlpl::sdl_mix_group_channels($from,$to,$group);
}

sub group_available {
	my $self = shift;	
	my $group = shift;
	return SDL::sdlpl::sdl_mix_group_available($group);
}

sub group_count {
	my $self = shift;
	my $group = shift;
	return SDL::sdlpl::sdl_mix_group_count($group);
}	

sub group_oldest {
	my $self = shift;
	my $group = shift;
	return SDL::sdlpl::sdl_mix_group_oldest($group);
}	

sub group_newer {
	my $self = shift;
	my $group = shift;
	return SDL::sdlpl::sdl_mix_group_newer($group);
}	

sub play_channel {
	my $self = shift;
	my $channel = shift;
	my $chunk = shift;
	my $loops = shift;
	my $ticks;
	if (@_) { $ticks = shift; } else { $ticks = -1; }
	return SDL::sdlpl::sdl_mix_play_channel_timed($channel,$chunk->{-data},
			$loops,$ticks);
}

sub play_music {
	my $self = shift;
	my $music = shift;
	my $loops = shift;
	return SDL::sdlpl::sdl_mix_play_music($music->{-data},$loops);
}

sub fade_in_channel {
	my $self = shift;
	my $channel = shift;
	my $chunk = shift;
	my $loops = shift;
	my $ms = shift;
	my $ticks;
	if (@_) { $ticks = shift; } else { $ticks = -1; }
	return SDL::sdlpl::sdl_mix_fade_in_channel_timed($channel,$chunk->{-data},
		$loops,$ms,$ticks);
}

sub fade_in_music {
	my $self = shift;
	my $music = shift;
	my $loops = shift;
	my $ms = shift;
	return SDL::sdlpl::sdl_mix_fade_in_music($music->{-data},$loops,$ms);
}

sub channel_volume {
	my $self = shift;
	my $channel = shift;
	my $volume = shift;
	return SDL::sdlpl::sdl_mix_volume($channel,$volume);
}

sub music_volume {
	my $self = shift;
	my $volume = shift;
	return SDL::sdlpl::sdl_mix_music_volume($volume);
}

sub halt_channel {
	my $self = shift;
	my $channel = shift;
	return SDL::sdlpl::sdl_mix_halt_channel($channel);
}

sub halt_group {
	my $self = shift;
	my $group = shift;
	return SDL::sdlpl::sdl_mix_halt_group($group);
}

sub halt_music {
	return SDL::sdlpl::sdl_mix_halt_music();
}

sub channel_expire {
	my $self = shift;
	my $channel = shift;
	my $ticks = shift;
	return SDL::sdlpl::sdl_mix_expire_channel($channel,$ticks);
}

sub fade_out_channel {
	my $self = shift;
	my $channel = shift;
	my $ms = shift;
	return SDL::sdlpl::sdl_mix_fade_out_channel($channel,$ms);
}

sub fade_out_group {
	my $self = shift;
	my $group = shift;
	my $ms = shift;
	return SDL::sdlpl::sdl_mix_fade_out_group($group,$ms);
}

sub fade_out_music {
	my $self = shift;
	my $ms = shift;
	return SDL::sdlpl::sdl_mix_fade_out_music($ms);
}

sub fading_music {
	return SDL::sdlpl::sdl_mix_fading_music_p();
}

sub fading_channel {
	my $self = shift;
	my $channel = shift;
	return SDL::sdlpl::sdl_mix_fading_channel_p($channel);
}
	
sub pause {
	my $self = shift;
	my $channel = shift;
	SDL::sdlpl::sdl_mix_pause($channel);
}

sub resume {
	my $self = shift;
	my $channel = shift;
	SDL::sdlpl::sdl_mix_resume($channel);
}

sub paused {
	my $self = shift;
	my $channel = shift;
	return SDL::sdlpl::sdl_mix_paused($channel);
}

sub pause_music {
	SDL::sdlpl::sdl_mix_pause_music();
}

sub resume_music {
	SDL::sdlpl::sdl_mix_resume_music();
}

sub rewind_music {
	SDL::sdlpl::sdl_mix_rewind_music();
}

sub music_paused {
	return SDL::sdlpl::sdl_mix_paused_music();
}

sub playing {
	my $self = shift;
	my $channel = shift;
	return SDL::sdlpl::sdl_mix_playing($channel);
}

sub playing_music {
	return SDL::sdlpl::sdl_mix_playing_music();
}

sub set_music_command {
	my $self = shift;
	my $command = shift;
	return SDL::sdlpl::sdl_set_music_cmd($command);
}

1;

__END__;

=head1 NAME

SDL::Mixer - a SDL perl extension

=head1 SYNOPSIS

  $mixer = new SDL::Mixer 	-frequency => MIX_DEFAULT_FREQUENCY,
				-format => MIX_DEFAULT_FORMAT,
				-channels => MIX_DEFAULT_CHANNELS,
				-size => 4096;

=head1 DESCRIPTION

	This module provides a pseudo object ( it contains no data ),
that handles all of the digital audio for the system.  It is simply an
interface for SDL_mixer.  In general, there is no need to pass any flags
to the constructor.  The default, shown above, provides 8 channels of
16 bit audio at 22050 Hz. and a single channel of music.

	The flags passable are -frequency ( or for the impatient -rate ),
-format, -channels, -size, which specify the sample frequency, byte
format, number of channels, and sample size respectively.  Frequency
can range from 11025 to 44100.  Format is one of the following:
AUDIO_U8, AUDIO_S8, AUDIO_U16, AUDIO_S16.  For those with big endian
machines use AUDIO_U16MSB and AUDIO_S16MSB.  Channels default to 8,
while size goes to 4096, and can range from 512 to 8096.  Given you
are using perl, a higher latency is probably more realistic. 

	There are two subordinate modules, Sound.pm and Music.pm
which handle the actual file access and memory cleanup.  Sound objects
also have a per file volume control above and beyond the channel's 
volume setting.  It can be set to half volume as follows:

	my $wavfile = new SDL::Sound "funk.wav";
	$wavfile.volume(64);

	Sound objects can only load .wav files.  Music files, however,
can load MIDI files such as .mod .s3m .it .xm.  Music files, more importantly,
through use of Lokisoft's smpeg library, can play MP3 files.  This is,
of course, the music format of choice.  If you need normal CD audio, please
use the Cdrom.pm module.

=head2 Functions

	$hashref = $mixer->query_spec();

Query_spec returns a has containing the keys -status, -frequency, -format,
and -channels.  These are the values that are being used by the mixer.
If you are adventurous, the SDL::sdlpl::sdl_*_audio_* functions provide low
level access the the SDL Audio features.  Without C level callback functions
these routines are useless though.

	$mixer->reserve_channels(n);

This calls Mix_ReserveChannels and saves n channels for the app.

	$mixer->allocate_channels(n);

If given a number greater than the current number of channels, it will
grow the collection of channels to n.  If n is lower, then it will free
those channels, and remove them.

	$mixer->group_channel(channel,group)

This will add channel to group, which channel and group are both integers.
Similarly,

	$mixer->group_channels(from,to,group)

will add channels from 'from' to 'to' to group 'group'.

	$mixer->group_available(group)

will return the next available channel in a group.

	$mixer->group_count(group)

will return the number of channels in a group, and if group = -1 will
return the total number of channels.

	$mixer->group_oldest(group)

will return the longest playing sample in the group.

	$mixer->group_newer(group)

will return the most recently played sample of a playing group.


	$mixer->play_channel(channel,Sound,loops,[ticks]);
	$mixer->fade_in_channel(channel,Sound,loops,ms,[ticks]);
	$mixer->fade_out_channel(channel,ms);
	$mixer->fade_out_group(group,ms);
	$mixer->channel_expire(channel,ms);
	$mixer->halt(channel);
	$mixer->halt_group(group);
	$mixer->pause(channel);
	$mixer->resume(channel);

	$mixer->fading_channel(channel);
	$mixer->playing(channel);
	$mixer->paused(channel);

Play_channel will play a Sound object 'Sound', on channel 'channel', and 
loop 'loops' times, for optionally at most 'ticks' ticks.  Fade_in_channel
works the same, but fades the sample in over ms milliseconds.  
Fade_out_channel will fade a channel out for ms milliseconds, where as
channel_expire will kill it after ms milliseconds. Halt will kill a
channel immediately, and halt_group works on an entire group.
Pause and resume works as a pair to pause and resume playback of a channel.
Fadding_channel, playing, and paused, all return a value if the channel is 
in that state.

There are a number of similar methods for music.  They work basically
the same way, but as there is only a single music channel, do not require
as many args. They are as follows:

	$mixer->play_music(Music,loops);
	$mixer->fade_in_music(Music,loops,ms);
	$mixer->fade_out_music(ms);
	$mixer->halt_music();
	$mixer->pause_music();
	$mixer->resume_music();

	$mixer->music_paused();
	$mixer->playing_music();
	$mixer->fading_music();

In addition to those, music also has two additional commands:
	
	$mixer->rewind_music();
	$mixer->set_music_command("string");

=head2 Volume Control

	The MIX_MAX_VOLUME is 128.  To set the volume of the music use
the method:
		
	$mixer->music_volume(vol);

Similarly the volume of each channel can be set using:

	$mixer->channel_volume(channel,vol);

For .wav files, the volume of the sample itself can be adjusted as
mentioned above using the 'volume' method of the Sound object.  The
mixer will automagically handle all of the mixing for you.


=head1 AUTHOR 

David J. Goehrig

=head1 SEE ALSO

perl(1) SDL::Cdrom(3)

=cut


