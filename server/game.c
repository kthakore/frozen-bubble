/*******************************************************************************
 *
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2, as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *
 ******************************************************************************/

/*
 * this file holds game operations: create, join, list etc.
 * it should be as far away as possible from network operations
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
#include <sys/socket.h>

#include <glib.h>

#include "net.h"
#include "tools.h"
#include "log.h"
#include "game.h"

#define MAX_PLAYERS_PER_GAME 5

enum game_status { GAME_STATUS_OPEN, GAME_STATUS_STARTING, GAME_STATUS_PLAYING };

struct game
{
        enum game_status status;
        int players_number;
        int players_conn[MAX_PLAYERS_PER_GAME];
        char* players_nick[MAX_PLAYERS_PER_GAME];
        int players_starting[MAX_PLAYERS_PER_GAME];
};

static GList * games = NULL;
static GList * open_players = NULL;

static ssize_t amount_transmitted = 0;

static char ok_pong[] = "PONG";
static char ok_player_joined[] = "JOINED: %s";
static char ok_player_parted[] = "PARTED: %s";
static char ok_talk[] = "TALK: %s";
static char ok_start[] = "START: %s";
static char ok_stop[] = "STOP: %s";
static char ok_can_start[] = "GAME_CAN_START: %s";
static char ok_status_open[] = "STATUS_OPEN";

static char wn_unknown_command[] = "UNKNOWN_COMMAND";
static char wn_missing_arguments[] = "MISSING_ARGUMENTS";
static char wn_nick_in_use[] = "NICK_IN_USE";
static char wn_no_such_game[] = "NO_SUCH_GAME";
static char wn_game_full[] = "GAME_FULL";
static char wn_already_in_game[] = "ALREADY_IN_GAME";
static char wn_not_in_game[] = "NOT_IN_GAME";
static char wn_alone_in_the_dark[] = "ALONE_IN_THE_DARK";
static char wn_already_started[] = "ALREADY_STARTED";
static char wn_not_started[] = "NOT_STARTED";

static char fl_line_unrecognized[] = "MISSING_FB_PROTOCOL_TAG";
static char fl_proto_mismatch[] = "INCOMPATIBLE_PROTOCOL";

#ifdef DEBUG
static void show_games_aux(gpointer data, gpointer user_data)
{
        const struct game* g = data;
        int i;
        printf("game:%p;status:%s;nbplayers:%d[",
               g,
               g->status == GAME_STATUS_OPEN ? "open" : g->status == GAME_STATUS_PLAYING ? "playing" : g->status == GAME_STATUS_STARTING ? "starting" : "???",
               g->players_number);
        for (i = 0; i < g->players_number; i++) {
                if (g->status == GAME_STATUS_STARTING) {
                        printf("%d-%s-%s", g->players_conn[i], g->players_nick[i], g->players_starting[i] ? "starting" : "chatting");
                } else {
                        printf("%d-%s", g->players_conn[i], g->players_nick[i]);
                }
                if (i < g->players_number - 1)
                        printf(",");
        }
        printf("]\n");
}
void show_games(void)
{
        g_list_foreach(games, show_games_aux, games);
}
#endif

// calculate the list of players for a given game
static char* list_game(const struct game * g)
{
        char list_game_str[8192] = "";
        int i;
        for (i = 0; i < g->players_number; i++) {
                strncat(list_game_str, g->players_nick[i], sizeof(list_game_str));
                if (i < g->players_number - 1)
                        strncat(list_game_str, ",", sizeof(list_game_str));
        }
        return memdup(list_game_str, strlen(list_game_str) + 1);
}

static char list_games_str[8192] __attribute__((aligned(4096))) = "";
static int players_in_game;
static void list_games_aux(gpointer data, gpointer user_data)
{
        const struct game* g = data;
        char* game;
        if (g->status != GAME_STATUS_OPEN) {
                players_in_game += g->players_number;
                return;
        }
        strncat(list_games_str, "[", sizeof(list_games_str));
        game = list_game(g);
        strncat(list_games_str, game, sizeof(list_games_str));
        free(game);
        strncat(list_games_str, "]", sizeof(list_games_str));
}
void calculate_list_games(void)
{
        char * free_players;
        memset(list_games_str, 0, strlen(list_games_str));
        players_in_game = 0;
        g_list_foreach(games, list_games_aux, NULL);
        free_players = asprintf_(" free:%d", conns_nb() - players_in_game - 1);  // 1: don't count myself
        strncat(list_games_str, free_players, sizeof(list_games_str));
        free(free_players);
}

static void create_game(int fd, char* nick)
{
        struct game * g = malloc(sizeof(struct game));
        g->players_number = 1;
        g->players_conn[0] = fd;
        g->players_nick[0] = nick;
        g->status = GAME_STATUS_OPEN;
        games = g_list_append(games, g);
        calculate_list_games();
        open_players = g_list_remove(open_players, GINT_TO_POINTER(fd));
}

static int add_player(struct game * g, int fd, char* nick)
{
        char joined_msg[1000];
        int i;
        if (g->players_number < MAX_PLAYERS_PER_GAME) {
                /* inform other players */
                snprintf(joined_msg, sizeof(joined_msg), ok_player_joined, nick);
                for (i = 0; i < g->players_number; i++)
                        send_line_log_push(g->players_conn[i], joined_msg);

                g->players_conn[g->players_number] = fd;
                g->players_nick[g->players_number] = nick;
                g->players_number++;
                calculate_list_games();
                open_players = g_list_remove(open_players, GINT_TO_POINTER(fd));
                return 1;
        } else {
                return 0;
        }
}

static int find_game_by_nick_aux(gconstpointer game, gconstpointer nick)
{
        const struct game * g = game;
        if (g->status == GAME_STATUS_OPEN
            && streq(g->players_nick[0], (char *) nick))
                return 0;
        else
                return 1;
}
static struct game* find_game_by_nick(char* nick)
{
        return GListp2data(g_list_find_custom(games, nick, find_game_by_nick_aux));
}

static int find_game_by_fd_aux(gconstpointer game, gconstpointer fd)
{
        const struct game* g = game;
        int fd_ = GPOINTER_TO_INT(fd);
        int i;
        for (i = 0; i < g->players_number; i++)
                if (g->players_conn[i] == fd_)
                        return 0;
        return 1;
}
static struct game* find_game_by_fd(int fd)
{
        return GListp2data(g_list_find_custom(games, GINT_TO_POINTER(fd), find_game_by_fd_aux));
}

int find_player_number(struct game *g, int fd)
{
        int i;
        for (i = 0; i < g->players_number; i++)
                if (g->players_conn[i] == fd)
                        return i;
        l0("Internal error");
        exit(1);
}

static void real_start_game(struct game* g)
{
        int i;
        char mapping_str[4096] = "";
        char can_start_msg[1000];
        for (i = 0; i < g->players_number; i++) {
                int len = strlen(mapping_str);
                if (len >= sizeof(mapping_str)-1)
                        return;
                mapping_str[len] = g->players_conn[i];
                mapping_str[len+1] = '\0';
                strncat(mapping_str, g->players_nick[i], sizeof(mapping_str));
                if (i < g->players_number - 1)
                        strncat(mapping_str, ",", sizeof(mapping_str));
        }
        snprintf(can_start_msg, sizeof(can_start_msg), ok_can_start, mapping_str);
        for (i = 0; i < g->players_number; i++)
                send_line_log_push_binary(g->players_conn[i], can_start_msg, ok_can_start);

        g->status = GAME_STATUS_PLAYING;
        for (i = 0; i < g->players_number; i++)
                add_prio(g->players_conn[i]);
}

static void start_game(int fd)
{
        int i;
        struct game * g = find_game_by_fd(fd);
        if (g) {
                char start_msg[1000];
                int j = find_player_number(g, fd);
                int still_waiting = 0;
                if (g->players_number == 1) {
                        send_line_log(fd, wn_alone_in_the_dark, "START");
                        return;
                }
                if (g->status == GAME_STATUS_OPEN) {
                        g->status = GAME_STATUS_STARTING;
                        for (i = 0; i < g->players_number; i++)
                                g->players_starting[i] = 0;
                        calculate_list_games();
                } else if (g->players_starting[j] == 1) {
                        send_line_log(fd, wn_already_started, "START");
                        return;
                }
                g->players_starting[j] = 1;
                snprintf(start_msg, sizeof(start_msg), ok_start, g->players_nick[j]);
                for (i = 0; i < g->players_number; i++) {
                        if (i != j) {
                                still_waiting |= !g->players_starting[i];
                                send_line_log_push(g->players_conn[i], start_msg);
                        }
                }
                send_ok(fd, "START");
                if (!still_waiting)
                        real_start_game(g);
        } else {
                l0("Internal error");
                exit(1);
        }
}

void player_part_game(int fd)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                int j;
                int i = find_player_number(g, fd);

                if (g->status == GAME_STATUS_PLAYING) {
                        // inform other players, playing state
                        char leave_player_prio_msg[] = "?leave:\n";
                        leave_player_prio_msg[0] = fd;
                        process_msg_prio(fd, leave_player_prio_msg, strlen(leave_player_prio_msg));
                } else {
                        char parted_msg[1000];
                        // inform other players, non-playing state
                        snprintf(parted_msg, sizeof(parted_msg), ok_player_parted, g->players_nick[i]);
                        for (j = 0; j < g->players_number; j++)
                                if (g->players_conn[j] != fd)
                                        send_line_log_push(g->players_conn[j], parted_msg);
                }

                // remove parting player from game
                free(g->players_nick[i]);
                for (j = i; j < g->players_number - 1; j++) {
                        g->players_conn[j] = g->players_conn[j + 1];
                        g->players_nick[j] = g->players_nick[j + 1];
                }
                g->players_number--;
                
                // completely remove game if empty
                if (g->players_number == 0) {
                        games = g_list_remove(games, g);
                        free(g);
                } else {
                        // if non-empty, game status is backwarded
                        if (g->status == GAME_STATUS_STARTING) {
                                g->status = GAME_STATUS_OPEN;
                                for (j = 0; j < g->players_number; j++)
                                        send_line_log_push(g->players_conn[j], ok_status_open);
                        }
                }
                calculate_list_games();
                
                open_players = g_list_append(open_players, GINT_TO_POINTER(fd));
        }
}

static void stop_game(int fd)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                char stop_msg[1000];
                int j = find_player_number(g, fd);
                if (g->status == GAME_STATUS_OPEN) {
                        send_line_log(fd, wn_not_started, "STOP");
                        return;
                }
                g->status = GAME_STATUS_OPEN;
                send_ok(fd, "STOP");
                snprintf(stop_msg, sizeof(stop_msg), ok_stop, g->players_nick[j]);
                for (j = 0; j < g->players_number; j++)
                        if (g->players_conn[j] != fd)
                                send_line_log_push(g->players_conn[j], stop_msg);
                player_part_game(fd);
        } else {
                l0("Internal error");
                exit(1);
        }
}

void player_connects(int fd)
{
        open_players = g_list_append(open_players, GINT_TO_POINTER(fd));
}

void player_disconnects(int fd)
{
        open_players = g_list_remove(open_players, GINT_TO_POINTER(fd));
}

static void talk_serverwide_aux(gpointer data, gpointer user_data)
{
        send_line_log_push(GPOINTER_TO_INT(data), user_data);
}

static void talk(int fd, char* msg)
{
        struct game * g = find_game_by_fd(fd);
        char talk_msg[1000];
        snprintf(talk_msg, sizeof(talk_msg), ok_talk, msg);
        if (g) {
                // player is in a game, it's a game-only chat
                int i;
                for (i = 0; i < g->players_number; i++)
                        send_line_log_push(g->players_conn[i], talk_msg);
        } else {
                // player is not in a game, it's a server-wide chat
                g_list_foreach(open_players, talk_serverwide_aux, talk_msg);
        }
}

static void status(int fd, char* msg)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                char* game = list_game(g);
                send_line_log(fd, game, msg);
                free(game);
        } else {
                send_line_log(fd, wn_not_in_game, msg);
        }
}

static gboolean nick_available_aux(gconstpointer data, gconstpointer user_data)
{
        const struct game* g = data;
        const char* nick = user_data;
        int i;
        for (i = 0; i < g->players_number; i++)
                if (streq(g->players_nick[i], nick))
                        return TRUE;
        return FALSE;
}
static int nick_available(char* nick)
{
        return !g_list_any(games, nick_available_aux, nick);
}

static gboolean already_in_game_aux(gconstpointer data, gconstpointer user_data)
{
        const struct game* g = data;
        int fd = GPOINTER_TO_INT(user_data);
        int i;
        for (i = 0; i < g->players_number; i++)
                if (g->players_conn[i] == fd)
                        return TRUE;
        return FALSE;
}
static int already_in_game(int fd)
{
        return g_list_any(games, already_in_game_aux, GINT_TO_POINTER(fd));
}



/* true return value indicates that connection must be closed */
int process_msg(int fd, char* msg)
{
        int remote_proto_major;
        int remote_proto_minor;
        char * args;
        char * ptr, * ptr2;
        char * msg_orig;

        /* check for leading protocol tag */
        if (!str_begins_static_str(msg, "FB/")
            || strlen(msg) < 8) {  // 8 stands for "FB/M.m f"(oo)
                send_line_log(fd, fl_line_unrecognized, msg);
                return 1;
        }
    
        /* check if remote protocol is compatible */
        remote_proto_major = charstar_to_int(msg + 3);
        remote_proto_minor = charstar_to_int(msg + 5);
        if (remote_proto_major != proto_major
            || remote_proto_minor > proto_minor) {
                send_line_log(fd, fl_proto_mismatch, msg);
                return 1;
        }

        msg_orig = strdup(msg);

        /* after protocol, first word is command, then possible args */
        current_command = msg + 7; // 7 stands for "FB/M.m "
        if ((ptr = strchr(current_command, ' '))) {
                *ptr = '\0';
                args = current_command + strlen(current_command) + 1;
        } else
                args = NULL;

        if (streq(current_command, "PING")) {
                send_line_log(fd, ok_pong, msg_orig);
        } else if (streq(current_command, "CREATE")) {
                if (!args) {
                        send_line_log(fd, wn_missing_arguments, msg_orig);
                } else {
                        if ((ptr = strchr(args, ' ')))
                                *ptr = '\0';
                        if (strlen(args) > 10)
                                args[10] = '\0';
                        if (!nick_available(args)) {
                                send_line_log(fd, wn_nick_in_use, msg_orig);
                        } else if (already_in_game(fd)) {
                                send_line_log(fd, wn_already_in_game, msg_orig);
                        } else {
                                create_game(fd, strdup(args));
                                send_ok(fd, msg_orig);
                        }
                }
        } else if (streq(current_command, "JOIN")) {
                if (!args || !(ptr = strchr(args, ' '))) {
                        send_line_log(fd, wn_missing_arguments, msg_orig);
                } else {
                        struct game * g;
                        char* nick = ptr + 1;
                        *ptr = '\0';
                        if ((ptr2 = strchr(ptr, ' ')))
                                *ptr2 = '\0';
                        if (strlen(nick) > 10)
                                nick[10] = '\0';
                        if (!nick_available(nick)) {
                                send_line_log(fd, wn_nick_in_use, msg_orig);
                        } else if (already_in_game(fd)) {
                                send_line_log(fd, wn_already_in_game, msg_orig);
                        } else if (!(g = find_game_by_nick(args))) {
                                send_line_log(fd, wn_no_such_game, msg_orig);
                        } else {
                                if (add_player(g, fd, strdup(nick)))
                                        send_ok(fd, msg_orig);
                                else
                                        send_line_log(fd, wn_game_full, msg_orig);
                        }
                }
        } else if (streq(current_command, "PART")) {
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        player_part_game(fd);
                        send_ok(fd, msg_orig);
                }
        } else if (streq(current_command, "LIST")) {
                send_line_log(fd, list_games_str, msg_orig);
        } else if (streq(current_command, "STATUS")) {
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        status(fd, msg_orig);
                }
        } else if (streq(current_command, "TALK")) {
                if (!args) {
                        send_line_log(fd, wn_missing_arguments, msg_orig);
                } else {
                        talk(fd, args);
                }
        } else if (streq(current_command, "START")) {
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        start_game(fd);
                }
        } else if (streq(current_command, "STOP")) {
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        stop_game(fd);
                }
#ifdef DEBUG
        } else if (streq(current_command, "DEBUG")) {
                show_games();
                net_debug();
        } else if (streq(current_command, "HALT")) {
                exit(0);
#endif
        } else {
                send_line_log(fd, wn_unknown_command, msg);
        }

        free(msg_orig);
        current_command = NULL;

        return 0;
}


ssize_t get_reset_amount_transmitted(void)
{
        ssize_t ret = amount_transmitted;
        amount_transmitted = 0;
        return ret;
}

int rand_(double val) { return 1+(int) (val*rand()/(RAND_MAX+1.0)); }
#define min(x, y) (x < y ? x : y)

void process_msg_prio(int fd, char* msg, ssize_t len)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                int i;
                for (i = 0; i < g->players_number; i++) {
                        // '!' is synchro message, each client will want to receive it even sender
                        if (g->players_conn[i] != fd || msg[1] == '!') {
                                ssize_t retval;
                                ssize_t togo = len;
                                l2("Sending total: %d bytes to %d", togo, g->players_conn[i]);
                                while (togo) {
                                        int randval = rand_(50);
                                        ssize_t amount = min(randval, togo);
                                        l2("Amount: %d togo: %d", amount, togo);
                                        retval = send(g->players_conn[i], msg + (len - togo), amount, 0);
                                        if (retval != amount) {
                                                if (retval == -1) {
                                                        perror("send");
                                                } else {
                                                        l2("short send of %d instead of %d bytes :(", retval, amount);
                                                }
                                        }
                                        {
                                                char buf[1024] = "";
                                                char * from = msg + (len - togo);
                                                int j;
                                                for (j=0; j<amount; j++)
                                                        strcat(buf, asprintf_("%d ", from[j]));
                                                l2("sent %d bytes: %s", amount, buf);
                                        }
                                        togo -= amount;
                                }
                                l0("- done");
                                amount_transmitted += len;
                        }
                }
        } else {
                l1("Internal error: could not find game by fd: %d", fd);
                exit(1);
        }
}
