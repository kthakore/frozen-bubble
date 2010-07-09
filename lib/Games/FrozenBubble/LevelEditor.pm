package Games::FrozenBubble::LevelEditor;

use POSIX(qw(floor ceil));
use SDL;
use SDLx::App;
use SDL::Video;
use SDL::Surface;
use SDL::Image;
use SDL::Events;
use SDL::Event;
use SDL::Mouse;
use SDL::Cursor;
use SDL::TTF;
use SDL::TTF::Font;
use SDLx::SFont;
use SDL::Mixer;
use File::Glob qw(bsd_glob);

use Games::FrozenBubble::Stuff;
use Games::FrozenBubble::Symbols;

use strict;
our ($NUM_ROWS, $NUM_BUBBLES_AVAIL,
     $BUBBLES_PER_ROW, $BUBBLE_OPTION_SEPARATION, $BUBBLE_OPTION_INIT_X,
     $ALPHA_BUBBLE_NO, $ALPHA_BUBBLE_YES, $WOOD_WIDTH, $WOOD_PLANK_HEIGHT,
     $LEFT_WOOD_X, $RIGHT_WOOD_X, $BUBBLE_WOOD_Y, $NAV_WOOD_Y, $LEVELSET_WOOD_Y,
     $LEVEL_WOOD_Y, $HELP_WOOD_Y, $colourblind, $app, $font, %bubble_rects, %bubble_hash, $color,
     $action, $previousx, $previousy, $background, $highlight,
     $highlighted_option, $curr_level, $displaying_dialog, $new_ls_name_text, $surface_dialog,
     $levelset_name, $list_browser_file_start_offset, $list_browser_highlight_offset,
     $surf_shrink, %file_browser_levelsets, @file_browser_levelsets_num_levels,
     $deleted_current_levelset, $jump_to_level_value,
     $modified_levelset, $modified_levelset_action, $button_hold, $command_line_fullscreen, %rect, $start_level);

$NUM_ROWS = 10;
$POS_1P{bottom_limit} = $POS_1P{p1}{top_limit} + $NUM_ROWS * $ROW_SIZE;
$NUM_BUBBLES_AVAIL = 8;
$BUBBLES_PER_ROW = 3;
$BUBBLE_OPTION_SEPARATION = 8;
$BUBBLE_OPTION_INIT_X = 18;
$ALPHA_BUBBLE_NO = 0;
$ALPHA_BUBBLE_YES = 1;

$WOOD_WIDTH = 150;
$WOOD_PLANK_HEIGHT = 40;
$LEFT_WOOD_X = 2;
$RIGHT_WOOD_X = 488;
$BUBBLE_WOOD_Y = 33;
$NAV_WOOD_Y = 209;
$LEVELSET_WOOD_Y = 30;
$LEVEL_WOOD_Y = 249;
$HELP_WOOD_Y = 428;

$highlighted_option = '';
$previousx = -1;
$previousy = -1;
$displaying_dialog = '';
$deleted_current_levelset = 0;
$button_hold = 0;


#- ----------- bubbles processing/drawing -----------------------------------------

# subroutine to calculate the left corner x of the given bubble option column (based on 0 start)
sub bubble_optionx {
    my ($col) = @_;
    return $BUBBLE_OPTION_INIT_X + $col * ($BUBBLE_SIZE + $BUBBLE_OPTION_SEPARATION);
}

# subroutine to calculate the left corner y of the given bubble option row (based on 0 start)
sub bubble_optiony {
    my ($row) = @_;
    return $BUBBLE_WOOD_Y + $WOOD_PLANK_HEIGHT + $row * ($BUBBLE_SIZE + $BUBBLE_OPTION_SEPARATION);
}

# subroutine to get the column
sub get_col {
    my ($x, $y) = @_;
    if (even(get_row($y))) {
        return floor(($x-$POS_1P{p1}{left_limit})/$BUBBLE_SIZE);

    } elsif ($POS_1P{p1}{left_limit} + $BUBBLE_SIZE/2 <= $x && $x < $POS_1P{p1}{right_limit} - $BUBBLE_SIZE/2)  {
        return floor(($x-($POS_1P{p1}{left_limit}+$BUBBLE_SIZE/2))/$BUBBLE_SIZE);

    } else {
        return -1;
    }
}

# subroutine to get the row
sub get_row {
    my ($y) = @_;
    return floor(($y-$POS_1P{p1}{top_limit})/$ROW_SIZE);
}

# subroutine to draw bubbles
sub draw_bubble {
    my ($bubbleid, $x, $y, $alpha, $surface_tmp, $ignore_update) = @_;
    my ($bubble);

    $surface_tmp or $surface_tmp = $app;
    $bubble = SDL::Image::load( "$FPATH/gfx/balls/bubble-".($colourblind && 'colourblind-')."$bubbleid.gif");

    $bubble_rects{$x}{$y} = SDL::Rect->new($x,  $y, $bubble->w,  $bubble->h);

    $alpha and SDL::Video::set_alpha($bubble, SDL_SRCALPHA, 0x66);

    SDL::Video::blit_surface($bubble, SDL::Rect->new(0,0,$bubble->w, $bubble->h), $surface_tmp, $bubble_rects{$x}{$y});
    $ignore_update or SDL::Video::update_rects($surface_tmp, $bubble_rects{$x}{$y});

}

# subroutine to erase bubble
sub erase_bubble {
    my ($x, $y) = @_;
    SDL::Video::blit_surface(    $background, $bubble_rects{$x}{$y}, $app, $bubble_rects{$x}{$y});
    #- redraw close bubbles because the rectangular blit of the previous statement erased a bit of them
    my $DISTANCE_CLOSE_SQRED = sqr($BUBBLE_SIZE*1.1);
    foreach my $x_ (keys %bubble_rects) {
        foreach my $y_ (%{$bubble_rects{$x_}}) {
            $y != $y_ && sqr($x-$x_) + sqr($y-$y_) <= $DISTANCE_CLOSE_SQRED or next;
            if ($bubble_hash{$curr_level}{my $col = get_col($x_, $y_)}{my $row = get_row($y_)} =~ /^\d+$/) {
                draw_bubble($bubble_hash{$curr_level}{$col}{$row} + 1, $x_, $y_, $ALPHA_BUBBLE_NO, undef, 1);
            }
        }
    }
    SDL::Video::update_rects($app, $bubble_rects{$x}{$y});
}

# subroutine to place a bubble
sub place_bubble {
    my ($x, $y, $alpha, $button) = @_;
    my $col = get_col($x, $y);
    my $row = get_row($y);
    $y = $row * $ROW_SIZE + $POS_1P{p1}{top_limit};
    if ($col != -1) {
        if (even($row)) {
            $x = get_col($x, $y) * $BUBBLE_SIZE + $POS_1P{p1}{left_limit};
        } else  {
            $x = $col * $BUBBLE_SIZE + $POS_1P{p1}{left_limit} + $BUBBLE_SIZE/2;
        }
        if ($action eq 'erase' || $button == SDL_BUTTON_RIGHT) {  #- when in motion, the right button is reported as button 4 !?
            if (($previousx != $x || $previousy != $y) && $previousx != -1 && $previousy != -1
                && $bubble_hash{$curr_level}{get_col($previousx, $previousy)}{get_row($previousy)} ne '-') {
                draw_bubble($bubble_hash{$curr_level}{get_col($previousx, $previousy)}{get_row($previousy)} + 1,
                            $previousx, $previousy, $ALPHA_BUBBLE_NO);
            }
            if ($bubble_rects{$x}{$y}) {
                if ($alpha && $bubble_hash{$curr_level}{$col}{$row} ne '-') {
                    if ($previousx != $x || $previousy != $y) {
                        erase_bubble($x, $y);
                        draw_bubble($bubble_hash{$curr_level}{$col}{$row} + 1, $x, $y, $alpha);
                    }
                    $previousx = $x;
                    $previousy = $y;
                } else {
                    $bubble_hash{$curr_level}{$col}{$row} = '-';
                    erase_bubble($x, $y);
                }
            }
        } elsif ($action eq 'add') {
            if ($alpha) {
                if ($previousx != $x || $previousy != $y) {
                    if ($previousx != -1 && $previousy != -1) {
                        if ($bubble_hash{$curr_level}{get_col($previousx, $previousy)}{get_row($previousy)} eq '-') {
                            erase_bubble($previousx, $previousy);
                        } else {
                            draw_bubble($bubble_hash{$curr_level}{get_col($previousx, $previousy)}{get_row($previousy)} + 1,
                                        $previousx, $previousy, $ALPHA_BUBBLE_NO);
                        }
                    }
                    draw_bubble($color, $x, $y, $alpha);
                    $previousx = $x;
                    $previousy = $y;
                }
            } else {
                $bubble_hash{$curr_level}{$col}{$row} = $color - 1;
                draw_bubble($color, $x, $y, $alpha);
            }
        }
    }
}


#- ----------- actions routing -----------------------------------------

# subroutine to change my color
sub change_color {
    my ($new_color) = @_;
    $color = $new_color;
    $action = 'add';

    draw_bubble($color,
                $POS_1P{p1}{next_bubble}{x} + $POS_1P{p1}{left_limit},
                $POS_1P{p1}{next_bubble}{y}, $ALPHA_BUBBLE_NO);    #- }}})
}

sub highlight_option {
    my ($option, $x, $y) = @_;

        unhighlight_option($option);
    if ($option ne $highlighted_option) {
        $highlighted_option = $option;
        $option =~ s/bubble-(\d+)/$1/;

        if (0 < $option && $option <= $NUM_BUBBLES_AVAIL) {
                SDL::Video::blit_surface(            $highlight, $rect{bubble_option_highlight}, $app, $bubble_rects{$x}{$y});
                SDL::Video::update_rects($app,$bubble_rects{$x}{$y});

        } elsif ($option eq 'erase') {
                SDL::Video::blit_surface(            $highlight, $rect{bubble_option_highlight}, $app, $rect{erase});
                SDL::Video::update_rects($app,$rect{erase});

        } elsif ($option =~ m/arrow/){
            eval "print_dialog_$option(1)";

        } else {
            eval "print_$option".'_text(1)';
        }
    }

}

sub unhighlight_option {
    # note: will only have x and y for bubbles and erase
    my ($no_highlight) = @_;
    my ($col, $row);

    # don't unhighlight currently highlighted option because it will cause flashing
    if ($highlighted_option ne '' && $highlighted_option ne $no_highlight) {
        $highlighted_option =~ s/bubble-(\d+)/$1/;
        if (0 < $highlighted_option && $highlighted_option <= $NUM_BUBBLES_AVAIL) {
            $col = ($highlighted_option - 1 ) % $BUBBLES_PER_ROW;
            $row = floor(($highlighted_option - 1 ) / $BUBBLES_PER_ROW);

            my $rect = $bubble_rects{bubble_optionx($col)}{bubble_optiony($row)};
            SDL::Video::blit_surface(            $background, $rect, $app, $rect);
            SDL::Video::update_rects($app,$rect);

            add_bubble_option($highlighted_option, $col, $row);

        } elsif ($highlighted_option eq 'erase') {
                SDL::Video::blit_surface(            $background, $rect{erase}, $app, $rect{erase});
                SDL::Video::update_rects($app,$rect{erase});

            add_erase_option();

        } elsif ($highlighted_option =~ m/arrow/) {
            eval "print_dialog_$highlighted_option(0)";

        } else {
            eval "print_$highlighted_option".'_text(0)';
        }

        $highlighted_option = '';
    }

}

# subroutine to decide what my mouse is telling me to do
sub choose_action {
    my ($x, $y, $caller, $button) = @_;

    # are we over the drawing area?
    if ($POS_1P{p1}{left_limit} <= $x && $x < $POS_1P{p1}{right_limit} && $POS_1P{p1}{top_limit} <= $y && $y < $POS_1P{bottom_limit}) {
        if ($caller eq 'motion' && $button_hold == 0) {
            place_bubble($x, $y, $ALPHA_BUBBLE_YES, $button);
        } elsif ($button_hold == 1) {
            place_bubble($x, $y, $ALPHA_BUBBLE_NO, $button);
            $modified_levelset = 1;
        } else { # $caller is 'button'
            place_bubble($x, $y, $ALPHA_BUBBLE_NO, $button);
            $modified_levelset = 1;
        }

    # we will want to remove bubble highlight if we go out of our drawing area
    } elsif ($previousx != -1 && $previousy != -1) {
        if ($bubble_hash{$curr_level}{get_col($previousx, $previousy)}{get_row($previousy)} eq '-') {
            erase_bubble($previousx, $previousy);
        } else {
            draw_bubble($bubble_hash{$curr_level}{get_col($previousx, $previousy)}{get_row($previousy)} + 1,
                        $previousx, $previousy, $ALPHA_BUBBLE_NO);
        }
        # make sure that when we come back into the drawing area, we immediatly start
        # doing our highlights - if we don't do this, you don't get a highlight
        # if you come back to the same spot that you left
        $previousx = -1;
        $previousy = -1;
    }

    # selecting a bubble or erase bubble??
    if ($y >= $BUBBLE_WOOD_Y + $WOOD_PLANK_HEIGHT && $y <= $BUBBLE_WOOD_Y + 4 * $WOOD_PLANK_HEIGHT
        && $x > $BUBBLE_OPTION_INIT_X - $BUBBLE_OPTION_SEPARATION/2
        && $x <= $BUBBLE_OPTION_INIT_X + $BUBBLES_PER_ROW * ($BUBBLE_SIZE + $BUBBLE_OPTION_SEPARATION) - $BUBBLE_OPTION_SEPARATION/2) {
        my $col = ceil(($x - $BUBBLE_OPTION_INIT_X + $BUBBLE_OPTION_SEPARATION/2) / ($BUBBLE_SIZE + $BUBBLE_OPTION_SEPARATION));
        my $row = ceil(($y - ($BUBBLE_WOOD_Y + $WOOD_PLANK_HEIGHT) + $BUBBLE_OPTION_SEPARATION/2) / ($BUBBLE_SIZE + $BUBBLE_OPTION_SEPARATION));

        my $color_tmp = $BUBBLES_PER_ROW * ($row - 1) + $col;
        if (0 < $color_tmp && $color_tmp <= $NUM_BUBBLES_AVAIL) {
            highlight_option("bubble-$color_tmp", bubble_optionx($col - 1), bubble_optiony($row - 1));
            if($caller eq 'button') {
                                change_color($color_tmp);
                        }
        } elsif ($color_tmp == $NUM_BUBBLES_AVAIL + 1) {
            highlight_option('erase');
            if ($caller eq 'button') {
                $action = 'erase';
                erase_bubble($POS_1P{p1}{next_bubble}{x} + $POS_1P{p1}{left_limit}, $POS_1P{p1}{next_bubble}{'y'});
            }
        }

    # check if over navigation options
    } elsif ($LEFT_WOOD_X <= $x && $x <= $WOOD_WIDTH && $rect{prev}->y <= $y && $y <= $rect{last}->y + $rect{last}->h) {
        my @nav_options = ({ name => 'prev',
                             unhighlight => $curr_level == 1,
                             action => sub { if ($curr_level != 1) {
                                                 prev_level();
                                                 $curr_level == 1 and unhighlight_option();
                                             } } },
                           { name => 'next',
                             unhighlight => $curr_level == keys %bubble_hash,
                             action => sub { if ($curr_level != keys %bubble_hash) {
                                                 next_level();
                                                 $curr_level == keys %bubble_hash and unhighlight_option();
                                             } } },
                           { name => 'first',
                             unhighlight => $curr_level == 1,
                             action => sub { if ($curr_level != 1) {
                                                 first_level();
                                                 unhighlight_option();
                                             } } },
                           { name => 'last',
                             unhighlight => $curr_level == keys %bubble_hash,
                             action => sub { if ($curr_level != keys %bubble_hash) {
                                                 last_level();
                                                 unhighlight_option();
                                             } } },
                       );

        foreach (@nav_options) {
            if ($rect{$_->{name}}->y <= $y && $y <= $rect{$_->{name}}->y + $rect{$_->{name}}->h) {
                if ($_->{unhighlight}) {
                    unhighlight_option();
                } else {
                    highlight_option($_->{name});
                }
                $caller eq 'button' and $_->{action}->();
            }
        }

    # check if over levelset options
    } elsif ($RIGHT_WOOD_X <= $x && $x <= $RIGHT_WOOD_X + $WOOD_WIDTH
             && $y >= $rect{ls_new}->y && $y <= $rect{ls_delete}->y + $rect{ls_delete}->h) {
        my @ls_options = ({ name => 'ls_new',    action => sub { create_new_levelset_dialog() } },
                          { name => 'ls_open',   action => sub { create_open_levelset_dialog() } },
                          { name => 'ls_save',   action => sub { save_file() } },
                          { name => 'ls_delete', action => sub { create_delete_levelset_dialog() } });
        foreach (@ls_options) {
            if ($y >= $rect{$_->{name}}->y && $y <= $rect{$_->{name}}->y + $rect{$_->{name}}->h) {
                highlight_option($_->{name});
                $caller eq 'button' and $_->{action}->();
            }
        }

    # check if over level options
    } elsif ($RIGHT_WOOD_X <= $x && $x <= $RIGHT_WOOD_X + $WOOD_WIDTH
             && $y >= $rect{lvl_insert}->y && $y <= $rect{lvl_delete}->y + $rect{lvl_delete}->h) {
        my @lvl_options = ({ name => 'lvl_insert', action => sub { insert_level() } },
                           { name => 'lvl_append', action => sub { append_level() } },
                           { name => 'lvl_delete', action => sub { delete_level(); load_level() } });
        foreach (@lvl_options) {
            if ($y >= $rect{$_->{name}}->y && $y <= $rect{$_->{name}}->y + $rect{$_->{name}}->h) {
                highlight_option($_->{name});
                $caller eq 'button' and $_->{action}->();
            }
        }

    # check if over help
    } elsif ($RIGHT_WOOD_X <= $x && $x <= $RIGHT_WOOD_X + $WOOD_WIDTH
             && $y >= $rect{help}->y && $y <= $rect{help}->y + $rect{help}->h) {

        if ($caller eq 'button') {
            create_help_dialog();
        }
        else {
            highlight_option('help');
        }

    # not over an option so I may need to unhighlight
    } else {
        unhighlight_option();
    }

}

# subroutine to return the list of levelsets in $FBLEVELS
sub get_levelset_list {
        #my @levelsets = sort(my @dummy = all($FBLEVELS));
        my @levelsets = map { $_ =~ s{^.*/(.*)$}{$1}; $_; } sort(bsd_glob("$FBLEVELS/*"));
    $displaying_dialog eq 'ls_delete' and @levelsets = difference2(\@levelsets, [ 'default-levelset' ]);
    return @levelsets;
}

sub betw {
    my ($val, $min, $max) = @_;
    $val > $min && $val < $max;
}

# subroutine to decide what my mouse is telling me to do in the dialog box
sub choose_dialog_action {
    my ($x, $y, $caller, $event) = @_;
    my ($ok_rect, $cancel_rect, $surface_tmp);

    # todo - can we get this info somewhere else in a better way?
    $surface_tmp = SDL::Image::load( "$FPATH/gfx/list_arrow_up.png");

    $rect{middle} = get_dialog_rect();
    # over left button
    if (betw($x, $rect{middle}->x, $rect{middle}->x + $rect{middle}->w/2)
        && betw($y, $rect{middle}->y + 6 * $WOOD_PLANK_HEIGHT, $rect{middle}->y + $rect{middle}->h)) {
        if (member($displaying_dialog, qw(help ls_play ls_play_choose_level ls_nothing_to_delete ls_open_ok_only ls_new_ok_only))) {
            # this dialog does not have a left button. return
            unhighlight_option();
            return 1;
        }

        if ($displaying_dialog eq 'jump') {
            if ( is_ok_jump_value() == 1 ) {
                highlight_option('ok');
            } else {
                unhighlight_option('ok');
                return 1;
            }
        }

        if ($displaying_dialog eq 'ls_new') {
            if ( is_ok_filename() == 1) {
                highlight_option('ok');
            } else {
                unhighlight_option('ok');
                return 1;
            }
        }

        $displaying_dialog ne 'ls_new' and highlight_option('ok');


        if ($caller eq 'button') {
            if ($displaying_dialog eq 'ls_new' && is_ok_filename() == 1) {
                remove_dialog();
                create_new_levelset();
            } elsif ($displaying_dialog eq 'jump' && is_ok_jump_value() == 1) {
                remove_dialog();
                jump_to_level($jump_to_level_value);
            } elsif ($displaying_dialog eq 'ls_open') {
                open_levelset();
            } elsif ($displaying_dialog eq 'ls_delete') {
                delete_levelset();
            } elsif ($displaying_dialog eq 'ls_deleted_current') {
                create_open_levelset_dialog_ok_only();
            } elsif ($displaying_dialog eq 'ls_save_changes') {
                save_file();
                $displaying_dialog = '';
                eval($modified_levelset_action);
            }
        }

        # over right button
    } elsif (betw($x, $rect{middle}->x + $rect{middle}->w/2, $rect{middle}->x + $rect{middle}->w)
             && betw($y, $rect{middle}->y + 6 * $WOOD_PLANK_HEIGHT, $rect{middle}->y + $rect{middle}->h)) {
        if (member($displaying_dialog, qw(help ls_play ls_play_choose_level ls_nothing_to_delete ls_open_ok_only ls_new_ok_only))) {
            if ($displaying_dialog eq 'ls_new_ok_only' && is_ok_filename() == 1) {
                highlight_option('ok_right');
            } else {
                unhighlight_option('ok_right');
            }

            if ($displaying_dialog eq 'ls_nothing_to_delete') {
                highlight_option('ok_right');
                if ($caller eq 'button') {
                    $displaying_dialog = '';
                    remove_dialog();
                }
            }

            $displaying_dialog ne 'ls_new_ok_only' and highlight_option('ok_right');

            if ($caller eq 'button') {
                if ($displaying_dialog eq 'help') {
                    $displaying_dialog = '';
                                remove_dialog();
                }
                if (member($displaying_dialog, qw(ls_play ls_play_choose_level))) {
                    my @levelsets = get_levelset_list();
                    $modified_levelset_action = "return $levelsets[$list_browser_highlight_offset]";
                    return 1;

                } elsif ($displaying_dialog eq 'ls_open_ok_only') {
                    remove_dialog();
                    $displaying_dialog = '';
                    open_levelset();

                } elsif ($displaying_dialog eq 'ls_new_ok_only' && is_ok_filename() == 1) {
                    remove_dialog();
                    create_new_levelset();
                }
            }
        } else {
                # still over right button, but for these dialogs, it is the cancel button
            highlight_option('cancel');
            if ($caller eq 'button') {
                if ($displaying_dialog eq 'ls_open' && $deleted_current_levelset == 1) {
                    remove_dialog();
                    create_deleted_current_levelset_dialog();

                } elsif ($displaying_dialog eq 'ls_deleted_current') {
                    $levelset_name = 'default-levelset';
                    %bubble_hash = read_file($levelset_name);
                    $curr_level = 1;
                    $displaying_dialog = '';
                    remove_dialog();
                    load_level();
                    print_levelset_name();
                    $deleted_current_levelset = 0;

                } elsif ($displaying_dialog eq 'ls_save_changes') {
                    $displaying_dialog = '';
                    eval($modified_levelset_action);

                } else {
                        # all other dialogs
                    remove_dialog();
                }
            }
        }

    } elsif (member($displaying_dialog, qw(ls_open_ok_only ls_open ls_delete ls_play ls_play_choose_level))) {
        if (betw($x, $rect{middle}->x + 4 * $rect{middle}->w/6, $rect{middle}->x + 4 * $rect{middle}->w/6 + $surface_tmp->w)) {
            my @arrows = ($rect{dialog_file_list}->y + 2,
                          $rect{dialog_file_list}->y + $rect{dialog_file_list}->h - $surface_tmp->h - 2);
            if (betw($y, $arrows[0], $arrows[0] + $surface_tmp->h)) {
                $caller eq 'button' and display_levelset_list_browser($list_browser_file_start_offset - 1, $list_browser_highlight_offset);
                highlight_option('list_arrow_up');

            } elsif (betw($y, $arrows[1], $arrows[1] + $surface_tmp->h)) {
                $caller eq 'button' and display_levelset_list_browser($list_browser_file_start_offset + 1, $list_browser_highlight_offset);
                highlight_option('list_arrow_down');

            } else {
                unhighlight_option();
            }
        } elsif (betw($x, $rect{dialog_file_list}->x, $rect{dialog_file_list}->x + $rect{dialog_file_list}->w)
                 && betw($y, $rect{dialog_file_list}->y, $rect{dialog_file_list}->y + $rect{dialog_file_list}->h)) {
            if ($caller eq 'button') {
                if ($y < $rect{dialog_file_list}->y + 25) {
                    display_levelset_list_browser($list_browser_file_start_offset, $list_browser_file_start_offset);
                } elsif ($y < $rect{dialog_file_list}->y + 2 * 25) {
                    display_levelset_list_browser($list_browser_file_start_offset, $list_browser_file_start_offset + 1);
                } elsif ($y < $rect{dialog_file_list}->y + 3 * 25) {
                    display_levelset_list_browser($list_browser_file_start_offset, $list_browser_file_start_offset + 2);
                } else {
                    display_levelset_list_browser($list_browser_file_start_offset, $list_browser_file_start_offset + 3);
                }
                if ($displaying_dialog eq 'ls_play_choose_level') {
                    #- we've potentially selected another level. Make sure the start level
                    #- that was previously selected is valid
                    if (is_ok_select_start_value($start_level) == 0) {
                        #- we're over (since we can't be under) so go to the last
                        #- level in this new set
                        $start_level = $file_browser_levelsets_num_levels[$list_browser_highlight_offset];
                        show_selected_level();
                    }

                }
            }
        } elsif ($displaying_dialog eq 'ls_play_choose_level' && betw($x, 435, 470)) {
            my $more = $x > 452 ? '_more' : '';
            if (betw($y, $rect{middle}->y + 180, $rect{middle}->y + 200)) {
                highlight_option("select_level_arrow_up$more");
                if ($caller eq 'button') {
                    modify_selected_level($event, "up$more");
                }
            } elsif (betw($y, $rect{middle}->y + 202, $rect{middle}->y + 222)) {
                highlight_option("select_level_arrow_down$more");
                if ($caller eq 'button') {
                    modify_selected_level($event, "down$more");
                }
            } else {
                unhighlight_option();
            }
        } else {
            unhighlight_option();
        }
    } else {
        unhighlight_option();
    }
}

# react to user's keyboard and mouse events
sub handle_events {
    my $event = SDL::Event->new;

    while (1) {
            SDL::Events::pump_events();
        if (SDL::Events::poll_event($event) != 0) {

            if ($event->type == SDL_MOUSEMOTION) {
                    #TODO: Change this ->button_x stuff to new api
                if ($displaying_dialog eq '') {
                    choose_action($event->button_x, $event->button_y, 'motion', $event->button_button);  #- , )
                } else {
                    choose_dialog_action($event->button_x, $event->button_y, 'motion');  #- ,, )
                }
                SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);

            } elsif ($event->type == SDL_MOUSEBUTTONDOWN) {
                $button_hold = 1;
                if ($displaying_dialog eq '') {
                    choose_action($event->button_x, $event->button_y, 'button', $event->button_button);  #- , )
                } else {
                    choose_dialog_action($event->button_x, $event->button_y, 'button', $event);  #- ,, )
                }
                SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);

            } elsif ($event->type == SDL_MOUSEBUTTONUP) {
                $button_hold = 0;

            } elsif ($event->type == SDL_KEYDOWN) {
                if ($displaying_dialog eq '') {
                    if ($event->key_sym == SDLK_ESCAPE() || $event->key_sym == SDLK_q() ) {
                        if ($modified_levelset == 1) {
                            $modified_levelset_action = '$modified_levelset_action = "return 1"';
                            create_save_changes_dialog();
                        } else {
                            return 1;
                        }
                    }
                    $event->key_sym == SDLK_LEFT() and prev_level();
                    $event->key_sym == SDLK_RIGHT() and next_level();
                    $event->key_sym == SDLK_UP() and first_level();
                    $event->key_sym == SDLK_DOWN() and last_level();
                    $event->key_sym == SDLK_a() and append_level();
                    $event->key_sym == SDLK_d() and do { delete_level(); Games::FrozenBubble::LevelEditor::load_level() };
                    $event->key_sym == SDLK_f() and $app->fullscreen;
                    $event->key_sym == SDLK_h() and prev_level();
                    $event->key_sym == SDLK_i() and insert_level();
                    $event->key_sym == SDLK_l() and next_level();
                    $event->key_sym == SDLK_n() and next_level();
                    $event->key_sym == SDLK_o() and create_open_levelset_dialog();
                    $event->key_sym == SDLK_p() and prev_level();
                    $event->key_sym == SDLK_s() and save_file();
                    $event->key_sym == SDLK_RIGHTBRACKET() and move_level_right();
                    $event->key_sym == SDLK_LEFTBRACKET() and move_level_left();
                    $event->key_sym == SDLK_F1() and create_help_dialog();
                    $event->key_sym == SDLK_j() and create_jump_to_level_dialog();
                    if ((($highlighted_option eq 'prev' || $highlighted_option eq 'first') && $curr_level == 1)
                        || (($highlighted_option eq 'next' || $highlighted_option eq 'last') && $curr_level == keys %bubble_hash)) {
                        unhighlight_option();
                    }
                } elsif (member($displaying_dialog, qw(ls_new ls_new_ok_only))) {
                    print_new_ls_name($event->key_sym);
                } elsif (member($displaying_dialog, qw(jump))) {
                    print_jump_to_level_value($event->key_sym);
                } elsif ($displaying_dialog eq 'ls_open') {
                    if ($event->key_sym() == SDLK_RETURN() || $event->key_sym() == SDLK_KP_ENTER()) {
                        highlight_option('ok');
                        SDL::delay(200);
                        open_levelset();
                    } elsif ($event->key_sym() == SDLK_ESCAPE()) {
                        highlight_option('cancel');
                        SDL::delay(200);
                        remove_dialog();
                        if ($deleted_current_levelset == 1) {
                            create_deleted_current_levelset_dialog();
                        }
                    } elsif ($event->key_sym() == SDLK_DOWN()) {
                        display_levelset_list_browser($FBLE::list_browser_file_start_offset + 1, $FBLE::list_browser_highlight_offset + 1);
                    } elsif ($event->key_sym() == SDLK_UP()) {
                        display_levelset_list_browser($FBLE::list_browser_file_start_offset - 1, $FBLE::list_browser_highlight_offset - 1);
                    }
                } elsif ($displaying_dialog eq 'ls_open_ok_only') {
                    if ($event->key_sym() == SDLK_RETURN() || $event->key_sym() == SDLK_KP_ENTER()) {
                        highlight_option('ok_right');
                        SDL::delay(200);
                        open_levelset();
                    } elsif ($event->key_sym() == SDLK_DOWN()) {
                        display_levelset_list_browser($FBLE::list_browser_file_start_offset + 1, $FBLE::list_browser_highlight_offset + 1);
                    } elsif ($event->key_sym() == SDLK_UP()) {
                        display_levelset_list_browser($FBLE::list_browser_file_start_offset - 1, $FBLE::list_browser_highlight_offset - 1);
                    }
                } elsif ($displaying_dialog eq 'help') {
                    if ($event->key_sym() == SDLK_RETURN() || $event->key_sym() == SDLK_KP_ENTER()) {
                        highlight_option('ok_right');
                        SDL::delay(200);
                        remove_dialog();
                    }

                } elsif (member($displaying_dialog, qw(ls_play ls_play_choose_level))) {
                    if ($event->key_sym == SDLK_ESCAPE() || $event->key_sym == SDLK_q() ) {
                        $displaying_dialog = '';
                        return;
                    }
                    if ($event->key_sym == SDLK_RETURN() || $event->key_sym == SDLK_KP_ENTER()) {
                        highlight_option('ok_right');
                        SDL::delay(200);
                        my (@levelsets);
                        @levelsets = get_levelset_list();
                        $displaying_dialog = '';
                        my @retval = ($levelsets[$list_browser_highlight_offset], $start_level);
                        return @retval;
                    } elsif ($event->key_sym() == SDLK_DOWN()) {
                        display_levelset_list_browser($FBLE::list_browser_file_start_offset + 1, $FBLE::list_browser_highlight_offset + 1);
                        if (is_ok_select_start_value($start_level) == 0) {
                            #- we're over (since we can't be under) so go to the last
                            #- level in this new set
                            $start_level = $file_browser_levelsets_num_levels[$list_browser_highlight_offset];
                            if ($displaying_dialog eq 'ls_play_choose_level') {
                                show_selected_level();
                            }
                        }
                    } elsif ($event->key_sym() == SDLK_UP()) {
                        display_levelset_list_browser($FBLE::list_browser_file_start_offset - 1, $FBLE::list_browser_highlight_offset - 1);
                        if (is_ok_select_start_value($start_level) == 0) {
                            #- we're over (since we can't be under) so go to the last
                            #- level in this new set
                            $start_level = $file_browser_levelsets_num_levels[$list_browser_highlight_offset];
                            if ($displaying_dialog eq 'ls_play_choose_level') {
                                show_selected_level();
                            }
                        }
                    } elsif ($event->key_sym() == SDLK_LEFT()) {
                        modify_selected_level($event, 'down');
                    } elsif ($event->key_sym() == SDLK_RIGHT()) {
                        modify_selected_level($event, 'up');
                    }

                } elsif ($displaying_dialog eq 'ls_delete') {
                    if ($event->key_sym() == SDLK_RETURN() || $event->key_sym() == SDLK_KP_ENTER()) {
                        highlight_option('ok');
                        SDL::delay(200);
                        delete_levelset();
                    } elsif ($event->key_sym() == SDLK_ESCAPE()) {
                        highlight_option('cancel');
                        SDL::delay(200);
                        remove_dialog();
                    } elsif ($event->key_sym() == SDLK_DOWN()) {
                        display_levelset_list_browser($FBLE::list_browser_file_start_offset + 1, $FBLE::list_browser_highlight_offset + 1);
                    } elsif ($event->key_sym() == SDLK_UP()) {
                        display_levelset_list_browser($FBLE::list_browser_file_start_offset - 1, $FBLE::list_browser_highlight_offset - 1);
                    }
                } elsif ($displaying_dialog eq 'ls_deleted_current') {
                    if ($event->key_sym() == SDLK_RETURN() || $event->key_sym() == SDLK_KP_ENTER() ) {
                        highlight_option('ok');
                        SDL::delay(200);
                        remove_dialog();
                        create_open_levelset_dialog_ok_only();
                    } elsif ($event->key_sym() == SDLK_ESCAPE()) {
                        highlight_option('cancel');
                        SDL::delay(200);
                        $levelset_name = 'default-levelset';
                        %bubble_hash = read_file($levelset_name);
                        $curr_level = 1;
                        $displaying_dialog = '';
                        remove_dialog();
                        load_level();
                        print_levelset_name();
                        $deleted_current_levelset = 0;
                    }
                } elsif ($displaying_dialog eq 'ls_nothing_to_delete') {
                    if ($event->key_sym() == SDLK_RETURN() || $event->key_sym() == SDLK_KP_ENTER()) {
                        highlight_option('ok_right');
                        SDL::delay(200);
                        $displaying_dialog = '';
                        remove_dialog();
                    }
                } elsif ($displaying_dialog eq 'ls_save_changes') {
                    if ($event->key_sym() == SDLK_RETURN() || $event->key_sym() == SDLK_KP_ENTER() ) {
                        highlight_option('ok');
                        SDL::delay(200);
                        save_file();
                        $displaying_dialog = '';
                        eval($modified_levelset_action);
                    } elsif ($event->key_sym() == SDLK_ESCAPE()) {
                        highlight_option('cancel');
                        SDL::delay(200);
                        $displaying_dialog = '';
                        eval($modified_levelset_action);
                    }
                }

                SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);

            } elsif ($event->type == SDL_QUIT) {
                if ($displaying_dialog eq '') {
                    if ($modified_levelset == 1) {
                        $modified_levelset_action = '$modified_levelset_action = "return 1"';
                        create_save_changes_dialog();
                        SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);
                    } else {
                        return 1;
                    }
                }
            }

            if ($modified_levelset_action =~ /return (\S*)/ && $displaying_dialog ne 'ls_save_changes') {
                $modified_levelset_action = '';
                if ($displaying_dialog eq 'ls_play_choose_level') {
                    #- hokey, but I have to return an array here
                    $displaying_dialog = '';
                    return ($1, $start_level);
                } else {
                    $displaying_dialog = '';
                    return $1;
                }
            }

        } else {
            SDL::delay(1);
        }

    }
}


#- ----------- dialogs -----------------------------------------

# subroutine to get the rect where the promt will go
sub get_dialog_rect {
    SDL::Rect->new( $background->w/2 - $surface_dialog->w/2,
                    $background->h/2 - $surface_dialog->h/2,
                    $surface_dialog->w,  $surface_dialog->h);
}

sub create_dialog_base {
    my ($title_text) = @_;

    unhighlight_option();
    if ($displaying_dialog eq 'help') {
        $surface_dialog = SDL::Image::load( "$FPATH/gfx/key_shortcuts.png");
    } else {
        $surface_dialog = SDL::Image::load( "$FPATH/gfx/menu/void_panel.png");
    }
    $rect{dialog} = SDL::Rect->new(0, 0, $surface_dialog->w,  $surface_dialog->h);
    $rect{middle} = get_dialog_rect();

    SDL::Video::blit_surface(    $surface_dialog, $rect{dialog}, $app, $rect{middle});

    SDLx::SFont::print_text(   $app,$rect{middle}->x + $rect{middle}->w/2 - 12 * length($title_text)/2, $rect{middle}->y + 5, uc($title_text));

}

# sub to create a blank dialog on the screen
sub create_dialog {
    my ($title_text) = @_;
    create_dialog_base($title_text);
    print_cancel_text(0);
    print_ok_text(0);

}

sub remove_dialog {
    $rect{middle} = SDL::Rect->new( $background->w/2 - $surface_dialog->w/2,
                                    $background->h/2 - $surface_dialog->h/2,
                                    $surface_dialog->w, $surface_dialog->h);
                           SDL::Video::blit_surface(    $background, $rect{middle}, $app, $rect{middle});
                           SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);

    # update the screen
    load_level();
    $displaying_dialog = '';
}

# subroutine to ask the user what to do if they delete the current levelset
sub create_deleted_current_levelset_dialog {
    $displaying_dialog = 'ls_deleted_current';
    $deleted_current_levelset = 1;
    create_dialog('DELETED CURRENT LEVELSET');
    $rect{middle} = get_dialog_rect();
    SDLx::SFont::print_text(   $app,$rect{middle}->x + 25, $rect{middle}->y + 15 + $WOOD_PLANK_HEIGHT, "PRESS \"OK\" TO CHOOSE");

    SDLx::SFont::print_text(   $app,$rect{middle}->x + 25, $rect{middle}->y + 35 + $WOOD_PLANK_HEIGHT, "ANOTHER LEVELSET TO OPEN");

    SDLx::SFont::print_text(   $app,$rect{middle}->x + 25, $rect{middle}->y + 3 * $WOOD_PLANK_HEIGHT, "PRESS \"CANCEL\" TO OPEN");

    SDLx::SFont::print_text(   $app,$rect{middle}->x + 25, $rect{middle}->y + 25 + 3* $WOOD_PLANK_HEIGHT, "THE DEFAULT LEVELSET");


}

# subroutine to create a delete levelset dialog
sub create_delete_levelset_dialog {
    if (all($FBLEVELS) > 1) {
        $displaying_dialog = 'ls_delete';
        create_dialog('SELECT LEVELSET TO DELETE');
        $list_browser_highlight_offset = -1;
        $list_browser_file_start_offset = -1;
        display_levelset_list_browser(0, 0);
    } else {
        $displaying_dialog = 'ls_nothing_to_delete';
        create_ok_dialog('NO LEVELSET TO DELETE');
        $rect{middle} = get_dialog_rect();
        SDLx::SFont::print_text(       $app,$rect{middle}->x + 50, $rect{middle}->y + 30 + $WOOD_PLANK_HEIGHT, "THERE ARE NO CUSTOM");

        SDLx::SFont::print_text(       $app,$rect{middle}->x + 50, $rect{middle}->y + 55 + $WOOD_PLANK_HEIGHT, "LEVELSETS TO DELETE.");

        SDLx::SFont::print_text(       $app,$rect{middle}->x + 40, $rect{middle}->y + 125 + $WOOD_PLANK_HEIGHT, "PRESS \"OK\" TO CONTINUE");

    }
}


#subroutine to display the help dialog.
sub create_help_dialog {
    $displaying_dialog = 'help';
    create_ok_dialog("HELP - KEY SHORTCUTS");
}


# subroutine to create a jump to level diaplog. This dialog asks the user what level they want to go directly to
sub create_jump_to_level_dialog {
    $jump_to_level_value = '';
    $displaying_dialog = 'jump';
    create_dialog("ENTER LEVEL TO JUMP TO");
}

# subroutine to create a new levelset dialog. This dialog asks for the name of the new levelset
sub create_new_levelset_dialog {
    if ($modified_levelset == 1) {
        $modified_levelset_action = 'create_new_levelset_dialog_ok_only()';
        create_save_changes_dialog();
    } else {
        $displaying_dialog = 'ls_new';
        # create the blank dialog with the title of "enter new levelset name"
        create_dialog('ENTER NEW LEVELSET NAME');
        # inialize the new levelset name
        $new_ls_name_text = '';
    }

}

sub create_new_levelset_dialog_ok_only {
    $displaying_dialog = 'ls_new_ok_only';
    create_ok_dialog('ENTER NEW LEVELSET NAME');
    $new_ls_name_text = '';
}

# sub to create a blank dialog on the screen
sub create_ok_dialog {
    my ($title_text) = @_;
    create_dialog_base($title_text);
    print_ok_right_text(0);

}

sub create_open_levelset_dialog {
    $start_level = undef;
    if ($modified_levelset == 1) {
        $modified_levelset_action = 'create_open_levelset_dialog_ok_only()';
        create_save_changes_dialog();
    } else {
        $displaying_dialog = 'ls_open';
        create_dialog('SELECT LEVELSET TO OPEN');
        $list_browser_highlight_offset = -1;
        $list_browser_file_start_offset = -1;
        display_levelset_list_browser(0,0);
    }
}

sub create_open_levelset_dialog_ok_only {

    $displaying_dialog = 'ls_open_ok_only';
    create_ok_dialog('SELECT LEVELSET TO OPEN');
    $list_browser_highlight_offset = -1;
    $list_browser_file_start_offset = -1;
    display_levelset_list_browser(0,0);

}

sub iter_rowscols(&) {
    my ($f) = @_;
    local ($::row, $::col);
    foreach $::row (0 .. $NUM_ROWS - 1) {
        foreach $::col (0 .. ($POS_1P{p1}{right_limit}-$POS_1P{p1}{left_limit})/$BUBBLE_SIZE - 1 - odd($::row)) {
            &$f;
        }
    }
}

sub save_file {
        my @contents;
        foreach my $lev (1 .. keys %bubble_hash) {
                iter_rowscols {
                        if ($::col == 0) {
                                ($lev == 1 && $::row == 0) or push @contents, "\n";
                                odd($::row) and push @contents, "  ";
                        }
                        push @contents, "$bubble_hash{$lev}{$::col}{$::row}";
                        $::col+odd($::row) < 7 and push @contents, "   ";
                };
                push @contents, "\n";
        }
        output("$FBLEVELS/$levelset_name", @contents);
        $modified_levelset = 0;
}

sub create_play_levelset_dialog {
    my ($chooseStartingLevel, $defaultLevel) = @_;

    #initialize the start level to the default level
    #this is only modified in ls_play_choose_level dialogs
    #but it is always referenced
    $start_level = $defaultLevel;

    #we do the check for $chooseStartingLevel twice because create_ok_dialog
    #needs to know the displaying levelset but display_level_selector
    #needs things that are set up in display_levelset_list_browser
    if ($chooseStartingLevel ==1 ) {
        $displaying_dialog = 'ls_play_choose_level';
    } else {
        $displaying_dialog = 'ls_play';
    }

    create_ok_dialog('SELECT LEVELSET TO PLAY');
    $list_browser_highlight_offset = -1;
    $list_browser_file_start_offset = -1;
    display_levelset_list_browser(0, 0);
    if ($chooseStartingLevel == 1) {
        display_level_selector();
    }
}


sub create_save_changes_dialog {
    $modified_levelset = 0;
    #reset the modified levelset flag
    $displaying_dialog = 'ls_save_changes';
    create_dialog('SAVE CHANGES?');

    $rect{middle} = get_dialog_rect();

    # write out the instructions
    SDLx::SFont::print_text(   $app,$rect{middle}->x + 25, $rect{middle}->y + $WOOD_PLANK_HEIGHT, 'THERE ARE UNSAVED CHANGES');

    SDLx::SFont::print_text(   $app,$rect{middle}->x + 22, $rect{middle}->y + 35 + $WOOD_PLANK_HEIGHT, "PRESS \"OK\" TO SAVE");

    SDLx::SFont::print_text(   $app,$rect{middle}->x + 22, $rect{middle}->y + 55 + $WOOD_PLANK_HEIGHT, "CHANGES AND CONTINUE");

    SDLx::SFont::print_text(   $app,$rect{middle}->x + 22, $rect{middle}->y + 95 + $WOOD_PLANK_HEIGHT, "PRESS \"CANCEL\" TO CONTINUE");

    SDLx::SFont::print_text(   $app,$rect{middle}->x + 22, $rect{middle}->y + 115 + $WOOD_PLANK_HEIGHT, "WITHOUT SAVING");

}

sub display_level_selector {

    $rect{middle} = get_dialog_rect();
    SDLx::SFont::print_text(   $app,$rect{middle}->x + 15, $rect{middle}->y + 190, "START LEVEL:");

    SDL::Video::update_rects($app,$rect{middle});

    show_selected_level();
    print_dialog_select_level_arrow(0, 'down');
    print_dialog_select_level_arrow(0, 'up');
    print_dialog_select_level_arrow(0, 'down_more');
    print_dialog_select_level_arrow(0, 'up_more');
}

sub is_ok_modify_selected_level {
    my ($modification) = @_;

    if ($modification =~ /up/ && is_ok_select_start_value($start_level + 1)
        || $modification =~ /down/ && is_ok_select_start_value($start_level - 1)) {
        return 1;
    } else {
        return 0;
    }
}

sub modify_selected_level {

    my ($event, $modification) = @_;
    my $loops = 0;


    #loop until we get a keyup or a mouse up
    while (1) {
            SDL::Events::pump_events();
        if ( SDL::Events::poll_event($event) == 0 ) {
            if (is_ok_modify_selected_level($modification)) {
                if ($modification eq 'up') {
                    $start_level++;
                }
                if ($modification eq 'down') {
                    $start_level--;
                }
                if ($modification eq 'up_more') {
                    if (is_ok_select_start_value($start_level + 10)) {
                        $start_level += 10;
                    } else {
                        $start_level = $file_browser_levelsets_num_levels[$list_browser_highlight_offset];
                    }
                }
                if ($modification eq 'down_more') {
                    if (is_ok_select_start_value($start_level - 10)) {
                        $start_level -= 10;
                    } else {
                        $start_level = 1;
                    }
                }
                show_selected_level();

                #- need to unhighlight when we got at one extremity
                if ($modification =~ /up/ && $start_level == $file_browser_levelsets_num_levels[$list_browser_highlight_offset]
                    || $modification =~ /down/ && $start_level == 1) {
                    unhighlight_option();
                }

            }

                        #no change in the event, delay and then try again
            if ($loops <= 5) {
                                #special case here. If the user hits the keys fast, we need
                                #to compensate for that. delay 100 and then check the key again
                                #if it has changed, just exit. Otherwise, they're holding the
                                #key down and we follow the logic as usual
                SDL::delay(100);
                SDL::Events::pump_events();
                if ( SDL::Events::poll_event($event) == 0 || $event->type == SDL_MOUSEMOTION) { #mousemotion is when they are
                    #holding the mouse key down and
                    #jiggle it's position a litte bit
                    SDL::delay(300);
                } else {
                    goto done;
                }

            } elsif ($loops <= 10) {
                SDL::delay(150);

            } elsif ($loops <= 20) {
                SDL::delay(80);

            } else {
                SDL::delay(35);
            }

            $loops++;

        } else {
            if ($event->type == SDL_MOUSEMOTION) {
                #let them move the mouse around in the arrow that's already highlighted

                my $x = $event->button_x;
                my $y = $event->button_y;  #;;

                #if I'm outside of the x range, just exit
                if (!betw($x, 435, 470)) {
                    goto done;
                }

                if ($modification =~ /up/) {
                    if ( !betw($y, $rect{middle}->y + 180, $rect{middle}->y + 200) ) {
                        goto done;
                    }
                } else {
                    if ( !betw($y, $rect{middle}->y + 202, $rect{middle}->y + 222) ) {
                        goto done;
                    }
                }

            } else {
                goto done;
            }
        }
    }

  done:

}

#- from gentoo patch IIRC
sub SDL_TEXTWIDTH {
    if (defined(&SDLx::App::SDL_TEXTWIDTH)) {
        SDLx::App::SDL_TEXTWIDTH(@_);   # perl-sdl-1.x
    } else {
        SDLx::SFont::SDL_TEXTWIDTH(@_); # perl-sdl-2.x
    }
}


sub show_selected_level {
    my $surf_select_level_background
      = SDL::Image::load( "$FPATH/gfx/select_level_background.png");

    $rect{select_level_background_src}
      = SDL::Rect->new(0, 0, $surf_select_level_background->w,
                      $surf_select_level_background->h);

    $rect{select_level_background_dest}
      = SDL::Rect->new( 305,
                       $rect{middle}->y + 190,  #==
                        $rect{select_level_background_src}->w,
                        $rect{select_level_background_src}->h);

               SDL::Video::blit_surface(    $surf_select_level_background, $rect{select_level_background_src}, $app, $rect{select_level_background_dest});

    #now write the selected level
    $font = SDLx::SFont->new("$FPATH/gfx/font-hi.png");
    SDLx::SFont::print_text(   $app,427 - SDL_TEXTWIDTH($start_level), $rect{middle}->y + 190, $start_level);

    $font = SDLx::SFont->new("$FPATH/gfx/font.png");

    SDL::Video::update_rects($app,$rect{select_level_background_dest});

    display_levelset_screenshot();
}


# subroutine to display to the user a list of levelsets and allow them
# to browse through and select one of them.
sub display_levelset_list_browser {
    my ($file_start_offset, $file_highlight_offset) = @_;
    my ($surf_file_list_background, $surf_purple_highlight, $surf_scroll_list_background, $cnt);

    my @levelsets = get_levelset_list();
    my $do_scroll = $file_start_offset != $list_browser_file_start_offset;

    if ($file_highlight_offset > @levelsets - 1
        || $file_highlight_offset == $list_browser_highlight_offset && !$do_scroll) {
        # this is the case where the user either clicks on the same
        # file that is already selected, or clicks in the file box, but
        # not on a file (for example, the user click on the second
        # file section when only one file is displayed
        return;
    }

    # we can display 4 files. If the offset makes us print less than 1, ignore it
    # also, make sure we don't let an offset of less than 0 go through
    if ($file_start_offset < @levelsets && $file_start_offset >= 0) {
        # save the current file offset
        $list_browser_file_start_offset = $file_start_offset;
    } else {
        # we don't need to draw anything. just exit
        return;
    }

        $rect{middle}              = get_dialog_rect();
        #I want the font to be blue in the dialogs
        $font                      = SDLx::SFont->new("$FPATH/gfx/font-hi.png");
        $surf_file_list_background = SDL::Image::load( "$FPATH/gfx/file_list_background.png");
        $rect{list_box_src}        = SDL::Rect->new(0,0, $surf_file_list_background->w, 3 * $WOOD_PLANK_HEIGHT);

    # if the user is choosing the start level, we need to move things up a little bit to make
    # room for the choose level widget
    my $widgetMove = 0;
    if ($displaying_dialog eq 'ls_play_choose_level') {
        $widgetMove = -25;
    }
    $rect{dialog_file_list} = SDL::Rect->new($rect{middle}->x + 9,  $rect{middle}->y + $WOOD_PLANK_HEIGHT + 37 + $widgetMove,
                                              $rect{list_box_src}->w,  $rect{list_box_src}->h);

    $surf_purple_highlight = SDL::Image::load( "$FPATH/gfx/purple_hover.gif");

    $rect{purple_highlight_src} = SDL::Rect->new(0,0, $surf_purple_highlight->w, $surf_purple_highlight->h);

    # we only want to draw the arrows and background here once, when we first get launched
    if ($list_browser_highlight_offset == -1) {
        $surf_scroll_list_background = SDL::Image::load("$FPATH/gfx/scroll_list_background.png");

        $rect{scroll_list_background_src} = SDL::Rect->new(0,0, $surf_scroll_list_background,
                                                            3 * $WOOD_PLANK_HEIGHT);

        $rect{scroll_list_background_dest} = SDL::Rect->new( $rect{dialog_file_list}->x + $rect{dialog_file_list}->w,
                                                             $rect{dialog_file_list}->y,
                                                             $rect{scroll_list_background_src}->w,
                                                             $rect{scroll_list_background_src}->h);

                                                    SDL::Video::blit_surface(        $surf_scroll_list_background, $rect{scroll_list_background_src}, $app, $rect{scroll_list_background_dest});
                                                    SDL::Video::update_rects($app,$rect{scroll_list_background_dest});

        print_dialog_list_arrow_down(0);
        print_dialog_list_arrow_up(0);
    }

    if ($do_scroll == 1) {
            SDL::Video::blit_surface(        $surf_file_list_background, $rect{list_box_src}, $app, $rect{dialog_file_list});
            SDL::Video::update_rects($app,$rect{dialog_file_list});

        for ($cnt = $file_start_offset; $cnt < $file_start_offset + 4; $cnt++) {
            if ($file_highlight_offset == $cnt) {
                $rect{purple_highlight_dest}
                  = SDL::Rect->new( $rect{middle}->x + 12,
                                    $rect{dialog_file_list}->y + 10 + 25 * ($cnt - $file_start_offset),
                                    $surf_purple_highlight->w,  $surf_purple_highlight->h);

                           SDL::Video::blit_surface(                $surf_purple_highlight, $rect{purple_highlight_src}, $app, $rect{purple_highlight_dest});
                           SDL::Video::update_rects($app,$rect{purple_highlight_dest});
            }
            SDLx::SFont::print_text(           $app,$rect{middle}->x + 19, $rect{dialog_file_list}->y + 8 + 25 * ($cnt - $file_start_offset),

                        uc($levelsets[$cnt]));
        }
    } else {
        # erase the old highlight
        $rect{old_highlight} = SDL::Rect->new(
            $rect{middle}->x + 12,
             $rect{dialog_file_list}->y + 10 + 25 * ($list_browser_highlight_offset - $list_browser_file_start_offset),
             $surf_purple_highlight->w,  $surf_purple_highlight->h);

        $rect{erase_highlight} = SDL::Rect->new(
             $rect{old_highlight}->x - $rect{dialog_file_list}->x,
             $rect{old_highlight}->y - $rect{dialog_file_list}->y,
             $surf_purple_highlight->w,  $surf_purple_highlight->h);

        # it is possible that the highlighed dude is off the screen. In this case, do not
        # call the blit, because there is no visible highlight to remove
        if ($list_browser_highlight_offset >= $list_browser_file_start_offset
            && $list_browser_highlight_offset <= $list_browser_file_start_offset + 3) {
            SDL::Video::blit_surface(            $surf_file_list_background, $rect{erase_highlight}, $app, $rect{old_highlight});
            SDL::Video::update_rects($app,$rect{old_highlight});
            # draw the text of the old highligted dude
            SDLx::SFont::print_text(           $app,$rect{middle}->x + 19,

                        $rect{dialog_file_list}->y + 8 + 25 * ($list_browser_highlight_offset - $list_browser_file_start_offset),
                        uc($levelsets[$list_browser_highlight_offset]));
        }

        # draw the highlight
        $rect{purple_highlight_dest} = SDL::Rect->new(
            $rect{middle}->x + 12,
             $rect{dialog_file_list}->y + 10 + 25 * ($file_highlight_offset - $file_start_offset),
             $surf_purple_highlight->w,
            $surf_purple_highlight->h);
    SDL::Video::blit_surface(        $surf_purple_highlight, $rect{purple_highlight_src}, $app, $rect{purple_highlight_dest});
    SDL::Video::update_rects($app,$rect{purple_highlight_dest});
    SDLx::SFont::print_text( $app,$rect{middle}->x + 19,

                    $rect{dialog_file_list}->y + 8 + 25 * ($file_highlight_offset - $file_start_offset),
                    uc($levelsets[$file_highlight_offset]));

    }

    # set the unhighlight so the app thinks nothing's highlighted and will highlight
    # the correct item in the next highlight function call
    unhighlight_option();

    SDL::Video::update_rects($app,$rect{middle});

    if ($file_highlight_offset != $list_browser_highlight_offset) {
        if ($list_browser_highlight_offset == -1) {
            $list_browser_highlight_offset = 0;

            %file_browser_levelsets = ();
            @file_browser_levelsets_num_levels = ();
            my @levelset_list = get_levelset_list();
            foreach my $levelset (@levelset_list) {
                my %levelset = read_file($levelset);
                $file_browser_levelsets{$levelset} = \%levelset;
                push @file_browser_levelsets_num_levels, scalar keys %levelset;
            }
        }
        $list_browser_highlight_offset = $file_highlight_offset;
        display_levelset_screenshot();
    } else {
        $list_browser_highlight_offset = $file_highlight_offset;
    }

    #reset the font back to white
    $font = SDLx::SFont->new("$FPATH/gfx/font.png");
    SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);
}

our $surfstyle;
sub surf {
    my ($surface) = @_;
    $surfstyle ||= UNIVERSAL::isa($surface, 'HASH') ? 'hashref' : 'scalarref';
    return $surfstyle eq 'hashref' ? $surface->{-surface} : $$surface;
}
sub rect {
    my ($rect) = @_;
    return $surfstyle eq 'hashref' ? $rect->{-rect} : $$rect;
}

my $s_save; 
# display a scrrenshot (1/4 size) of the first level in a levelset on the current dialog
sub display_levelset_screenshot {
        my @levelsets     = get_levelset_list();
        my $name          = $levelsets[$list_browser_highlight_offset];
        $rect{middle}     = get_dialog_rect();
        $rect{screenshot} = SDL::Rect->new($POS_1P{p1}{left_limit}  - 40, 0,
                                           $POS_1P{p1}{right_limit} - $POS_1P{p1}{left_limit} + 80,
                                           $POS_1P{bottom_limit}    - $POS_1P{p1}{top_limit} + 190);
        # if the user is choosing the start level, we need to move things up a little bit to make
        # room for the choose level widget
        my $widgetMove    = ($displaying_dialog eq 'ls_play_choose_level') ? -25 : 0;
        my $x             = $rect{middle}->x + $rect{middle}->w   - $rect{screenshot}->w/4 - 12;
        my $y             = $rect{middle}->y + $rect{middle}->h/2 - $rect{screenshot}->h/8 - 3 + $widgetMove;

    my %shrinks;
    my $current_nb = $start_level || 1;
    if (!exists $shrinks{$name}{$current_nb}) {
                my $surf = SDL::Image::load("$FPATH/gfx/menu/please_wait.png");
                SDL::Video::blit_surface($surf, SDL::Rect->new(0,0, $surf->w,  $surf->h),
                                         $app,  SDL::Rect->new($rect{scroll_list_background_dest}->x + $rect{scroll_list_background_dest}->w + 7,
                                                               $rect{scroll_list_background_dest}->y + 20,
                                                               $surf->w,  $surf->w));
                SDL::Video::update_rects($app,$rect{middle});

        #- sorta "read ahead": will compute next 10 levels screenshots as well
                $s_save = SDL::Image::load( "$FPATH/gfx/level_editor.png") unless $s_save;
        #- don't read-ahead if $start_level is void because it
        #- indicates we're just selecting a levelset in the editor
        my @read_ahead = $start_level ? ($current_nb - 10, $current_nb - 3 .. $current_nb + 10, $current_nb + 20)
                                      : ($current_nb);
                foreach my $nb (@read_ahead) {
                        next if $nb < 1 || exists $shrinks{$name}{$nb};
                        my %ls = %{$file_browser_levelsets{$name}};
                        last if !exists $ls{$nb};
                        my $s    = SDL::Surface->new(SDL_SWSURFACE, $s_save->w, $s_save->h, 32);
                        my $rect = SDL::Rect->new(0, 0, $app->w, $app->h);
                        SDL::Video::blit_surface($s_save, $rect, $s, $rect);
                        load_level($s, $nb, %ls);
                        $shrinks{$name}{$nb} = SDL::Surface->new(SDL_SWSURFACE, $rect{screenshot}->w / 4, $rect{screenshot}->h / 4, 32);
                        Games::FrozenBubble::CStuff::shrink($shrinks{$name}{$nb}, $s, 0, 0, $rect{screenshot}, 4);
                }
        }

        if(defined $shrinks{$name}{$current_nb})
        {
                my $image = $shrinks{$name}{$current_nb};
                SDL::Video::blit_surface($image, SDL::Rect->new(0, 0, $image->w, $image->h),
                                         $app, SDL::Rect->new($x, $y, $image->w, $image->h));
                SDL::Video::update_rects($app,$rect{middle});
        }
}


#- ----------- levels and levelsets operations ------------------------------------------

# subroutine load_level
sub load_level {
    my ($surface_tmp, $curr_lvl, %b) = @_;

    if (!$surface_tmp) {
        $curr_lvl = $curr_level;
        %b = %bubble_hash;
        clear_level();
        print_level_nb();
    }

    iter_rowscols {
        my $bub = \$b{$curr_lvl}{$::col}{$::row};
        defined($$bub) or $$bub = '-';  #- sanitize
        if ($$bub ne '-') {
            draw_bubble($$bub + 1,
                        $::col * $BUBBLE_SIZE + $POS_1P{p1}{left_limit} + odd($::row)*$BUBBLE_SIZE/2,
                        $::row * $ROW_SIZE + $POS_1P{p1}{top_limit},
                        $ALPHA_BUBBLE_NO, $surface_tmp, undef, 1);
        }
    };

    SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);
}

# subroutine to clear level off the screen
sub clear_level {
    $rect{clear} = SDL::Rect->new( $POS_1P{p1}{left_limit}, $POS_1P{p1}{top_limit},
                                   $POS_1P{p1}{right_limit} - $POS_1P{p1}{left_limit},
                                   $POS_1P{bottom_limit} - $POS_1P{p1}{top_limit} + $BUBBLE_SIZE
                                  );

                           SDL::Video::blit_surface(    $background, $rect{clear}, $app, $rect{clear});
}

sub delete_level {

    delete $bubble_hash{$curr_level};

    if ($curr_level - 1 == keys %bubble_hash) {
        $curr_level--;
        if ($curr_level == 0) {
            append_level();
        }
    } else {
        foreach my $lev ($curr_level .. keys %bubble_hash) {
            $bubble_hash{$lev} = $bubble_hash{$lev + 1};
        }

        delete $bubble_hash{keys %bubble_hash};
    }

    $modified_levelset = 1;
}

# subroutine to actually create a new levelset
sub create_new_levelset {

    $levelset_name = lc($new_ls_name_text);

    %bubble_hash = ();
    $curr_level = 0;
    append_level();

    print_levelset_name();
    load_level();
    $modified_levelset = 0;
}

# subroutine to delete a levelset
sub delete_levelset {

    my @levelsets = get_levelset_list();
    my $lvs_name = $levelsets[$list_browser_highlight_offset];
    unlink "$FBLEVELS/$lvs_name" or die "Can't remove $FBLEVELS/$lvs_name\n";
    remove_dialog();

    $levelset_name eq $lvs_name and create_deleted_current_levelset_dialog();
}

# this subroutine is mostly copied from frozen-bubble
sub read_file {
    my ($file_name) = @_;

    my $row = 0;
    my $lev_number = 1;
    my %tmp_hash;
    foreach my $line (cat_("$FBLEVELS/$file_name")) {
        if ($line !~ /\S/) {
            if ($row) {
                $lev_number++;
                $row = 0;
            }
        } else {
            my $col = 0;
            foreach (split ' ', $line) {
                $tmp_hash{$lev_number}{$col}{$row} = $_;
                $col++;
            }
            $row++;
        }
    }

    return %tmp_hash;

}

# subroutine to open the levelset
sub open_levelset {
    my (@levelsets);
    # reset the deleted_current_levelset flag in case
    # we were in that situation

    $deleted_current_levelset = 0;
    @levelsets = get_levelset_list();

    $levelset_name = $levelsets[$list_browser_highlight_offset];
    %bubble_hash = read_file($levelset_name);
    print_levelset_name();
    $curr_level = 1;
    remove_dialog();
    $modified_levelset = 0;
}


#- ----------- navigation in a levelset ------------------------------------------

sub prev_level {
    $curr_level > 1 and $curr_level--;
    load_level();
}

sub next_level {
    $curr_level < keys %bubble_hash and $curr_level++;
    load_level();
}

sub first_level {
    $curr_level = 1;
    load_level();
}

sub last_level {
    $curr_level = keys %bubble_hash;
    load_level();
}

sub jump_to_level {
    my ($n) = @_;
    if ($n >= 1 && $n <= keys %bubble_hash) {
        $curr_level = $_[0];
        load_level();
    }
}

sub insert_level {
    for (my $lev = 1 + keys %bubble_hash; $lev > $curr_level; $lev--) {
        $bubble_hash{$lev} = $bubble_hash{$lev - 1};
    }

    delete $bubble_hash{$curr_level};

    # initialize our new level
    iter_rowscols { $bubble_hash{$curr_level}{$::col}{$::row} = '-' };

    load_level();
    $modified_levelset = 1;
}

sub append_level {
    $curr_level++;
    insert_level();
}

sub move_level_left {
    $curr_level > 1 or return;
    ($bubble_hash{$curr_level-1}, $bubble_hash{$curr_level}) = ($bubble_hash{$curr_level}, $bubble_hash{$curr_level-1});
    $curr_level--;
    load_level();
    $modified_levelset = 1;
}

sub move_level_right {
    $curr_level < keys(%bubble_hash) or return;
    ($bubble_hash{$curr_level+1}, $bubble_hash{$curr_level}) = ($bubble_hash{$curr_level}, $bubble_hash{$curr_level+1});
    $curr_level++;
    load_level();
    $modified_levelset = 1;
}


#- ----------- printing stuff ------------------------------------------

sub print_cancel_text {
    my ($do_highlight) = @_;

    if ($displaying_dialog ne '') {
        $rect{middle} = get_dialog_rect();

        $rect{cancel_src} = SDL::Rect->new( $rect{middle}->w - $rect{option_highlight}->w,
                                            6 * $WOOD_PLANK_HEIGHT - 4,
                                            $rect{middle}->w/2, $WOOD_PLANK_HEIGHT);

        $rect{cancel} = SDL::Rect->new( $rect{middle}->x + $rect{middle}->w - $rect{option_highlight}->w,
                                        $rect{middle}->y + 6 * $WOOD_PLANK_HEIGHT - 4,
                                       $rect{middle}->w/2, $WOOD_PLANK_HEIGHT);

                               SDL::Video::blit_surface(        $surface_dialog, $rect{cancel_src}, $app, $rect{cancel});
                               SDL::Video::update_rects($app,$rect{cancel});

                               SDLx::SFont::print_text(       $app,$rect{middle}->x + $rect{middle}->w - 120, $rect{middle}->y + 6 * $WOOD_PLANK_HEIGHT, 'CANCEL');

        if ($do_highlight) {
                SDL::Video::blit_surface(            $highlight, $rect{option_highlight}, $app, $rect{cancel});
                SDL::Video::update_rects($app,$rect{cancel});
        }
    }
}

sub print_dialog_list_arrow {
    my ($do_highlight, $type) = @_;

    $rect{middle} = get_dialog_rect();

    my $surf_list_arrow = SDL::Image::load( "$FPATH/gfx/list_arrow_$type.png");
    $rect{list_arrow_src} = SDL::Rect->new( 0, 0, $surf_list_arrow->w, $surf_list_arrow->h);
    $rect{list_arrow_dest} = SDL::Rect->new(
                     $rect{middle}->x + 4 * $rect{middle}->w/6 + 2,
                     $type eq 'up' ? $rect{dialog_file_list}->y + 2
                                          : $rect{dialog_file_list}->y + $rect{dialog_file_list}->h - $surf_list_arrow->h - 2,
                     $surf_list_arrow->w,  $surf_list_arrow->h);

    my $surf_scroll_list_background = SDL::Image::load( "$FPATH/gfx/scroll_list_background.png");
    $rect{erase_arrow} = SDL::Rect->new( $rect{list_arrow_dest}->x - $rect{scroll_list_background_dest}->x,
                                         $rect{list_arrow_dest}->y - $rect{scroll_list_background_dest}->y,
                                         $surf_list_arrow->w,  $surf_list_arrow->h);

                                SDL::Video::blit_surface(    $surf_scroll_list_background, $rect{erase_arrow}, $app, $rect{list_arrow_dest});
                                SDL::Video::update_rects($app,$rect{list_arrow_dest});

    SDL::Video::blit_surface(    $surf_list_arrow, $rect{list_arrow_src}, $app, $rect{list_arrow_dest});
    SDL::Video::update_rects($app,$rect{list_arrow_dest});

    if ($do_highlight) {
            SDL::Video::blit_surface(        $highlight, $rect{list_arrow_src}, $app, $rect{list_arrow_dest});
            SDL::Video::update_rects($app,$rect{list_arrow_dest});
    }
}


sub print_dialog_select_level_arrow {
    my ($do_highlight, $type, $more) = @_;
    $rect{middle} = get_dialog_rect();

    my $surf_list_arrow = SDL::Image::load( "$FPATH/gfx/list_arrow_$type.png");
    $rect{list_arrow_src} = SDL::Rect->new(0,0, $surf_list_arrow->w,  $surf_list_arrow->h);
    my $x = $type =~ /more/ ? 457 : 437;
    $rect{list_arrow_dest} = SDL::Rect->new(
                     $x,
                     $type =~ /up/ ? $rect{middle}->y + 180
                                          : $rect{middle}->y + 202,
                    $surf_list_arrow->w,  $surf_list_arrow->h);

    my $surf_arrow_background = SDL::Image::load( "$FPATH/gfx/menu/void_panel.png");
    $rect{erase_arrow} = SDL::Rect->new( $x - $rect{middle}->x,
                                         $type =~ /up/ ? 180  : 202,
                                         $surf_list_arrow->w, $surf_list_arrow->h);

                                SDL::Video::blit_surface(    $surf_arrow_background, $rect{erase_arrow}, $app, $rect{list_arrow_dest});
                                SDL::Video::update_rects($app,$rect{list_arrow_dest});

    SDL::Video::blit_surface(    $surf_list_arrow, $rect{list_arrow_src}, $app, $rect{list_arrow_dest});
    SDL::Video::update_rects($app,$rect{list_arrow_dest});

    if ($do_highlight && is_ok_modify_selected_level($type)) {
            SDL::Video::blit_surface(        $highlight, $rect{list_arrow_src}, $app, $rect{list_arrow_dest});
            SDL::Video::update_rects($app,$rect{list_arrow_dest});
    }
}

sub print_dialog_select_level_arrow_down {
    my ($do_highlight) = @_;
    print_dialog_select_level_arrow($do_highlight, 'down');
}

sub print_dialog_select_level_arrow_up {
    my ($do_highlight) = @_;
    print_dialog_select_level_arrow($do_highlight, 'up');
}

sub print_dialog_select_level_arrow_down_more {
    my ($do_highlight) = @_;
    print_dialog_select_level_arrow($do_highlight, 'down_more');
}

sub print_dialog_select_level_arrow_up_more {
    my ($do_highlight) = @_;
    print_dialog_select_level_arrow($do_highlight, 'up_more');
}

sub print_dialog_list_arrow_down {
    my ($do_highlight) = @_;
    print_dialog_list_arrow($do_highlight, 'down');
}

sub print_dialog_list_arrow_up {
    my ($do_highlight) = @_;
    print_dialog_list_arrow($do_highlight, 'up');
}

# subroutine to print out the levelset name at the top of the screen
sub print_levelset_name {
    $rect{ls_name_erase} = SDL::Rect->new( 195,  0,  445-195,  35);
    SDL::Video::blit_surface(    $background, $rect{ls_name_erase}, $app, $rect{ls_name_erase});
    SDLx::SFont::print_text(    $app,($background->w - SDL_TEXTWIDTH(uc($levelset_name)))/2 - 6, 7, uc($levelset_name));

    SDL::Video::update_rects($app, SDL::Rect->new(0,0,$app->w, $app->h) );
}

sub print_text_generic {
    my ($do_highlight, $name, $xpos, $ypos, $text) = @_;

    SDL::Video::blit_surface($background, $rect{$name}, $app, $rect{$name});
    SDL::Video::update_rects($app,$rect{$name});

    SDLx::SFont::print_text(  $app,$xpos, $ypos, $text || uc($name));

    if ($do_highlight) {
            SDL::Video::blit_surface(        $highlight, $rect{option_highlight}, $app, $rect{$name});
            SDL::Video::update_rects($app,$rect{$name});
    }
}

sub print_first_text {
    print_text_generic($_[0], 'first', $WOOD_WIDTH/2, $rect{first}->y + 6);
}

sub print_last_text {
    print_text_generic($_[0], 'last', 20, $rect{last}->y + 6);
}

sub print_prev_text {
    print_text_generic($_[0], 'prev', $WOOD_WIDTH/2, $rect{prev}->y + 6);
}

sub print_next_text {
    print_text_generic($_[0], 'next', 20, $rect{next}->y + 6);
}

sub print_ls_delete_text {
    print_text_generic($_[0], 'ls_delete', $rect{ls_delete}->x + 12, $rect{ls_delete}->y + 6, 'DELETE');
}

sub print_ls_new_text {
    print_text_generic($_[0], 'ls_new', $rect{ls_new}->x + $WOOD_WIDTH/2, $rect{ls_new}->y + 6, 'NEW');
}

sub print_ls_open_text {
    print_text_generic($_[0], 'ls_open', $rect{ls_open}->x + 35, $rect{ls_open}->y + 6, 'OPEN');
}

sub print_ls_save_text {
    print_text_generic($_[0], 'ls_save', $rect{ls_save}->x + $WOOD_WIDTH/2, $rect{ls_save}->y + 6, 'SAVE');
}

sub print_lvl_append_text {
    print_text_generic($_[0], 'lvl_append', $rect{lvl_append}->x + 20, $rect{lvl_append}->y + 6, 'APPEND');
}

sub print_lvl_delete_text {
    print_text_generic($_[0], 'lvl_delete', $rect{lvl_delete}->x + $WOOD_WIDTH/2, $rect{lvl_delete}->y + 6, 'DELETE');
}

sub print_lvl_insert_text {
    print_text_generic($_[0], 'lvl_insert', $rect{lvl_insert}->x + $WOOD_WIDTH/2 - 5, $rect{lvl_insert}->y + 6, 'INSERT');
}

sub print_help_text {
        print_text_generic($_[0], 'help', $rect{help}->x + 20, $rect{help}->y + 6, 'HELP!');
}

# filename is OK == not blank or pre-existing
sub is_ok_filename {
    length($new_ls_name_text) == 0 and return 0;

    lc($new_ls_name_text) eq lc($_) and return 0 foreach get_levelset_list();

    return 1;
}


# subroutine to determine if the entered jump to level value is OK
sub is_ok_jump_value {
    if (length($jump_to_level_value) == 0 || $jump_to_level_value == 0 || $jump_to_level_value > keys %bubble_hash) {
        return 0;
    } else {
        return 1;
    }

}

sub is_ok_select_start_value {

    my ($proposed_level) = @_;
    if ($proposed_level >= 1 && $proposed_level <= $file_browser_levelsets_num_levels[$list_browser_highlight_offset]) {
        return 1;
    } else {
        return 0;
    }

}

# subroutine to get the letter pressed by the user on the keyboard
# this subroutine is taken from frozen-bubble code
sub keysym_to_char($) {
    my ($key) = @_;
    my $name = SDL::Events::get_key_name($key);
    return uc($name) if $name;
    eval "$key eq SDLK_$_" and return uc($_) foreach @Games::FrozenBubble::Symbols::syms;
}


sub print_jump_to_level_value {

    my ($key) = @_;
    if ($key == SDLK_ESCAPE()) {
        highlight_option('cancel');
        SDL::delay(200);
        remove_dialog();
    } elsif (($key == SDLK_RETURN() || $key == SDLK_KP_ENTER()) && length($jump_to_level_value) > 0 ) {
        highlight_option('ok');
        SDL::delay(200);
        remove_dialog();
        jump_to_level($jump_to_level_value);
    } elsif ($key == SDLK_BACKSPACE() || ($key >= SDLK_0() && $key <= SDLK_9()) || ( $key >= SDLK_KP0() && $key <= SDLK_KP9())) {
        #- translate keypad values to real values
        if ($key >= SDLK_KP0() && $key <= SDLK_KP9()) {
            foreach (0..9) {
                if (eval("$key == SDLK_KP$_()")) {
                    $key = eval("SDLK_$_()");
                }
            }
        }
        # first erase the previous words
        $rect{dialog_blank} = SDL::Rect->new(0, 2 * $WOOD_PLANK_HEIGHT,
                                              $surface_dialog->w,
                                              $surface_dialog->h - 3 * $WOOD_PLANK_HEIGHT);
        $rect{dialog_new} = SDL::Rect->new( $background->w/2 - $surface_dialog->w/2,
                                            $background->h/2 - $surface_dialog->h/2 + 2 * $WOOD_PLANK_HEIGHT,
                                            $surface_dialog->w,
                                            $surface_dialog->h - 3*$WOOD_PLANK_HEIGHT);
                                   SDL::Video::blit_surface(        $surface_dialog, $rect{dialog_blank}, $app, $rect{dialog_new});
                                   SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);
        if ($key == SDLK_BACKSPACE()) {
            chop $jump_to_level_value;
        } else {
            #- adjust the value, but then check to make sure its a valid value
            $jump_to_level_value .= keysym_to_char($key);
            if (!is_ok_jump_value()) {
                chop $jump_to_level_value;
                unhighlight_option();
            }
        }

        SDLx::SFont::print_text(     $app,$rect{dialog_new}->x + $rect{dialog_new}->w/2 - 12 * length($jump_to_level_value)/2, 210, $jump_to_level_value);

    }
}

# subroutine to print the name of the new levelset in the dialog
sub print_new_ls_name {
    my ($key) = @_;
    if ($key == SDLK_ESCAPE()) {
        if ($displaying_dialog eq 'ls_new') {
            highlight_option('cancel');
            SDL::delay(200);
            remove_dialog();
        }
    } elsif (($key == SDLK_RETURN() || $key == SDLK_KP_ENTER()) && length($new_ls_name_text) > 0 && is_ok_filename() ) {
        if ($displaying_dialog eq 'ls_new') {
            highlight_option('ok');
        } elsif ($displaying_dialog eq 'ls_new_ok_only') {
            highlight_option('ok_right');
        }
        SDL::delay(200);
        remove_dialog();
        create_new_levelset();
    } elsif ($key == SDLK_BACKSPACE()
             || (length($new_ls_name_text) < 14 && ($key == SDLK_KP_MINUS()
                                                    || $key >= SDLK_KP0() && $key <= SDLK_KP9()
                                                    || $key >= SDLK_a() && $key <= SDLK_z()
                                                    || $key == SDLK_MINUS()
                                                    || $key >= SDLK_0 && $key <= SDLK_9()))) {
        # first erase the previous words
        $rect{dialog_blank} = SDL::Rect->new(0,  2 * $WOOD_PLANK_HEIGHT,
                                             $surface_dialog->w,
                                              $surface_dialog->h - 3 * $WOOD_PLANK_HEIGHT);
        $rect{dialog_new} = SDL::Rect->new( $background->w/2 - $surface_dialog->w/2,
                                            $background->h/2 - $surface_dialog->h/2 + 2 * $WOOD_PLANK_HEIGHT,
                                            $surface_dialog->w,
                                            $surface_dialog->h - 3*$WOOD_PLANK_HEIGHT);
                                   SDL::Video::blit_surface(        $surface_dialog, $rect{dialog_blank}, $app, $rect{dialog_new});
                                   SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);
        if ($key == SDLK_BACKSPACE()) {
            chop $new_ls_name_text;
        } elsif ($key == SDLK_MINUS() || $key == SDLK_KP_MINUS()) {
            $new_ls_name_text .= '-';
        } elsif ($key >= SDLK_KP0() && $key <= SDLK_KP9()) {
            my $kp_num;
            eval("SDLK_KP$_() eq $key") and $new_ls_name_text .= $_ foreach 0..9;
        } else {
            $new_ls_name_text .= keysym_to_char($key);
        }
        SDLx::SFont::print_text(       $app,$rect{dialog_new}->x + $rect{dialog_new}->w/2 - 12 * length($new_ls_name_text)/2, 210, $new_ls_name_text);

    }

    # if the filename is bad, unhighlight any option that is highlighted since
    # they can't do anything...
    is_ok_filename() == 0 and unhighlight_option();

}

# subroutine to print the ok text on the right side of the dialog
sub print_ok_right_text {
    my ($do_highlight) = @_;
    if ($displaying_dialog ne '') {
        $rect{middle} = get_dialog_rect();

        $rect{cancel_src} = SDL::Rect->new( $rect{middle}->w - $rect{option_highlight}->w,
                                            6 * $WOOD_PLANK_HEIGHT - 4,
                                            $rect{middle}->w/2,
                                            $WOOD_PLANK_HEIGHT);

        $rect{cancel} = SDL::Rect->new( $rect{middle}->x + $rect{middle}->w - $rect{option_highlight}->w,
                                        $rect{middle}->y + 6 * $WOOD_PLANK_HEIGHT - 4,
                                        $rect{middle}->w/2,
                                        $WOOD_PLANK_HEIGHT);

                               SDL::Video::blit_surface(        $surface_dialog, $rect{cancel_src}, $app, $rect{cancel});
                               SDL::Video::update_rects($app,$rect{cancel});

                               SDLx::SFont::print_text(       $app,$rect{middle}->x + $rect{middle}->w - 80, $rect{middle}->y + 6 * $WOOD_PLANK_HEIGHT, 'OK');

        if ($do_highlight) {
                SDL::Video::blit_surface(            $highlight, $rect{option_highlight}, $app, $rect{cancel});
                SDL::Video::update_rects($app,$rect{cancel});
        }
    }
}

sub print_ok_text {
    my ($do_highlight) = @_;

    if ($displaying_dialog ne '') {
        $rect{middle} = get_dialog_rect();

        $rect{ok_src} = SDL::Rect->new(0,  6 * $WOOD_PLANK_HEIGHT - 4,
                                        $rect{middle}->w/2,
                                        $WOOD_PLANK_HEIGHT);

        $rect{ok} = SDL::Rect->new( $rect{middle}->x,
                                    $rect{middle}->y + 6 * $WOOD_PLANK_HEIGHT - 4,
                                    $rect{middle}->w/2,
                                    $WOOD_PLANK_HEIGHT);

                           SDL::Video::blit_surface(        $surface_dialog, $rect{ok_src}, $app, $rect{ok});
                           SDL::Video::update_rects($app,$rect{ok});

                           SDLx::SFont::print_text(       $app,$rect{middle}->x + 60, $rect{middle}->y + 6 * $WOOD_PLANK_HEIGHT, 'OK');

        if ($do_highlight) {
                SDL::Video::blit_surface(            $highlight, $rect{option_highlight}, $app, $rect{ok});
                SDL::Video::update_rects($app,$rect{ok});
        }
    }
}

sub print_level_nb {
    my $posx = 183;
    my $posy = 421;
    my $level_sign_rect = SDL::Rect->new($posx - 50,  $posy,  100,  25);
    SDL::Video::blit_surface(    $background, $level_sign_rect, $app, $level_sign_rect);
    my $text = "$curr_level/" . keys %bubble_hash;
    SDLx::SFont::print_text(   $app,$posx - 12 * length($text)/2, $posy, $text);

    SDL::Video::update_rects($app,$level_sign_rect);
}


#- ----------- initialization stuff ------------------------------------------

# subroutine to add specific bubble option
sub add_bubble_option {
    my ($bubble_id, $col, $row) = @_;
    draw_bubble($bubble_id, bubble_optionx($col), bubble_optiony($row), $ALPHA_BUBBLE_NO);
}

# subroutine to add the bubble options
sub add_bubble_options {
    my ($count, $col_count);
    # add my list of bubbles on the left
    $count = 0;

    while ($count < $NUM_BUBBLES_AVAIL) {
        $col_count = 0;
        while ($col_count < $BUBBLES_PER_ROW && $count < $NUM_BUBBLES_AVAIL) {
            add_bubble_option($count + 1, $col_count, floor($count/$BUBBLES_PER_ROW));
            $col_count++;
            $count++;
        }
    }

    if ($col_count >= $BUBBLES_PER_ROW) {
        $col_count = 0;
    }

}

# subroutine to add the erase option
sub add_erase_option {
    my $erase = SDL::Image::load("$FPATH/gfx/balls/stick_effect_6.png");
    SDL::Video::blit_surface( $erase,  SDL::Rect->new(0,0,$erase->w, $background->h), $app, $rect{erase});
    SDL::Video::update_rects( $app, $rect{erase});
}

# subroutine to do the initial setup
sub init_setup {
    my ($application_caller, $sdlapp) = @_;

    init_app($application_caller, $sdlapp);

    SDL::Video::blit_surface($background, SDL::Rect->new(0,0,$background->w, $background->h), $app, $rect{background});
    SDL::Video::update_rects( $app, $rect{background});

    add_bubble_options();
    add_erase_option();

    # set font
    $font = SDLx::SFont->new("$FPATH/gfx/font.png");
    SDLx::SFont::print_text(   $app,5, $BUBBLE_WOOD_Y + 3, 'CHOOSE BUBBLE');


    # add navigation words
    SDLx::SFont::print_text(   $app,20, $NAV_WOOD_Y + 8,'NAVIGATION');

    print_prev_text(0);
    print_next_text(0);
    print_first_text(0);
    print_last_text(0);

    # add levelset words
    SDLx::SFont::print_text(   $app,$RIGHT_WOOD_X + 30, $LEVELSET_WOOD_Y + 8, 'LEVELSET');

    print_ls_new_text(0);
    print_ls_open_text(0);
    print_ls_save_text(0);
    print_ls_delete_text(0);

    # add level words
    SDLx::SFont::print_text(   $app,$RIGHT_WOOD_X + 45, $LEVEL_WOOD_Y + 8, 'LEVEL');

    print_lvl_insert_text(0);
    print_lvl_append_text(0);
    print_lvl_delete_text(0);

    # add help words
    print_help_text(0);

    # add initial bubble to draw
    change_color(1);

    $modified_levelset = 0;
    -d "$FBLEVELS" or mkdir "$FBLEVELS" or die "Can't create $FBLEVELS directory.\n";
    -f "$FBLEVELS/default-levelset" or cp_af("$FPATH/data/levels", "$FBLEVELS/default-levelset");

    %bubble_hash = read_file($levelset_name);

    # if inputted level is > the number of levels than reset current level to 1
    $curr_level > keys %bubble_hash and $curr_level = 1;
    load_level();

    SDL::Mouse::warp_mouse(320, 240);

    print_levelset_name();
    SDL::Video::update_rect($app, 0 , 0, $app->w, $app->h);

    $button_hold = 0;
}

# subroutine to initialize the application
sub init_app {
    my ($application_caller, $sdlapp) = @_;
    my @rcfile_data;

    $app = $sdlapp;
    # we only want to check to see if we're in full screen if we're
    # running as a stand alone app. If we're running embedded in the
    # game, we'll use whatever is already set up
    if ($application_caller eq 'stand-alone') {
        @rcfile_data = cat_("$FBHOME/rc");

        if ($command_line_fullscreen == 1) {
            $app->fullscreen;
        } elsif ($rcfile_data[0] eq "\$fullscreen = 1;\n") {
            $app->fullscreen;
        }
    } else {
        # we need to set the default levelset name to "default-levelset"
        $levelset_name = 'default-levelset';
        $curr_level = 1;
    }

    $font = SDLx::SFont->new("$FPATH/gfx/font.png");

    # background image
    $background = SDL::Image::load( "$FPATH/gfx/level_editor.png");

    my @allrects =
     ({ name => 'background', width => $background->w, height => $background->h },
      # bubble wood rectangle (without heading part)
      { name => 'bubble_wood', x => $LEFT_WOOD_X, 'y' => $BUBBLE_WOOD_Y + $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT * ($NUM_BUBBLES_AVAIL + 1)/$BUBBLES_PER_ROW },
      { name => 'erase', x => bubble_optionx($NUM_BUBBLES_AVAIL % $BUBBLES_PER_ROW),
        'y' => bubble_optiony(floor($NUM_BUBBLES_AVAIL / $BUBBLES_PER_ROW)),
        width => $BUBBLE_SIZE, height => $BUBBLE_SIZE },

      # navigation rectangles
      { name => 'prev', x => $LEFT_WOOD_X, 'y' => $NAV_WOOD_Y + $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },
      { name => 'next', x => $LEFT_WOOD_X, 'y' => $NAV_WOOD_Y + 2 * $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },
      { name => 'first', x => $LEFT_WOOD_X, 'y' => $NAV_WOOD_Y + 3 * $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },
      { name => 'last', x => $LEFT_WOOD_X, 'y' => $NAV_WOOD_Y + 4 * $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },

      # levelset rectangles
      { name => 'ls_new', x => $RIGHT_WOOD_X, 'y' => $LEVELSET_WOOD_Y + $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },
      { name => 'ls_open', x => $RIGHT_WOOD_X, 'y' => $LEVELSET_WOOD_Y + 2 * $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },
      { name => 'ls_save', x => $RIGHT_WOOD_X, 'y' => $LEVELSET_WOOD_Y + 3 * $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },
      { name => 'ls_delete', x => $RIGHT_WOOD_X, 'y' => $LEVELSET_WOOD_Y + 4 * $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },

      # level rectangles
      { name => 'lvl_insert', x => $RIGHT_WOOD_X, 'y' => $LEVEL_WOOD_Y + $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },
      { name => 'lvl_append', x => $RIGHT_WOOD_X, 'y' => $LEVEL_WOOD_Y + 2 * $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },
      { name => 'lvl_delete', x => $RIGHT_WOOD_X, 'y' => $LEVEL_WOOD_Y + 3 * $WOOD_PLANK_HEIGHT,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT },

      # help rectangle
      { name => 'help', x => $RIGHT_WOOD_X, 'y' => $HELP_WOOD_Y,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT},

      { name => 'bubble_option_highlight', x => 0, 'y' => 0,
        width => $BUBBLE_SIZE, height => $BUBBLE_SIZE },
      { name => 'option_highlight', x => 0, 'y' => 0,
        width => $WOOD_WIDTH, height => $WOOD_PLANK_HEIGHT }
      );

    $rect{$_->{name}} = SDL::Rect->new( $_->{x}, $_->{'y'}, $_->{width}, $_->{height}) foreach @allrects;

    $highlight = SDL::Image::load("$FPATH/gfx/hover.gif");
    SDL::Video::set_alpha($highlight, SDL_SRCALPHA, 0x44);
}


1;

__END__

=encoding UTF-8

=head1 Frozen-Bubble Level Editor

Copyright © 2002 - 2003 Kim Joham and David Joham <[k|d]joham@yahoo.com>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License version 2, as
published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

Design & Programming by Kim Joham and David Joham, October 2002 - May 2003

Integration to Frozen-Bubble by Guillaume Cottenceau - change a few styles
things, fix a few bugs, add a few features
