/*******************************************************************************
 *
 * Copyright (c) 2004-2012 Guillaume Cottenceau
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
#include <regex.h>

#include <glib.h>

#include "net.h"
#include "tools.h"
#include "log.h"
#include "game.h"

enum game_status { GAME_STATUS_OPEN, GAME_STATUS_CLOSED, GAME_STATUS_PLAYING };

#define MAX_PLAYERS_PER_GAME 5
struct game
{
        enum game_status status;
        int players_number;
        int players_conn[MAX_PLAYERS_PER_GAME];
        char* players_nick[MAX_PLAYERS_PER_GAME];
        int players_started[MAX_PLAYERS_PER_GAME];
};

static GList * games = NULL;
static GList * open_players = NULL;

static ssize_t amount_transmitted = 0;

static char ok_pong[] = "PONG";
static char ok_player_joined[] = "JOINED: %s";
static char ok_player_parted[] = "PARTED: %s";
static char ok_player_kicked[] = "KICKED: %s";
static char ok_talk[] = "TALK: %s";
static char ok_can_start[] = "GAME_CAN_START: %s";

static char wn_unknown_command[] = "UNKNOWN_COMMAND";
static char wn_missing_arguments[] = "MISSING_ARGUMENTS";
static char wn_nick_invalid[] = "INVALID_NICK";
static char wn_nick_in_use[] = "NICK_IN_USE";
static char wn_no_such_game[] = "NO_SUCH_GAME";
static char wn_game_full[] = "GAME_FULL";
static char wn_already_in_game[] = "ALREADY_IN_GAME";
static char wn_max_open_games[] = "ALREADY_MAX_OPEN_GAMES";
static char wn_not_started[] = "NOT_STARTED";
static char wn_already_ok_started[] = "ALREADY_OK_STARTED";
static char wn_not_in_game[] = "NOT_IN_GAME";
static char wn_alone_in_the_dark[] = "ALONE_IN_THE_DARK";
static char wn_not_creator[] = "NOT_CREATOR";
static char wn_no_such_player[] = "NO_SUCH_PLAYER";
static char wn_denied[] = "DENIED";
static char wn_flooding[] = "FLOODING";
static char wn_others_not_ready[] = "OTHERS_NOT_READY";

static char fl_line_unrecognized[] = "MISSING_FB_PROTOCOL_TAG";
static char fl_proto_mismatch[] = "INCOMPATIBLE_PROTOCOL";

char* nick[256];
char* geoloc[256];
char* IP[256];
int remote_proto_minor[256];
int admin_authorized[256];

// calculate the list of players for a given game
static char* list_game(const struct game * g)
{
        char list_game_str[8192] = "";
        int i;
        for (i = 0; i < g->players_number; i++) {
                strconcat(list_game_str, g->players_nick[i], sizeof(list_game_str));
                if (i < g->players_number - 1)
                        strconcat(list_game_str, ",", sizeof(list_game_str));
        }
        return memdup(list_game_str, strlen(list_game_str) + 1);
}

// calculate the list of players for a given game with geolocation
static char* list_game_with_geolocation(const struct game * g)
{
        char list_game_str[8192] = "";
        int i;
        char* n;
        for (i = 0; i < g->players_number; i++) {
                strconcat(list_game_str, g->players_nick[i], sizeof(list_game_str));
                n = geoloc[g->players_conn[i]];
                if (n != NULL) {
                        strconcat(list_game_str, ":", sizeof(list_game_str));
                        strconcat(list_game_str, n, sizeof(list_game_str));
                }
                if (i < g->players_number - 1)
                        strconcat(list_game_str, ",", sizeof(list_game_str));
        }
        return memdup(list_game_str, strlen(list_game_str) + 1);
}

static char list_games_str[16384] __attribute__((aligned(4096))) = "";
static char list_playing_geolocs_str[16384] __attribute__((aligned(4096))) = "";
static int players_in_game;
static int games_open;
static int games_running;
static void list_open_nicks_aux(gpointer data, gpointer user_data)
{
        char* n = nick[GPOINTER_TO_INT(data)];
        if (n == NULL)
                return;
        strconcat(list_games_str, n, sizeof(list_games_str));
        n = geoloc[GPOINTER_TO_INT(data)];
        if (n != NULL) {
                strconcat(list_games_str, ":", sizeof(list_games_str));
                strconcat(list_games_str, n, sizeof(list_games_str));
        }
        strconcat(list_games_str, ",", sizeof(list_games_str));
}
static void list_games_aux(gpointer data, gpointer user_data)
{
        const struct game* g = data;
        if (g->status == GAME_STATUS_OPEN) {
                char* game;
                games_open++;
                strconcat(list_games_str, "[", sizeof(list_games_str));
                game = list_game(g);
                strconcat(list_games_str, game, sizeof(list_games_str));
                free(game);
                strconcat(list_games_str, "]", sizeof(list_games_str));
        } else {
                int i;
                char* geo;
                players_in_game += g->players_number;
                games_running++;
                for (i = 0; i < g->players_number; i++) {
                        geo = geoloc[g->players_conn[i]];
                        if (geo != NULL) {
                                strconcat(list_playing_geolocs_str, geo, sizeof(list_playing_geolocs_str));
                                strconcat(list_playing_geolocs_str, ",", sizeof(list_playing_geolocs_str));
                        }
                }
                return;
        }
}
/* Game list is of the following scheme:
 * 1.1 protocol:
 * <list-of-open-players format="NICK|NICK:GEOLOC"> [<list-of-open-games format=<list-of-players format="NICK">>] free:%d games:%d playing:%d at:<list-of-playing-geolocs>
 * 1.0 protocol:
 * <list-of-open-players format="NICK|NICK:GEOLOC"> [<list-of-open-games format=<list-of-players format="NICK">>] free:%d games:%d playing:%d
 */
void calculate_list_games(void)
{
        char * free_players;
        list_games_str[0] = '\0';
        list_playing_geolocs_str[0] = '\0';
        players_in_game = 0;
        games_open = 0;
        games_running = 0;
        g_list_foreach(open_players, list_open_nicks_aux, NULL);
        strconcat(list_games_str, " ", sizeof(list_games_str));
        g_list_foreach(games, list_games_aux, NULL);
        free_players = asprintf_(" free:%d games:%d playing:%d at:%s", conns_nb() - players_in_game - 1, games_running, players_in_game, list_playing_geolocs_str);  // 1: don't count myself
        strconcat(list_games_str, free_players, sizeof(list_games_str));
        free(free_players);
}

static void create_game(int fd, char* nick)
{
        struct game * g = malloc_(sizeof(struct game));
        g->players_number = 1;
        g->players_conn[0] = fd;
        g->players_nick[0] = nick;
        g->status = GAME_STATUS_OPEN;
        games = g_list_append(games, g);
        open_players = g_list_remove(open_players, GINT_TO_POINTER(fd));
        calculate_list_games();
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
                open_players = g_list_remove(open_players, GINT_TO_POINTER(fd));
                calculate_list_games();
                return 1;
        } else {
                free(nick);
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
        l0(OUTPUT_TYPE_ERROR, "Internal error");
        exit(EXIT_FAILURE);
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
                strconcat(mapping_str, g->players_nick[i], sizeof(mapping_str));
                if (i < g->players_number - 1)
                        strconcat(mapping_str, ",", sizeof(mapping_str));
        }
        snprintf(can_start_msg, sizeof(can_start_msg), ok_can_start, mapping_str);
        for (i = 0; i < g->players_number; i++) {
                send_line_log_push_binary(g->players_conn[i], can_start_msg, ok_can_start);
                g->players_started[i] = 0;
        }
        g->status = GAME_STATUS_PLAYING;
}

static void start_game(int fd)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                if (g->players_conn[0] == fd) {
                        if (g->players_number == 1) {
                                send_line_log(fd, wn_alone_in_the_dark, "START");
                                return;
                        }
                        send_ok(fd, "START");
                        real_start_game(g);
                        calculate_list_games();
                        l2(OUTPUT_TYPE_INFO, "running games increments to: %d (%d players)", games_running, players_in_game);
                } else {
                        send_line_log(fd, wn_not_creator, "START");
                }

        } else {
                l0(OUTPUT_TYPE_ERROR, "Internal error");
                exit(EXIT_FAILURE);
        }
}

static void close_game(int fd)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                if (g->players_conn[0] == fd) {
                        if (g->players_number == 1) {
                                send_line_log(fd, wn_alone_in_the_dark, "CLOSE");
                                return;
                        }
                        send_ok(fd, "CLOSE");
                        g->status = GAME_STATUS_CLOSED;
                        calculate_list_games();
                } else {
                        send_line_log(fd, wn_not_creator, "CLOSE");
                }

        } else {
                l0(OUTPUT_TYPE_ERROR, "Internal error");
                exit(EXIT_FAILURE);
        }
}

static int min_protocol_level(struct game* g)
{
        int i;
        int minor = remote_proto_minor[g->players_conn[0]];
        for (i = 1; i < g->players_number; i++)
                minor = MIN(minor, remote_proto_minor[g->players_conn[i]]);
        return minor;
}

static void setoptions(int fd, char* options)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                if (g->players_conn[0] == fd) {
                        int i;
                        char* msg;
                        send_ok(fd, "SETOPTIONS");
                        msg = asprintf_("OPTIONS: %s,PROTOCOLLEVEL:%d", options, min_protocol_level(g));
                        for (i = 0; i < g->players_number; i++)
                                if (remote_proto_minor[g->players_conn[i]] >= 1)
                                        send_line_log_push(g->players_conn[i], msg);
                        free(msg);
                } else {
                        send_line_log(fd, wn_not_creator, "SETOPTIONS");
                }

        } else {
                l0(OUTPUT_TYPE_ERROR, "Internal error");
                exit(EXIT_FAILURE);
        }
}

static void leader_check_game_start(int fd)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                if (g->status == GAME_STATUS_PLAYING) {
                        int i;
                        for (i = 0; i < g->players_number; i++) {
                                if (fd != g->players_conn[i]) {
                                        if (!g->players_started[i]) {
                                                send_line_log(fd, wn_others_not_ready, "LEADER_CHECK_GAME_START");
                                                return;
                                        }
                                }
                        }
                        send_ok(fd, "LEADER_CHECK_GAME_START");
                } else {
                        send_line_log(fd, wn_not_started, "LEADER_CHECK_GAME_START");
                }
        } else {
                l0(OUTPUT_TYPE_ERROR, "Internal error");
                exit(EXIT_FAILURE);
        }
}

static void ok_start_game(int fd)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                if (g->status == GAME_STATUS_PLAYING) {
                        int i;
                        for (i = 0; i < g->players_number; i++) {
                                if (g->players_conn[i] == fd) {
                                        if (!g->players_started[i]) {
                                                if (remote_proto_minor[g->players_conn[i]] >= 1)
                                                        send_ok(fd, "OK_GAME_START");
                                                g->players_started[i] = 1;
                                                l1(OUTPUT_TYPE_DEBUG, "[%d] entering prio mode", g->players_conn[i]);
                                                add_prio(g->players_conn[i]);
                                        } else {
                                                send_line_log(fd, wn_already_ok_started, "OK_GAME_START");
                                        }
                                }
                        }
                } else {
                        send_line_log(fd, wn_not_started, "OK_GAME_START");
                }
        } else {
                l0(OUTPUT_TYPE_ERROR, "Internal error");
                exit(EXIT_FAILURE);
        }
}

static void kick_player(int fd, struct game * g, char * nick)
{
        int i;
        for (i = 0; i < g->players_number; i++) {
                if (g->players_conn[i] != fd && streq(g->players_nick[i], nick)) {
                        send_ok(fd, "KICK");
                        send_line_log_push(g->players_conn[i], "KICKED");
                        player_part_game_(g->players_conn[i], ok_player_kicked);
                        return;
                }
        }
        send_line_log(fd, wn_no_such_player, "KICK");
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

static gboolean check_match_alert_words(gconstpointer data, gconstpointer user_data)
{
        const regex_t* preg = data;
        const char* msg = user_data;
        if (regexec(preg, msg, 0, NULL, 0) == 0) {
                return TRUE;
        }
        return FALSE;
}

static void talk(int fd, char* msg)
{
        struct game * g = find_game_by_fd(fd);
        char talk_msg[1000];

        if (g_list_any(alert_words, check_match_alert_words, msg))
                l2(OUTPUT_TYPE_INFO, "message '%s' from %s matches alert words!", msg, IP[fd]);

        amount_talk_flood[fd]++;
        if (amount_talk_flood[fd] == 15) {
                l1(OUTPUT_TYPE_INFO, "'%s' is flooding!", IP[fd]);
                send_line_log(fd, wn_flooding, msg);
                conn_terminated(fd, "flooding");
                return;
        }

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

static void status_geo(int fd, char* msg)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                char* game = list_game_with_geolocation(g);
                send_line_log(fd, game, msg);
                free(game);
        } else {
                send_line_log(fd, wn_not_in_game, msg);
        }
}

static void protocol_level(int fd, char* msg)
{
        // Find the smallest minor protocol level among players in game
        struct game * g = find_game_by_fd(fd);
        if (g) {
                char* response;
                int level = min_protocol_level(g);
                response = asprintf_("%d", level);
                send_line_log(fd, response, msg);
                free(response);
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

static int is_nick_ok(char* nick)
{
        int i;
        if (strlen(nick) > 10)
                return 0;
        for (i = 0; i < strlen(nick); i++) {
                if (!((nick[i] >= 'a' && nick[i] <= 'z')
                      || (nick[i] >= 'A' && nick[i] <= 'Z')
                      || (nick[i] >= '0' && nick[i] <= '9')
                      || nick[i] == '-' || nick[i] == '_')) {
                        return 0;
                }
        }
        return 1;
}

/* true return value indicates that connection must be closed */
int process_msg(int fd, char* msg)
{
        int client_proto_major;
        int client_proto_minor;
        char * args;
        char * ptr, * ptr2;
        char * msg_orig;

        /* check for leading protocol tag */
        if (!str_begins_static_str(msg, "FB/")
            || strlen(msg) < 8) {  // 8 stands for "FB/M.m f"(oo)
                send_line_log(fd, fl_line_unrecognized, msg);
                return 1;
        }
    
        /* check if client protocol is compatible; for simplicity, we don't support client protocol more recent
         * than server protocol, we suppose that our servers are upgraded when a new release appears (but of
         * course client protocol older is supported within the major protocol) */
        client_proto_major = charstar_to_int(msg + 3);
        client_proto_minor = charstar_to_int(msg + 5);
        if (client_proto_major != proto_major
            || client_proto_minor > proto_minor) {
                send_line_log(fd, fl_proto_mismatch, msg);
                return 1;
        }

        if (remote_proto_minor[fd] == -1)
                remote_proto_minor[fd] = client_proto_minor;

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
        } else if (streq(current_command, "NICK")) {
                if (!args) {
                        send_line_log(fd, wn_missing_arguments, msg_orig);
                } else {
                        if ((ptr = strchr(args, ' ')))
                                *ptr = '\0';
                        if (strlen(args) > 10)
                                args[10] = '\0';
                        if (!is_nick_ok(args)) {
                                send_line_log(fd, wn_nick_invalid, msg_orig);
                        } else {
                                if (nick[fd] != NULL) {
                                        free(nick[fd]);
                                }
                                nick[fd] = strdup(args);
                                calculate_list_games();
                                send_ok(fd, msg_orig);
                        }
                }
        } else if (streq(current_command, "GEOLOC")) {
                if (!args) {
                        send_line_log(fd, wn_missing_arguments, msg_orig);
                } else {
                        if ((ptr = strchr(args, ' ')))
                                *ptr = '\0';
                        if (strlen(args) > 13)  // sign, 4 digits, dot, colon, sign, 4 digits, dot
                                args[13] = '\0';
                        if (geoloc[fd] != NULL) {
                                free(geoloc[fd]);
                        }
                        geoloc[fd] = strdup(args);
                        calculate_list_games();
                        send_ok(fd, msg_orig);
                }
        } else if (streq(current_command, "CREATE")) {
                if (!args) {
                        send_line_log(fd, wn_missing_arguments, msg_orig);
                } else {
                        if ((ptr = strchr(args, ' ')))
                                *ptr = '\0';
                        if (strlen(args) > 10)
                                args[10] = '\0';
                        if (!is_nick_ok(args)) {
                                send_line_log(fd, wn_nick_invalid, msg_orig);
                        } else if (!nick_available(args)) {
                                send_line_log(fd, wn_nick_in_use, msg_orig);
                        } else if (already_in_game(fd)) {
                                send_line_log(fd, wn_already_in_game, msg_orig);
                        } else if (games_open == 16) {  // FB client can display 16 max
                                send_line_log(fd, wn_max_open_games, msg_orig);
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
                        if (!is_nick_ok(nick)) {
                                send_line_log(fd, wn_nick_invalid, msg_orig);
                        } else if (!nick_available(nick)) {
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
        } else if (streq(current_command, "KICK")) {
                if (!args) {
                        send_line_log(fd, wn_missing_arguments, msg_orig);
                } else {
                        if ((ptr = strchr(args, ' ')))
                                *ptr = '\0';
                        if (strlen(args) > 10)
                                args[10] = '\0';
                        if (!already_in_game(fd)) {
                                send_line_log(fd, wn_not_in_game, msg_orig);
                        } else {
                                struct game * g = find_game_by_fd(fd);
                                if (g->players_conn[0] != fd) {
                                        send_line_log(fd, wn_not_creator, msg_orig);
                                } else {
                                        kick_player(fd, g, args);
                                }
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
        } else if (streq(current_command, "STATUS")) {  // 1.0 command
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        status(fd, msg_orig);
                }
        } else if (streq(current_command, "STATUSGEO")) {
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        status_geo(fd, msg_orig);
                }
        } else if (streq(current_command, "PROTOCOL_LEVEL")) {
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        protocol_level(fd, msg_orig);
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
        } else if (streq(current_command, "CLOSE")) {
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        close_game(fd);
                }
        } else if (streq(current_command, "SETOPTIONS")) {
                if (!args) {
                        send_line_log(fd, wn_missing_arguments, msg_orig);
                } else if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        setoptions(fd, args);
                }
        } else if (streq(current_command, "LEADER_CHECK_GAME_START")) {
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        leader_check_game_start(fd);
                }
        } else if (streq(current_command, "OK_GAME_START")) {
                if (!already_in_game(fd)) {
                        send_line_log(fd, wn_not_in_game, msg_orig);
                } else {
                        ok_start_game(fd);
                }
        } else if (streq(current_command, "ADMIN_REREAD")) {
                if (!admin_authorized[fd]) {
                        send_line_log(fd, wn_denied, msg_orig);
                } else {
                        reread();
                        send_ok(fd, "ADMIN_REREAD");
                }
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

static void conn_to_terminate_helper(gpointer data, gpointer user_data)
{
        conn_terminated(GPOINTER_TO_INT(data), "system error on send (probably peer shutdown or try again)");
}

void process_msg_prio_(int fd, char* msg, ssize_t len, struct game* g)
{
        GList * conn_to_terminate = NULL;
        if (!g)
                g = find_game_by_fd(fd);
        if (g) {
                int i;
                for (i = 0; i < g->players_number; i++) {
                        // Pings are for the server only. Don't broadcast them to save bandwidth.
                        if (len == 3 && msg[1] == 'p') {
                                // nada

                        // Emitter wants to receive synchro message as well
                        } else if (g->players_conn[i] == fd && len > 2 && msg[1] == '!') {
                                char synchro4self[] = "?!\n";
                                ssize_t retval;
                                synchro4self[0] = fd;
                                l1(OUTPUT_TYPE_DEBUG, "[%d] sending self synchro", g->players_conn[i]);
                                retval = send(g->players_conn[i], synchro4self, sizeof(synchro4self) - 1, MSG_NOSIGNAL|MSG_DONTWAIT);
                                if (retval != sizeof(synchro4self) - 1) {
                                        if (retval != -1) {
                                                l4(OUTPUT_TYPE_INFO, "[%d] short send of %zd instead of %zd bytes from %d - destination is not reading data "
                                                                     "(illegal FB client) or our upload bandwidth is saturated - sorry, cannot continue serving "
                                                                     "this client in this situation, closing connection",
                                                                     g->players_conn[i], retval, sizeof(synchro4self) - 1, fd);
                                        }
                                        conn_to_terminate = g_list_append(conn_to_terminate, GINT_TO_POINTER(g->players_conn[i]));
                                }

                        } else if (g->players_conn[i] != fd) {
                                ssize_t retval;
                                l3(OUTPUT_TYPE_DEBUG, "[%d] sending %zd bytes to %d", fd, len, g->players_conn[i]);
                                retval = send(g->players_conn[i], msg, len, MSG_NOSIGNAL|MSG_DONTWAIT);
                                if (retval != len) {
                                        if (retval != -1) {
                                                l4(OUTPUT_TYPE_INFO, "[%d] short send of %zd instead of %zd bytes from %d - destination is not reading data "
                                                                     "(illegal FB client) or our upload bandwidth is saturated - sorry, cannot continue serving "
                                                                     "this client in this situation, closing connection",
                                                                     g->players_conn[i], retval, len, fd);
                                        }
                                        conn_to_terminate = g_list_append(conn_to_terminate, GINT_TO_POINTER(g->players_conn[i]));
                                }
                        }
                }
                if (conn_to_terminate) {
                        g_list_foreach(conn_to_terminate, conn_to_terminate_helper, NULL);
                        g_list_free(conn_to_terminate);
                }
        } else {
                l1(OUTPUT_TYPE_ERROR, "Internal error: could not find game by fd: %d", fd);
                exit(EXIT_FAILURE);
        }
}

void process_msg_prio(int fd, char* msg, ssize_t len)
{
        process_msg_prio_(fd, msg, len, NULL);
}

void player_part_game(int fd)
{
        player_part_game_(fd, NULL);
}

void player_part_game_(int fd, char* reason)
{
        struct game * g = find_game_by_fd(fd);
        if (g) {
                char * save_nick;
                int j;
                int i = find_player_number(g, fd);

                // remove parting player from game
                save_nick = g->players_nick[i];
                for (j = i; j < g->players_number - 1; j++) {
                        g->players_conn[j] = g->players_conn[j + 1];
                        g->players_nick[j] = g->players_nick[j + 1];
                        g->players_started[j] = g->players_started[j + 1];
                }
                g->players_number--;
                
                // completely remove game if empty
                if (g->players_number == 0) {
                        int was_running = g->status == GAME_STATUS_PLAYING;
                        games = g_list_remove(games, g);
                        free(g);
                        calculate_list_games();
                        if (was_running)
                                l2(OUTPUT_TYPE_INFO, "running games decrements to: %d (%d players)", games_running, players_in_game);

                } else {
                        if (g->status == GAME_STATUS_PLAYING) {
                                // inform other players, playing state
                                char leave_player_prio_msg[] = "?l\n";
                                leave_player_prio_msg[0] = fd;
                                process_msg_prio_(fd, leave_player_prio_msg, strlen(leave_player_prio_msg), g);
                        } else {
                                char parted_msg[1000];
                                // inform other players, non-playing state
                                snprintf(parted_msg, sizeof(parted_msg), reason ? reason : ok_player_parted, save_nick);
                                for (j = 0; j < g->players_number; j++)
                                        send_line_log_push(g->players_conn[j], parted_msg);
                        }
                        calculate_list_games();
                }
                free(save_nick);

                open_players = g_list_append(open_players, GINT_TO_POINTER(fd));
        }
}
