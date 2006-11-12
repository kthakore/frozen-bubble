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
#include <stdarg.h>

void player_connects(int fd);
void player_disconnects(int fd);

void calculate_list_games(void);

void player_part_game(int fd);
void player_part_game_(int fd, char* reason);

int process_msg(int fd, char* msg);

ssize_t get_reset_amount_transmitted(void);
void process_msg_prio(int fd, char* msg, ssize_t len);

extern char* nick[256];
extern char* geoloc[256];
extern char* IP[256];
extern int remote_proto_minor[256];
extern int admin_authorized[256];
