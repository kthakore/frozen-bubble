#!/usr/bin/perl

# For faster multiple execs, start a gimp, and do Xtns/Perl/Server.

# Warning! Error message are the worst ever. Unquote the "set_trace" if you need troubleshooting.


$ARGV[0] && -r $ARGV[0] && $ARGV[1] && !$ARGV[2] or
  die "Usage: create <base_image> <number_steps_each_side>\n";


#- (gc) this shit wasted me something like 2 hours: opposedly to what's
#- claimed in the doc, we need to precise `:auto' in the imports, grrrrr..
use Gimp qw(:consts main xlfd_size :auto);

Gimp::init();
#Gimp::set_trace(TRACE_ALL);

print "Using base file <$ARGV[0]> with <$ARGV[1]> steps each side.\n";

$| = 1;

my $data;


sub rot {
    my ($filename, $step, $max) = @_;

    my $img;
    eval { $img = gimp_file_load($filename, $filename) };
    if ($@) {
	die "Failed to load <$filename> into a Gimp image ($@).\n";
    }

    my $w = gimp_image_width($img);
    my $h = gimp_image_height($img);
    
    my $rot = gimp_rotate(gimp_image_active_drawable($img), 1, 3.1415926535897932384626433832795028841972/2 * (-$step)/$max);
    
    #- dunno why, interactive "rotate" keeps same width/height, this one not.. this is beautiful
    gimp_crop($img, $w, $h, 0, 0);
    
    $filename =~ s/\.([^\.]+)/_$step.$1/;

    #- now we want to crop the image a maximum, to reduce time of drawing in the game
    my @pixels = gimp_drawable_get_pixel($rot, $w-1, $h-1);

    #- since I need to know which shift this crop produced, first I forbid croping right and bottom...
    gimp_drawable_set_pixel($rot, $w-1, $h-1, 4, [255, 255, 255, 255]);
    plug_in_autocrop($img, $rot);

    #- ...and I measure shift...
    $data .= sprintf "$step %d %d\n", $w-gimp_image_width($img), $h-gimp_image_height($img);
    
    #- ...and now I can finally crop the rest of the image
    gimp_drawable_set_pixel($rot, gimp_image_width($img)-1, gimp_image_height($img)-1, 4, \@pixels);
    plug_in_autocrop($img, $rot);

    gimp_file_save($img, $rot, $filename, $filename);
}


foreach my $step (0..$ARGV[1]) {
    print ".";
    rot($ARGV[0], $step, $ARGV[1]);
    print ".";
    rot($ARGV[0], -$step, $ARGV[1]);
}

open DAT, ">data" or fail_with_message("Can't open data for writing.");
print DAT $data;
close DAT;

print "done.\n";

Gimp::end();

