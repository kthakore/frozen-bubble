/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

#include <stdlib.h>
#include <stdarg.h>

void calculate_list_games(void);
void cleanup_player(int fd);
int process_msg(int fd, char* msg);
void process_msg_prio(int fd, char* msg, ssize_t len);
