/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

#include <stdlib.h>
#include <unistd.h>


extern int proto_major;
extern int proto_minor;

extern char* current_command;

ssize_t send_line_log(int fd, char* dest_msg, char* inco_msg);
ssize_t send_line_log_push(int fd, char* dest_msg);
ssize_t send_ok(int fd, char* inco_msg);

void connections_manager(int sock);
int create_server(void);
