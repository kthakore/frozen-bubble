/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

/*
 * this file holds network transmission operations.
 * it should be as far away as possible from game considerations
 */

#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <glib.h>

#include "game.h"
#include "tools.h"
#include "log.h"


/* this is set in game.c and used here for answering with
 * the requested command without passing this additional arg */
char* current_command;

int proto_major = 1;
int proto_minor = 0;

static char greets_msg[] = "SERVER_READY";

static char ok_generic[] = "OK";

static char fl_missing_lf[] = "MISSING_LF";
static char fl_server_full[] = "SERVER_IS_FULL";


/* send line adding the protocol in front of the supplied msg */
static ssize_t send_line(int fd, char* msg)
{
        char buf[1000];
        if (current_command)
                snprintf(buf, sizeof(buf), "FB/%d.%d %s: %s\n", proto_major, proto_minor, current_command, msg);
        else 
                snprintf(buf, sizeof(buf), "FB/%d.%d ???: %s\n", proto_major, proto_minor, msg);
        return send(fd, buf, strlen(buf), 0);
}

ssize_t send_line_log(int fd, char* dest_msg, char* inco_msg)
{
        l3("[%d] %s -> %s", fd, inco_msg, dest_msg);
        return send_line(fd, dest_msg);
}

ssize_t send_line_log_push(int fd, char* dest_msg)
{
        char * tmp = current_command;
        ssize_t b;
        current_command = "PUSH";
        l2("[%d] PUSH %s", fd, dest_msg);
        b = send_line(fd, dest_msg);
        current_command = tmp;
        return b;
}

ssize_t send_line_log_push_binary(int fd, char* dest_msg, char* printable_msg)
{
        char * tmp = current_command;
        ssize_t b;
        current_command = "PUSH";
        l2("[%d] PUSH (binary message) %s", fd, printable_msg);
        b = send_line(fd, dest_msg);
        current_command = tmp;
        return b;
}

ssize_t send_ok(int fd, char* inco_msg)
{
        return send_line_log(fd, ok_generic, inco_msg);
}


static void fill_conns_set(gpointer data, gpointer user_data)
{
        FD_SET(GPOINTER_TO_INT(data), (fd_set *) user_data);
}

static GList * new_conns;
static int prio_processed;
static void handle_incoming_data_generic(gpointer data, gpointer user_data, int prio)
{
        int fd;

        if (FD_ISSET((fd = GPOINTER_TO_INT(data)), (fd_set *) user_data)) {
                int conn_terminated = 0;
                char buf[100000];

                ssize_t len = recv(fd, buf, sizeof(buf) - 1, 0);
                if (len <= 0) {
                        l1("[%d] Unexpected peer shutdown", fd);
                        if (len == -1)
                                l2("[%d] This happened on a system error: %s", fd, strerror(errno));
                        goto conn_terminated;
                } else {
                        /* string operations will need a NULL conn_terminated string */
                        buf[len] = '\0';

                        if (prio) {
                                // prio e.g. in game
                                process_msg_prio(fd, buf, len + 1);
                                prio_processed = 1;
                        } else {
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
                                }

                                if (conn_terminated) {
                                conn_terminated:
                                        l1("[%d] Closing connection", fd);
                                        close(fd);
                                        player_part_game(fd);
                                        new_conns = g_list_remove(new_conns, data);
                                        player_disconnects(fd);
                                }
                        }
                }
        }
}

static void handle_incoming_data(gpointer data, gpointer user_data)
{
        handle_incoming_data_generic(data, user_data, 0);
}
static void handle_incoming_data_prio(gpointer data, gpointer user_data)
{
        handle_incoming_data_generic(data, user_data, 1);
}


static GList * conns = NULL;
static GList * conns_prio = NULL;
void connections_manager(int sock)
{
        struct sockaddr_in client_addr;
        ssize_t len = sizeof(client_addr);
        struct timeval tv;

        while (1) {
                int fd;
                int retval;
                fd_set conns_set;

                FD_ZERO(&conns_set);
                g_list_foreach(conns, fill_conns_set, &conns_set);
                g_list_foreach(conns_prio, fill_conns_set, &conns_set);
                FD_SET(sock, &conns_set);
               
                tv.tv_sec = 30;
                tv.tv_usec = 0;

                if ((retval = select(FD_SETSIZE, &conns_set, NULL, NULL, &tv)) == -1) {
                        perror("select");
                        exit(-1);
                }

                // timeout
                if (!retval)
                        continue;

                prio_processed = 0;
                new_conns = g_list_copy(conns_prio);
                g_list_foreach(conns_prio, handle_incoming_data_prio, &conns_set);
                g_list_free(conns_prio);
                conns_prio = new_conns;

                // prio has higher priority (astounding statement, eh?)
                if (prio_processed)
                        continue;

                if (FD_ISSET(sock, &conns_set)) {
                        if ((fd = accept(sock, (struct sockaddr *) &client_addr,
                                         (socklen_t *) &len)) == -1) {
                                perror("accept");
                                exit(-1);
                        }
                        l2("Accepted connection from %s: fd %d", inet_ntoa(client_addr.sin_addr), fd);
                        if (fd > 255) {
                                send_line_log_push(fd, fl_server_full);
                                close(fd);
                        } else {
                                send_line_log_push(fd, greets_msg);
                                conns = g_list_append(conns, GINT_TO_POINTER(fd));
                                player_connects(fd);
                                calculate_list_games();
                        }
                }

                new_conns = g_list_copy(conns);
                g_list_foreach(conns, handle_incoming_data, &conns_set);
                g_list_free(conns);
                conns = new_conns;
        }
}


int conns_nb(void)
{
        return g_list_length(conns_prio) + g_list_length(conns);
}

void add_prio(int fd)
{
        conns_prio = g_list_append(conns_prio, GINT_TO_POINTER(fd));
        new_conns = g_list_remove(new_conns, GINT_TO_POINTER(fd));
}


int create_server(void)
{
        int sock;
        struct sockaddr_in client_addr;
        int port = 1511;  // a.k.a 0xf 0xb thx misc
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