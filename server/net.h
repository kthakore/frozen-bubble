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

#include <stdlib.h>
#include <unistd.h>

#include <glib.h>

extern int proto_major;
extern int proto_minor;

extern char* current_command;

ssize_t send_line_log(int fd, char* dest_msg, char* inco_msg);
ssize_t send_line_log_push(int fd, char* dest_msg);
ssize_t send_line_log_push_binary(int fd, char* dest_msg, char* printable_msg);
ssize_t send_ok(int fd, char* inco_msg);

void connections_manager(int sock);
int create_server(void);

int conns_nb(void);
void add_prio(int fd);
