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
#include <errno.h>

#include <glib.h>

#include "net.h"


int main(int argc, char **argv)
{
        int sock = create_server();
        connections_manager(sock);

        return 0;
}
