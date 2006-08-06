/*******************************************************************************
 *
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 * Portions from Mandriva's stage1.
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
#include <netdb.h>
#include <poll.h>
#include <sys/utsname.h>

#include <glib.h>

#include "game.h"
#include "tools.h"
#include "log.h"
#include "net.h"

/* this is set in game.c and used here for answering with
 * the requested command without passing this additional arg */
char* current_command;

const int proto_major = 1;
const int proto_minor = 0;

static char greets_msg_base[] = "SERVER_READY %s %s";
static char* servername = NULL;
static char* serverlanguage = NULL;

static char ok_generic[] = "OK";

static char fl_client_nolf[] = "NO_LF_WITHIN_TOO_MUCH_DATA (I bet you're not a regular FB client, hu?)";
static char fl_server_full[] = "SERVER_IS_FULL";
static char fl_server_overloaded[] = "SERVER_IS_OVERLOADED";

static double date_amount_transmitted_reset;

#define DEFAULT_PORT 1511  // a.k.a 0xF 0xB thx misc
#define DEFAULT_MAX_USERS 200
#define DEFAULT_MAX_TRANSMISSION_RATE 100000
#define DEFAULT_OUTPUT "CONNECT"
static int port = DEFAULT_PORT;
static int max_users = DEFAULT_MAX_USERS;
static int max_transmission_rate = DEFAULT_MAX_TRANSMISSION_RATE;

static int lan_game_mode = 0;

static int tcp_server_socket;
static int udp_server_socket = -1;

static int quiet = 0;

static char* external_hostname = "DISTANT_END";
static int external_port = -1;

static GList * conns = NULL;
static GList * conns_prio = NULL;

#define INCOMING_DATA_BUFSIZE 16384
static char * incoming_data_buffers[256];
static int incoming_data_buffers_count[256];

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
        l3(OUTPUT_TYPE_DEBUG, "[%d] %s -> %s", fd, inco_msg, dest_msg);
        return send_line(fd, dest_msg);
}

ssize_t send_line_log_push(int fd, char* dest_msg)
{
        char * tmp = current_command;
        ssize_t b;
        current_command = "PUSH";
        l2(OUTPUT_TYPE_DEBUG, "[%d] PUSH %s", fd, dest_msg);
        b = send_line(fd, dest_msg);
        current_command = tmp;
        return b;
}

ssize_t send_line_log_push_binary(int fd, char* dest_msg, char* printable_msg)
{
        char * tmp = current_command;
        ssize_t b;
        current_command = "PUSH";
        l2(OUTPUT_TYPE_DEBUG, "[%d] PUSH (binary message) %s", fd, printable_msg);
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
void conn_terminated(int fd, char* reason)
{
        l2(OUTPUT_TYPE_CONNECT, "[%d] Closing connection: %s", fd, reason);
        close(fd);
        free(incoming_data_buffers[fd]);
        player_part_game(fd);
        new_conns = g_list_remove(new_conns, GINT_TO_POINTER(fd));
        player_disconnects(fd);
        if (lan_game_mode && g_list_length(new_conns) == 0 && udp_server_socket == -1) {
                l0(OUTPUT_TYPE_INFO, "LAN game mode server exiting on last client exit.");
                exit(EXIT_SUCCESS);
        }
}

static int prio_processed;
static void handle_incoming_data_generic(gpointer data, gpointer user_data, int prio)
{
        int fd;

        if (FD_ISSET((fd = GPOINTER_TO_INT(data)), (fd_set *) user_data)) {
                char buf[INCOMING_DATA_BUFSIZE];
                ssize_t len;
                ssize_t offset = incoming_data_buffers_count[fd];
                incoming_data_buffers_count[fd] = 0;
                memcpy(buf, incoming_data_buffers[fd], offset);
                len = recv(fd, buf + offset, INCOMING_DATA_BUFSIZE - 1 - offset, 0);
                if (len <= 0) {
                        if (len == -1)
                                l2(OUTPUT_TYPE_DEBUG, "[%d] System error on recv: %s", fd, strerror(errno));
                        conn_terminated(fd, "peer shutdown on recv");
                        return;
                } else {
                        len += offset;
                        // If we don't have a newline, it means we are seeing a partial send. Buffer
                        // them, since we can't synchronously wait for newline now or else we'd offer a
                        // nice easy shot for DOS (and beside, this would slow down the whole rest).
                        if (buf[len-1] != '\n') {
                                if (len == INCOMING_DATA_BUFSIZE - 1) {
                                        send_line_log_push(fd, fl_client_nolf);
                                        conn_terminated(fd, "too much data without LF");
                                        return;
                                }
                                l2(OUTPUT_TYPE_DEBUG, "[%d] ****** buffering %d bytes", fd, len);
                                memcpy(incoming_data_buffers[fd], buf, len);
                                incoming_data_buffers_count[fd] = len;
                                return;
                        }

                        if (prio) {
                                // prio e.g. in game
                                process_msg_prio(fd, buf, len);
                                prio_processed = 1;
                        } else {
                                char * eol;
                                char * line = buf;

                                /* string operations will need a NULL conn_terminated string */
                                buf[len] = '\0';

                                /* loop (to handle case when network gives us several lines at once) */
                                while ((eol = strchr(line, '\n'))) {
                                        eol[0] = '\0';
                                        if (strlen(line) > 0 && eol[-1] == '\r')
                                                eol[-1] = '\0';
                                        if (process_msg(fd, line)) {
                                                conn_terminated(fd, "process_msg said to shutdown this connection");
                                                return;
                                        }
                                        line = eol + 1;
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

static void handle_udp_request(void)
{
        static char ok_input_base[] = "FB/%d.%d SERVER PROBE";
        static char * ok_input = NULL;
        static char fl_unrecognized[] = "FB/1.0 You don't exist, go away.\n";
        static char ok_answer_base[] = "FB/%d.%d SERVER HERE AT PORT %d";
        static char * ok_answer = NULL;
        int n;
        char msg[128];
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        char * answer;
        
        if (!ok_input)   // C sux
                ok_input = asprintf_(ok_input_base, proto_major, proto_minor);
        if (!ok_answer)
                ok_answer = asprintf_(ok_answer_base, proto_major, proto_minor, port);


        memset(msg, 0, sizeof(msg));
        n = recvfrom(udp_server_socket, msg, sizeof(msg), 0, (struct sockaddr *) &client_addr, &client_len);
        if (n == -1) {
                l1(OUTPUT_TYPE_ERROR, "recvfrom: %s", strerror(errno));
                return;
        }
        
        l2(OUTPUT_TYPE_DEBUG, "UDP server receives %d bytes from %s.", n, inet_ntoa(client_addr.sin_addr));
        if (strcmp(msg, ok_input) || (lan_game_mode && g_list_length(conns_prio) > 0)) {
                answer = fl_unrecognized;
                l0(OUTPUT_TYPE_DEBUG, "Unrecognized/full.");
        } else {
                answer = ok_answer;
                l0(OUTPUT_TYPE_DEBUG, "Valid FB server probe, answering.");
        }
        
        if (sendto(udp_server_socket, answer, strlen(answer), 0, (struct sockaddr *) &client_addr, sizeof(client_addr)) != strlen(answer)) {
                l1(OUTPUT_TYPE_ERROR, "sendto: %s", strerror(errno));
        }
}

void connections_manager(void)
{
        struct sockaddr_in client_addr;
        ssize_t len = sizeof(client_addr);
        struct timeval tv;
        static char * greets_msg = NULL;
        if (!greets_msg)   // C sux
                greets_msg = asprintf_(greets_msg_base, servername, serverlanguage);

        date_amount_transmitted_reset = get_current_time();

        while (1) {
                int fd;
                int retval;
                fd_set conns_set;

                FD_ZERO(&conns_set);
                g_list_foreach(conns, fill_conns_set, &conns_set);
                g_list_foreach(conns_prio, fill_conns_set, &conns_set);
                if (tcp_server_socket != -1)
                        FD_SET(tcp_server_socket, &conns_set);
                if (udp_server_socket != -1)
                        FD_SET(udp_server_socket, &conns_set);
               
                tv.tv_sec = 30;
                tv.tv_usec = 0;

                if ((retval = select(FD_SETSIZE, &conns_set, NULL, NULL, &tv)) == -1) {
                        l1(OUTPUT_TYPE_ERROR, "select: %s", strerror(errno));
                        exit(EXIT_FAILURE);
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

                new_conns = g_list_copy(conns);
                g_list_foreach(conns, handle_incoming_data, &conns_set);
                g_list_free(conns);
                conns = new_conns;

                if (tcp_server_socket != -1 && FD_ISSET(tcp_server_socket, &conns_set)) {
                        if ((fd = accept(tcp_server_socket, (struct sockaddr *) &client_addr, (socklen_t *) &len)) == -1) {
                                l1(OUTPUT_TYPE_ERROR, "accept: %s", strerror(errno));
                                continue;
                        }
                        l2(OUTPUT_TYPE_CONNECT, "Accepted connection from %s: fd %d", inet_ntoa(client_addr.sin_addr), fd);
                        if (fd > 255 || conns_nb() >= max_users || (lan_game_mode && g_list_length(conns_prio) > 0)) {
                                send_line_log_push(fd, fl_server_full);
                                l1(OUTPUT_TYPE_CONNECT, "[%d] Closing connection (server full)", fd);
                                close(fd);
                        } else {
                                double now = get_current_time();
                                double rate = get_reset_amount_transmitted() / (now - date_amount_transmitted_reset);
                                l1(OUTPUT_TYPE_DEBUG, "Transmission rate: %.2f bytes/sec", rate);
                                date_amount_transmitted_reset = now;
                                if (rate > max_transmission_rate) {
                                        send_line_log_push(fd, fl_server_overloaded);
                                        l1(OUTPUT_TYPE_CONNECT, "[%d] Closing connection (maximum transmission rate reached)", fd);
                                        close(fd);
                                } else {
                                        send_line_log_push(fd, greets_msg);
                                        conns = g_list_append(conns, GINT_TO_POINTER(fd));
                                        player_connects(fd);
                                        incoming_data_buffers[fd] = malloc_(sizeof(char) * INCOMING_DATA_BUFSIZE);
                                        memset(incoming_data_buffers[fd], 0, sizeof(char) * INCOMING_DATA_BUFSIZE);  // force Linux to allocate now
                                        incoming_data_buffers_count[fd] = 0;
                                        calculate_list_games();
                                }
                        }
                }

                if (udp_server_socket != -1 && FD_ISSET(udp_server_socket, &conns_set))
                        handle_udp_request();
        }
}


int conns_nb(void)
{
        return g_list_length(conns_prio) + g_list_length(conns);
}

#ifdef DEBUG
void net_debug(void)
{
        printf("conns_prio:%d;conns:%d\n", g_list_length(conns_prio), g_list_length(conns));
}
#endif
        
void add_prio(int fd)
{
        conns_prio = g_list_append(conns_prio, GINT_TO_POINTER(fd));
        new_conns = g_list_remove(new_conns, GINT_TO_POINTER(fd));
        if (lan_game_mode && g_list_length(conns_prio) > 0 && udp_server_socket != -1) {
                close(tcp_server_socket);
                close(udp_server_socket);
                tcp_server_socket = udp_server_socket = -1;
        }
}

void close_server() {
        if (tcp_server_socket != -1) {
                close(tcp_server_socket);
        }
        if (udp_server_socket != -1) {
                close(udp_server_socket);
        }
        tcp_server_socket = udp_server_socket = -1;
}

static void help(void)
{
        printf("[[ Frozen-Bubble server ]]\n");
        printf(" \n");
        printf("Copyright (c) Guillaume Cottenceau, 2004.\n");
        printf("\n");
        printf("This program is free software; you can redistribute it and/or modify\n");
        printf("it under the terms of the GNU General Public License version 2, as\n");
        printf("published by the Free Software Foundation.\n");
        printf(" \n");
        printf("Usage: fb-server [OPTION]...\n");
        printf("\n");
        printf("     -h                        display this help then exits\n");
        printf("     -n name                   set the server name (mandatory)\n");
        printf("     -l                        LAN mode: create an UDP server (on port %d) to answer broadcasts of clients discovering where are the servers\n", DEFAULT_PORT);
        printf("     -L                        LAN/game mode: create an UDP server as above, but limit number of games to 1 (this is for an FB client hosting a LAN server)\n");
        printf("     -p port                   set the server port (defaults to %d)\n", DEFAULT_PORT);
        printf("     -H host                   set the hostname (or IP) as seen from outside (by default, when registering the server to www.frozen-bubble.org, the distant end at IP level will be used)\n");
        printf("     -P port                   set the server port as seen from outside (defaults to the port specified with -p)\n");
        printf("     -u max_users              set the maximum of connected users (defaults to %d, physical maximum 255 in non debug mode)\n", DEFAULT_MAX_USERS);
        printf("     -t max_transmission_rate  set the maximum transmission rate, in bytes per second (defaults to %d)\n", DEFAULT_MAX_TRANSMISSION_RATE);
        printf("     -o outputtype             set the output type; can be DEBUG, INFO, CONNECT, ERROR; each level includes messages of next level; defaults to INFO\n");
        printf("     -d                        debug mode: do not daemonize, and log on STDERR rather than through syslog (implies -q)\n");
        printf("     -q                        \"quiet\" mode: don't automatically register the server to www.frozen-bubble.org\n");
        printf("     -a                        set the preferred language of the server (it is just an indication used by players when choosing a server, so that they can chat using their native language - you can chose none with -z)\n");
        printf("     -z                        set that there is no preferred language for the server (see -a)\n");
        printf("     -q                        \"quiet\" mode: don't automatically register the server to www.frozen-bubble.org\n");
        printf("     -c conffile               specify the path of the configuration file\n");
}

static void create_udp_server(void)
{
        struct sockaddr_in server_addr;

        printf("-l: creating UDP server for answering broadcast server discover, on default port %d\n", DEFAULT_PORT);

        udp_server_socket = socket(AF_INET, SOCK_DGRAM, 0);
        if (udp_server_socket < 0) {
                perror("socket");
                exit(EXIT_FAILURE);
        }

        server_addr.sin_family = AF_INET;
        server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
        server_addr.sin_port = htons(DEFAULT_PORT);
        if (bind(udp_server_socket, (struct sockaddr *) &server_addr, sizeof(server_addr)) < 0) {
                perror("bind UDP 1511");
                exit(EXIT_FAILURE);
        }
}

static void handle_parameter(char command, char * param) {
        switch (command) {
        case 'h':
                help();
                exit(EXIT_SUCCESS);
        case 'n':
                if (strlen(param) > 12) {
                        fprintf(stderr, "-n: name is too long, maximum is 12 characters\n");
                        exit(EXIT_FAILURE);
                } else {
                        int i;
                        for (i = 0; i < strlen(param); i++) {
                                if (!((param[i] >= 'a' && param[i] <= 'z')
                                      || (param[i] >= 'A' && param[i] <= 'Z')
                                      || (param[i] >= '0' && param[i] <= '9')
                                      || param[i] == '.' || param[i] == '-')) {
                                        fprintf(stderr, "-n: name must contain only chars in [a-zA-Z0-9.-]\n");
                                        exit(EXIT_FAILURE);
                                }
                        }
                        servername = strdup(param);
                }
                break;
        case 'o':
                if (streq(param, "DEBUG")) {
                        output_type = OUTPUT_TYPE_DEBUG;
                } else if (streq(param, "INFO")) {
                        output_type = OUTPUT_TYPE_INFO;
                } else if (streq(param, "CONNECT")) {
                        output_type = OUTPUT_TYPE_CONNECT;
                } else if (streq(param, "ERROR")) {
                        output_type = OUTPUT_TYPE_ERROR;
                }
                break;
        case 'l':
                create_udp_server();
                break;
        case 'L':
                create_udp_server();
                lan_game_mode = 1;
                break;
        case 'p':
                port = charstar_to_int(param);
                if (port != 0) {
                        printf("-p: setting port to %d\n", port);
                        if (external_port == -1)
                                external_port = port;
                } else {
                        port = DEFAULT_PORT;
                        fprintf(stderr, "-p: %s not convertible to int, ignoring\n", param);
                }
                break;
        case 'u':
                max_users = charstar_to_int(param);
                if (max_users != 0)
                        printf("-u: setting maximum users to %d\n", max_users);
                else {
                        max_users = DEFAULT_MAX_USERS;
                        fprintf(stderr, "-u: %s not convertible to int, ignoring\n", param);
                }
                break;
        case 't':
                max_transmission_rate = charstar_to_int(param);
                if (max_transmission_rate != 0)
                        printf("-t: setting maximum transmission rate to %d bytes/sec\n", max_transmission_rate);
                else {
                        max_transmission_rate = DEFAULT_MAX_TRANSMISSION_RATE;
                        fprintf(stderr, "-t: %s not convertible to int, ignoring\n", param);
                }
                break;
        case 'd':
                printf("-d: debug mode on: will not daemonize and will display log messages on STDERR\n");
                debug_mode = TRUE;
                break;
        case 'q':
                printf("-q: quiet mode: will not register to www.frozen-bubble.org\n");
                quiet = TRUE;
                break;
        case 'H':
                printf("-H: setting hostname as seen from outside to %s\n", param);
                external_hostname = strdup(param);
                break;
        case 'P':
                external_port = charstar_to_int(param);
                if (external_port != 0)
                        printf("-P: setting port as seen from outside to %d\n", port);
                else {
                        external_port = -1;
                        fprintf(stderr, "-P: %s not convertible to int, ignoring\n", param);
                }
                break;
        case 'a':
                if (streq(param, "af") || streq(param, "ar") || streq(param, "az") || streq(param, "bg") || streq(param, "br")
                    || streq(param, "bs") || streq(param, "ca") || streq(param, "cs") || streq(param, "cy") || streq(param, "da")
                    || streq(param, "de") || streq(param, "el") || streq(param, "en") || streq(param, "eo") || streq(param, "eu")
                    || streq(param, "fi") || streq(param, "fr") || streq(param, "ga") || streq(param, "gl") || streq(param, "hr")
                    || streq(param, "hu") || streq(param, "id") || streq(param, "is") || streq(param, "it") || streq(param, "ja")
                    || streq(param, "ko") || streq(param, "lt") || streq(param, "lv") || streq(param, "mk") || streq(param, "ms")
                    || streq(param, "nl") || streq(param, "no") || streq(param, "pl") || streq(param, "pt_BR") || streq(param, "ro")
                    || streq(param, "ru") || streq(param, "sk") || streq(param, "sl") || streq(param, "sq") || streq(param, "sv")
                    || streq(param, "tg") || streq(param, "tr") || streq(param, "uk") || streq(param, "uz") || streq(param, "vi")
                    || streq(param, "wa") || streq(param, "zh_CN") || streq(param, "zh_TW")) {
                        serverlanguage = strdup(param);
                        printf("-a: setting preferred language for users of the server to '%s'\n", serverlanguage);
                } else {
                        fprintf(stderr, "-a: %s not a valid language, ignoring\n", param);
                        fprintf(stderr, "    valid languages are: af, ar, az, bg, br, bs, ca, cs, cy, da, de, el, en, eo, eu, fi, fr, ga, gl, hr, hu, id, is, it, ja, ko, lt, lv, mk, ms, nl, no, pl, pt_BR, ro, ru, sk, sl, sq, sv, tg, tr, uk, uz, vi, wa, zh_CN, zh_TW\n" );
                }
                break;
        case 'z':
                printf("-z: no preferred language for users of the server\n");
                serverlanguage = "zz";
                break;
        default:
                fprintf(stderr, "unrecognized option %c, ignoring\n", command);
        }
}

void create_server(int argc, char **argv)
{
        struct sockaddr_in client_addr;
        int valone = 1;

        while (1) {
                int c = getopt(argc, argv, "hn:lLp:u:t:o:c:dqH:P:a:z");
                if (c == -1)
                        break;
                
                if (c == 'c') {
                        FILE* f;
                        printf("-c: reading configuration file %s\n", optarg);
                        f = fopen(optarg, "r");
                        if (!f) {
                                fprintf(stderr, "-c: error opening %s, ignoring\n", optarg);
                        } else {
                                char buf[8192];
                                while (fgets(buf, sizeof(buf), f)) {
                                        char command, param[256];
                                        if (buf[0] == '#' || buf[0] == '\n' || buf[0] == '\r')
                                                continue;
                                        if (sscanf(buf, "%c %256s\n", &command, param) == 2) {
                                                handle_parameter(command, param);
                                        } else if (sscanf(buf, "%c\n", &command) == 1) {
                                                handle_parameter(command, NULL);
                                        } else {
                                                fprintf(stderr, "-c: ignoring line %s\n", buf);
                                        }
                                }
                                if (ferror(f)) {
                                        fprintf(stderr, "-c: error reading %s\n", optarg);
                                }
                                fclose(f);
                        }
                        break;

                } else {
                        handle_parameter(c, optarg);
                }
        }

        if (external_port == -1)
                external_port = port;

        if (!servername) {
                fprintf(stderr, "Must give a name to the server with -n <name>.\n");
                exit(EXIT_FAILURE);
        }

        if (!serverlanguage) {
                fprintf(stderr, "Must set the preferred language of users of the server with -a <language> or specify there is none with -z.\n");
                exit(EXIT_FAILURE);
        }

        tcp_server_socket = socket(AF_INET, SOCK_STREAM, 0);
        if (tcp_server_socket < 0) {
                fprintf(stderr, "creating socket: %s\n", strerror(errno));
                exit(EXIT_FAILURE);
        }

        setsockopt(tcp_server_socket, SOL_SOCKET, SO_REUSEADDR, &valone, sizeof(valone));

        client_addr.sin_family = AF_INET;
        client_addr.sin_addr.s_addr = htonl(INADDR_ANY);
        client_addr.sin_port = htons(port);
        if (bind(tcp_server_socket, (struct sockaddr *) &client_addr, sizeof(client_addr))) {
                fprintf(stderr, "binding port %d: %s\n", port, strerror(errno));
                exit(EXIT_FAILURE);
        }

        if (listen(tcp_server_socket, 1000) < 0) {
                fprintf(stderr, "listen: %s\n", strerror(errno));
                exit(EXIT_FAILURE);
        }

        // Binded correctly, now we can init logging specifying the port (useful for multiple servers)
        logging_init(port);

        l2(OUTPUT_TYPE_INFO, "Created TCP game server on port %d. Servername is '%s'.", port, servername);
}

static int mygethostbyname(char * name, struct in_addr * addr)
{
	struct hostent * h;

        h = gethostbyname(name);
	if (!h) {
                l1(OUTPUT_TYPE_DEBUG, "Unknown host %s", name);
                return -1;

	} else if (h->h_addr_list && (h->h_addr_list)[0]) {
		memcpy(addr, (h->h_addr_list)[0], sizeof(*addr));
                l2(OUTPUT_TYPE_DEBUG, "%s is at %s", name, inet_ntoa(*addr));
		return 0;
	}
	return -1;
}

static char * http_get(char * host, int port, char * path)
{
	char * buf, * ptr, * user_agent;
	char headers[4096];
	char * nextChar = headers;
	int checkedCode;
	struct in_addr serverAddress;
	struct pollfd polls;
	int sock;
        int size, bufsize, dlsize;
	int rc;
        ssize_t bytes;
	struct sockaddr_in destPort;
	char * header_content_length = "Content-Length: ";
        struct utsname uname_;

        l3(OUTPUT_TYPE_DEBUG, "HTTP_GET: retrieving http://%s:%d%s", host, port, path);

	if ((rc = mygethostbyname(host, &serverAddress))) {
                l1(OUTPUT_TYPE_ERROR, "HTTP_GET: cannot resolve %s", host);
                return NULL;
        }

	sock = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
	if (sock < 0) {
                l2(OUTPUT_TYPE_ERROR, "HTTP_GET: cannot create socket for connection to %s:%d", host, port);
		return NULL;
	}

	destPort.sin_family = AF_INET;
	destPort.sin_port = htons(port);
	destPort.sin_addr = serverAddress;

	if (connect(sock, (struct sockaddr *) &destPort, sizeof(destPort))) {
		close(sock);
                l2(OUTPUT_TYPE_ERROR, "HTTP_GET: cannot connect to %s:%d", host, port);
		return NULL;
	}

        uname(&uname_);
        user_agent = asprintf_("Frozen-Bubble server version " VERSION " (protocol version %d.%d) on %s/%s\n", proto_major, proto_minor, uname_.sysname, uname_.machine);
        buf = asprintf_("GET %s HTTP/0.9\r\nHost: %s\r\nUser-Agent: %s\r\n\r\n", path, host, user_agent);
        free(user_agent);
	write(sock, buf, strlen(buf));
        free(buf);

	/* This is fun; read the response a character at a time until we:

	   1) Get our first \r\n; which lets us check the return code
	   2) Get a \r\n\r\n, which means we're done */

	*nextChar = '\0';
	checkedCode = 0;
	while (!strstr(headers, "\r\n\r\n")) {
		polls.fd = sock;
		polls.events = POLLIN;
		rc = poll(&polls, 1, 20*1000);

		if (rc == 0) {
			close(sock);
                        l3(OUTPUT_TYPE_ERROR, "HTTP_GET: timeout retrieving http://%s:%d%s", host, port, path);
			return NULL;
		} else if (rc < 0) {
			close(sock);
                        l3(OUTPUT_TYPE_ERROR, "HTTP_GET: I/O error retrieving http://%s:%d%s", host, port, path);
			return NULL;
		}

		if (read(sock, nextChar, 1) != 1) {
			close(sock);
                        l3(OUTPUT_TYPE_ERROR, "HTTP_GET: I/O error retrieving http://%s:%d%s", host, port, path);
			return NULL;
		}

		nextChar++;
		*nextChar = '\0';

		if (nextChar - headers == sizeof(headers)) {
			close(sock);
                        l3(OUTPUT_TYPE_ERROR, "HTTP_GET: I/O error retrieving http://%s:%d%s", host, port, path);
			return NULL;
		}

		if (!checkedCode && strstr(headers, "\r\n")) {
			char * start, * end;

			checkedCode = 1;
			start = headers;
			while (!isspace(*start) && *start)
                                start++;
			if (!*start) {
				close(sock);
                                l3(OUTPUT_TYPE_ERROR, "HTTP_GET: I/O error retrieving http://%s:%d%s", host, port, path);
                                return NULL;
			}
			start++;

			end = start;
			while (!isspace(*end) && *end)
                                end++;
			if (!*end) {
				close(sock);
                                l3(OUTPUT_TYPE_ERROR, "HTTP_GET: I/O error retrieving http://%s:%d%s", host, port, path);
                                return NULL;
			}

			*end = '\0';
                        l1(OUTPUT_TYPE_DEBUG, "HTTP_GET: server response '%s'", start);
			if (strcmp(start, "200")) {
				close(sock);
                                l4(OUTPUT_TYPE_ERROR, "HTTP_GET: bad server response %s retrieving http://%s:%d%s", start, host, port, path);
                                return NULL;
			}

			*end = ' ';
		}
	}

	if ((buf = strstr(headers, header_content_length))) {
		size = charstar_to_int(buf + strlen(header_content_length));
                bufsize = size + 1;
        } else {
                size = -1;
                bufsize = 4096;
        }
        
        dlsize = 0;
        buf = ptr = malloc_(bufsize);
        while (1) {
                bytes = read(sock, ptr, bufsize - (ptr - buf) - 1);
                if (bytes == -1) {
                        l1(OUTPUT_TYPE_ERROR, "HTTP_GET: read: %s", strerror(errno));
                        close(sock);
                        return NULL;
                } else if (bytes == 0) {
                        // 0 == EOF
                        ptr[0] = '\0';
                        buf = realloc_(buf, dlsize + 1);
                        close(sock);
                        return buf;
                } else {
                        l1(OUTPUT_TYPE_DEBUG, "HTTP_GET: read %d bytes", bytes);
                        dlsize += bytes;
                        ptr = buf + dlsize;
                        if (size > -1 && dlsize == size) {
                                ptr[0] = '\0';
                                buf = realloc_(buf, dlsize + 1);
                                close(sock);
                                return buf;
                        }
                        if (bufsize - (ptr - buf) - 1 < 2048) {
                                bufsize += 4096;
                                buf = realloc_(buf, bufsize);
                                ptr = buf + dlsize;
                        }
                        l2(OUTPUT_TYPE_DEBUG, "HTTP_GET: dlsize %d bytes, bufsize %d bytes", dlsize, bufsize);
                }
        }
}

void register_server() {
        if (!quiet && !lan_game_mode) {
                char* path = asprintf_("/servers/servers.php?server-add=%s&server-add-port=%d", external_hostname, external_port);
                char* doc = http_get("www.frozen-bubble.org", 80, path);
                free(path);
                if (doc != NULL) {
                        if (strstr(doc, "FB_TAG_SERVER_ADDED")) {
                                if (streq(external_hostname, "DISTANT_END")) {
                                        // don't confuse admin printing a cryptic DISTANT_END hostname
                                        l1(OUTPUT_TYPE_INFO, "Successfully registered server (port:%d) to 'www.frozen-bubble.org'.", external_port);
                                } else {
                                        l2(OUTPUT_TYPE_INFO, "Successfully registered server (host:%s port:%d) to 'www.frozen-bubble.org'.", external_hostname, external_port);
                                }
                        } else {
                                char * ptr = doc;
                                l2(OUTPUT_TYPE_ERROR, "Problem registering server (host:%s port:%d) to 'www.frozen-bubble.org'.", external_hostname, external_port);
                                l2(OUTPUT_TYPE_ERROR, "Notice: for successful registering, using the said host and port from outside must reach this server!", external_hostname, external_port);
                                while ((ptr = strstr(doc, "FB_TAG_"))) {
                                        char * end = strchr(ptr, ' ');
                                        if (end) {
                                                *end = '\0';
                                                l1(OUTPUT_TYPE_ERROR, "-> %s", ptr + 7);
                                                ptr = end + 1;
                                        } else {
                                                break;
                                        }
                                }
                        }
                }
        }
}

void unregister_server() {
        if (!quiet && !lan_game_mode) {
                char* path = asprintf_("/servers/servers.php?server-remove=%s&server-remove-port=%d", external_hostname, external_port);
                char* doc = http_get("www.frozen-bubble.org", 80, path);
                free(path);
                if (doc != NULL) {
                        if (strstr(doc, "FB_TAG_SERVER_REMOVED")) {
                                if (streq(external_hostname, "DISTANT_END")) {
                                        // don't confuse admin printing a cryptic DISTANT_END hostname
                                        l1(OUTPUT_TYPE_INFO, "Successfully unregistered server (port:%d) to 'www.frozen-bubble.org'.", external_port);
                                } else {
                                        l2(OUTPUT_TYPE_INFO, "Successfully unregistered server (host:%s port:%d) to 'www.frozen-bubble.org'.", external_hostname, external_port);
                                }
                        } else {
                                char * ptr = doc;
                                l0(OUTPUT_TYPE_ERROR, "Problem unregistering server to 'www.frozen-bubble.org'.");
                                while ((ptr = strstr(doc, "FB_TAG_"))) {
                                        char * end = strchr(ptr, ' ');
                                        if (end) {
                                                *end = '\0';
                                                l1(OUTPUT_TYPE_ERROR, "-> %s", ptr + 7);
                                                ptr = end + 1;
                                        } else {
                                                break;
                                        }
                                }
                        }
                }
        }
}
