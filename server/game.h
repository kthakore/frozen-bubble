/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

#include <stdlib.h>
#include <stdarg.h>

void player_connects(int fd);
void player_disconnects(int fd);

void calculate_list_games(void);

void player_part_game(int fd);

int process_msg(int fd, char* msg);
void process_msg_prio(int fd, char* msg, ssize_t len);
