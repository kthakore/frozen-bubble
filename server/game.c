/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

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

#include <glib.h>

#include "net.h"
#include "tools.h"
#include "log.h"


#define MAX_PLAYERS 5

struct game
{
        int players_number;
        int players_conn[MAX_PLAYERS];
        char* players_nick[MAX_PLAYERS];
};

GList * games = NULL;

static char ok_player_joined[] = "JOINED: %s";
static char ok_player_parted[] = "PARTED: %s";

static char wn_unknown_command[] = "UNKNOWN_COMMAND";
static char wn_missing_arguments[] = "MISSING_ARGUMENTS";
static char wn_nick_in_use[] = "NICK_IN_USE";
static char wn_no_such_game[] = "NO_SUCH_GAME";
static char wn_game_full[] = "GAME_FULL";
static char wn_already_in_game[] = "ALREADY_IN_GAME";

static char fl_line_unrecognized[] = "MISSING_FB_PROTOCOL_TAG";
static char fl_proto_mismatch[] = "INCOMPATIBLE_PROTOCOL";


static char list_games_str[10000];
static void list_games_aux(gpointer data, gpointer user_data)
{
        const struct game* g = data;
        int i;
        if (list_games_str[0] != '\0')
                strncat(list_games_str, ",", sizeof(list_games_str));
        strncat(list_games_str, "[", sizeof(list_games_str));
        for (i = 0; i < g->players_number; i++) {
                strncat(list_games_str, g->players_nick[i], sizeof(list_games_str));
                if (i < g->players_number - 1)
                        strncat(list_games_str, ",", sizeof(list_games_str));
        }
        strncat(list_games_str, "]", sizeof(list_games_str));
}
static void calculate_list_games(void)
{
        list_games_str[0] = '\0';
        g_list_foreach(games, list_games_aux, NULL);
}

static void create_game(int fd, char* nick)
{
        struct game * g = malloc(sizeof(struct game));
        g->players_number = 1;
        g->players_conn[0] = fd;
        g->players_nick[0] = nick;
        games = g_list_append(games, g);
        calculate_list_games();
}

static int add_player(struct game * g, int fd, char* nick)
{
        char joined_msg[1000];
        int i;
        if (g->players_number < MAX_PLAYERS) {
                /* inform other players */
                snprintf(joined_msg, sizeof(joined_msg), ok_player_joined, nick);
                for (i = 0; i < g->players_number; i++)
                        send_line_log_push(g->players_conn[i], joined_msg);

                g->players_conn[g->players_number] = fd;
                g->players_nick[g->players_number] = nick;
                g->players_number++;
                calculate_list_games();
                return 1;
        } else {
                return 0;
        }
}

static struct game * cleanup_game;
static void cleanup_player_aux(gpointer data, gpointer user_data)
{
        struct game* g = data;
        int fd = GPOINTER_TO_INT(user_data);
        int i;
        for (i = 0; i < g->players_number; i++)
                if (g->players_conn[i] == fd) {
                        int j;
                        char parted_msg[1000];
                        // inform other players
                        snprintf(parted_msg, sizeof(parted_msg), ok_player_parted, g->players_nick[i]);
                        for (j = 0; j < g->players_number; j++)
                                if (j != i)
                                        send_line_log_push(g->players_conn[j], parted_msg);
                        // remove parting player from game
                        free(g->players_nick[i]);
                        for (j = g->players_number - 2; j >= i; j--) {
                                g->players_conn[j] = g->players_conn[j + 1];
                                g->players_nick[j] = g->players_nick[j + 1];
                        }
                        g->players_number--;
                        if (g->players_number == 0)
                                cleanup_game = g;
                }

}
void cleanup_player(int fd)
{
        cleanup_game = NULL;
        g_list_foreach(games, cleanup_player_aux, GINT_TO_POINTER(fd));
        if (cleanup_game)
                games = g_list_remove(games, cleanup_game);
        calculate_list_games();
}

static int find_game_aux(gconstpointer game, gconstpointer nick)
{
        if (streq(((struct game *) game)->players_nick[0], (char *) nick))
                return 0;
        else
                return 1;
}
static struct game* find_game(char* nick)
{
        return GListp2data(g_list_find_custom(games, nick, find_game_aux));
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

        if (streq(current_command, "CREATE")) {
                if (!args) {
                        send_line_log(fd, wn_missing_arguments, msg_orig);
                } else {
                        if ((ptr = strchr(args, ' ')))
                                *ptr = '\0';
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
                        if (!nick_available(nick)) {
                                send_line_log(fd, wn_nick_in_use, msg_orig);
                        } else if (already_in_game(fd)) {
                                send_line_log(fd, wn_already_in_game, msg_orig);
                        } else if (!(g = find_game(args))) {
                                send_line_log(fd, wn_no_such_game, msg_orig);
                        } else {
                                if (add_player(g, fd, strdup(nick)))
                                        send_ok(fd, msg_orig);
                                else
                                        send_line_log(fd, wn_game_full, msg_orig);
                        }
                }
        } else if (streq(current_command, "LIST")) {
                send_line_log(fd, list_games_str, msg_orig);
        } else if (streq(current_command, "TALK")) {

        } else {
                send_line_log(fd, wn_unknown_command, msg);
        }

        free(msg_orig);
        current_command = NULL;

        return 0;
}
