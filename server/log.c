/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>
#include <sys/time.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>

#include "tools.h"


double get_current_time(void) 
{
    struct timezone tz;
    struct timeval now;

    gettimeofday(&now, &tz);
    return (double) now.tv_sec + now.tv_usec / 1e6;
}

char current_date[50];
char* get_current_date(void) 
{
    struct tm * lt;
    char buf[50];
    double time = get_current_time();
    time_t seconds = (time_t)time;
    lt = localtime(&seconds);
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", lt);
    snprintf(current_date, sizeof(current_date),
             "%s.%03d", buf, (int)(1000 * (time-seconds)));
    return current_date;
}

void l_(char* file, long line, const char* func, char* fmt, ...)
{
    char *msg;
    va_list args;
    va_start(args, fmt);
    msg = vasprintf_(fmt, args); // segfault later if no more memory :)
    va_end(args);
    fprintf(stderr, "[%s] %s:%ld(%s): %s\n",
                    get_current_date(), file, line, func, msg);
    free(msg);
}

