/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

#define _GNU_SOURCE
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/poll.h>
#include <errno.h>
#include <fcntl.h>

#include <glib.h>

#include "tools.h"
#include "log.h"


#define MAX_PLAYERS 5

enum game_status { GAME_STATUS_CHAT, GAME_STATUS_PLAY };

struct game
{
        enum game_status status;
        int players_number;
        int players_conn[MAX_PLAYERS];
        char* players_nick[MAX_PLAYERS];
};

GList * games = NULL;

static int proto_major = 1;
static int proto_minor = 0;

static char greets_msg[] = "SERVER READY";

static char ok_generic[] = "Accepted";

static char wn_unknown_command[] = "Unknown command";
static char wn_missing_arguments[] = "Missing arguments";
static char wn_nick_in_use[] = "Nick in use, please choose another one";
static char wn_no_such_game[] = "No game created by supplied nick";
static char wn_game_full[] = "Game is full";
static char wn_already_in_game[] = "Already in a game";

static char fl_line_unrecognized[] = "Unrecognized line, should start with FB protocol tag (bye)";
static char fl_proto_mismatch[] = "Sorry, incompatible protocol versions (bye)";
static char fl_missing_lf[] = "Received data with missing LF (bye)";


static void create_game(int fd, char* nick)
{
        struct game * g = malloc(sizeof(struct game));
//        l1("%p", g);
        g->status = GAME_STATUS_CHAT;
        g->players_number = 1;
        g->players_conn[0] = fd;
        g->players_nick[0] = nick;
        games = g_list_append(games, g);
}

static int add_player(struct game * g, int fd, char* nick)
{
        if (g->players_number < MAX_PLAYERS) {
                g->players_conn[g->players_number] = fd;
                g->players_nick[g->players_number] = nick;
                g->players_number++;
                return 1;
        } else {
                return 0;
        }
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

static char list_games_str[10000];
static void list_games_aux(gpointer data, gpointer user_data)
{
        const struct game* g = data;
        char* s = asprintf_("%s[%d]", g->players_nick[0], g->players_number);
        if (list_games_str[0] != '\0')
                strncat(list_games_str, ",", sizeof(list_games_str));
        strncat(list_games_str, s, sizeof(list_games_str));
        free(s);
}

static char* list_games(void)
{
        list_games_str[0] = '\0';
        g_list_foreach(games, list_games_aux, NULL);
        return list_games_str;
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

static int create_server(void)
{
        int sock;
        struct sockaddr_in client_addr;
        int port = 31337;
        int valone = 1;

        sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) {
                perror("socket");
                exit(-1);
        }

        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &valone, sizeof(valone));

        client_addr.sin_family = AF_INET;
        client_addr.sin_addr.s_addr = htonl(INADDR_ANY);
        client_addr.sin_port = htons(port);
        if (bind(sock, (struct sockaddr *) &client_addr,
                 sizeof(client_addr))) {
                perror("bind");
                exit(-1);
        }

        if (listen(sock, 1000) < 0) {
                perror("listen");
                exit(-1);
        }

        l1("Opened server on port %d", port);

        return sock;
}


/* send line adding the protocol in front of the supplied msg */
static ssize_t send_line(int fd, char* msg)
{
        char buf[1000];
        snprintf(buf, sizeof(buf), "FB/%d.%d %s\n", proto_major, proto_minor, msg);
        return send(fd, buf, strlen(buf), 0);
}

static ssize_t send_line_log(int fd, char* dest_msg, char* inco_msg)
{
        l3("[%d] %s: %s", fd, dest_msg, inco_msg);
        return send_line(fd, dest_msg);
}

static ssize_t send_ok(int fd, char* inco_msg)
{
        return send_line_log(fd, ok_generic, inco_msg);
}

/* true return value indicates that connection must be closed */
static int process_msg(int fd, char* msg)
{
        int remote_proto_major;
        int remote_proto_minor;
        char * command, * args;
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
        command = msg + 7; // 7 stands for "FB/M.m "
        if ((ptr = strchr(command, ' '))) {
                *ptr = '\0';
                args = command + strlen(command) + 1;
        } else
                args = NULL;

        if (streq(command, "CREATE")) {
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
        } else if (streq(command, "JOIN")) {
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
        } else if (streq(command, "LIST")) {
                send_line_log(fd, list_games(), msg_orig);
        } else if (streq(command, "TALK")) {

        } else {
                send_line_log(fd, wn_unknown_command, msg);
        }

        free(msg_orig);

        return 0;
}


static void fill_conns_set(gpointer data, gpointer user_data)
{
        FD_SET(GPOINTER_TO_INT(data), (fd_set *) user_data);
}

static GList * new_conns;
static void handle_incoming_data(gpointer data, gpointer user_data)
{
        int fd;

        if (FD_ISSET((fd = GPOINTER_TO_INT(data)), (fd_set *) user_data)) {
                int conn_terminated = 0;
                char buf[100000];

                ssize_t len = recv(fd, buf, sizeof(buf) - 1, 0);
                if (len == -1) {
                        perror("recv");
                        exit(-1);
                }
                if (len == 0) {
                        l1("[%d] Unexpected peer shutdown", fd);
                        goto conn_terminated;
                } else {
                        /* string operations will need a NULL conn_terminated string */
                        buf[len] = '\0';
                        
                        if (!strchr(buf, '\n')) {
                                send_line_log(fd, fl_missing_lf, buf);
                                goto conn_terminated;
                        } else {
                                char * eol;
                                char * line = buf;
                                /* loop (to handle case when network gives us several lines at once) */
                                while (!conn_terminated && (eol = strchr(line, '\n'))) {
                                        eol[0] = '\0';
                                        if (strlen(line) > 0 && eol[-1] == '\r')
                                                eol[-1] = '\0';
                                        conn_terminated = process_msg(fd, line);
                                        line = eol + 1;
                                }
                                
                                if (conn_terminated) {
                                conn_terminated:
                                        l1("[%d] Closing connection", fd);
                                        close(fd);
                                        new_conns = g_list_remove(new_conns, data);
                                }
                        }
                }
        }
}


static void connections_manager(int sock)
{
        struct sockaddr_in client_addr;
        ssize_t len = sizeof(client_addr);
        GList * conns = NULL;
        struct timeval tv;

        while (1) {
                int fd;
                int retval;
                fd_set conns_set;

                FD_ZERO(&conns_set);
                g_list_foreach(conns, fill_conns_set, &conns_set);
                FD_SET(sock, &conns_set);
               
                tv.tv_sec = 30;
                tv.tv_usec = 0;

                if ((retval = select(FD_SETSIZE, &conns_set, NULL, NULL, &tv)) == -1) {
                        perror("select");
                        exit(-1);
                }

                /* timeout */
                if (!retval)
                        continue;

                if (FD_ISSET(sock, &conns_set)) {
                        if ((fd = accept(sock, (struct sockaddr *) &client_addr,
                                         (socklen_t *) &len)) == -1) {
                                perror("accept");
                                exit(-1);
                        }
                        l2("Accepted connection from %s: fd %d", inet_ntoa(client_addr.sin_addr), fd);
                        send_line(fd, greets_msg);
                        conns = g_list_append(conns, GINT_TO_POINTER(fd));
                }

                new_conns = g_list_copy(conns);
                g_list_foreach(conns, handle_incoming_data, &conns_set);
                g_list_free(conns);
                conns = new_conns;
        }
}

int main(int argc, char **argv)
{
        int sock = create_server();
        connections_manager(sock);

        return 0;
}
