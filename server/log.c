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
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>
#include <sys/time.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>

#include "tools.h"
#include "log.h"

int output_type = OUTPUT_TYPE_INFO;

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
    snprintf(current_date, sizeof(current_date), "%s.%03d", buf, (int)(1000 * (time-seconds)));
    return current_date;
}

void l_(int wanted_output_type, char* file, long line, const char* func, char* fmt, ...)
{
    char *msg;
    va_list args;
    if (output_type <= wanted_output_type) {
            va_start(args, fmt);
            msg = vasprintf_(fmt, args); // segfault later if no more memory :)
            va_end(args);
            if (wanted_output_type == OUTPUT_TYPE_DEBUG) {
                    fprintf(stderr, "[%s] DEBUG   %s:%ld(%s): %s\n", get_current_date(), file, line, func, msg);
            } else if (wanted_output_type == OUTPUT_TYPE_INFO) {
                    fprintf(stderr, "[%s] INFO    %s:%ld(%s): %s\n", get_current_date(), file, line, func, msg);
            } else if (wanted_output_type == OUTPUT_TYPE_CONNECT) {
                    fprintf(stderr, "[%s] CONNECT %s:%ld(%s): %s\n", get_current_date(), file, line, func, msg);
            } else if (wanted_output_type == OUTPUT_TYPE_ERROR) {
                    fprintf(stderr, "[%s] ERROR   %s:%ld(%s): %s\n", get_current_date(), file, line, func, msg);
            } else {
                    fprintf(stderr, "[%s] ???      %s:%ld(%s): %s\n", get_current_date(), file, line, func, msg);
            }
            free(msg);
    }
}

