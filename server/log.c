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
#include <syslog.h>

#include "tools.h"
#include "log.h"
#include "net.h"

int output_type = OUTPUT_TYPE_INFO;
int debug_mode = FALSE;

time_t get_current_time(void) 
{
    struct timeval now;
    struct timezone tz;
    gettimeofday(&now, &tz);
    return now.tv_sec;
}

double get_current_time_exact(void) 
{
    struct timezone tz;
    struct timeval now;
    gettimeofday(&now, &tz);
    return (double) now.tv_sec + now.tv_usec / 1e6;  // bad bad idea to use float as precision is not down to the seconds then
}

char current_date[50];
char* get_current_date(void) 
{
    struct tm * lt;
    char buf[50];
    double time = get_current_time_exact();
    time_t seconds = (time_t)time;
    lt = localtime(&seconds);
    strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", lt);
    snprintf(current_date, sizeof(current_date), "%s.%03d", buf, (int)(1000 * (time-seconds)));
    return current_date;
}

void logging_init(int portnum) {
        openlog(asprintf_("fb-server[TCP%d]", portnum), LOG_PID, LOG_DAEMON);
        if (output_type == OUTPUT_TYPE_DEBUG) {
                l0(OUTPUT_TYPE_INFO, "Starting log. Messages displayed: DEBUG, CONNECT, INFO, ERROR.");
        } else if (output_type == OUTPUT_TYPE_CONNECT) {
                l0(OUTPUT_TYPE_INFO, "Starting log. Messages displayed: CONNECT, INFO, ERROR.");
        } else if (output_type == OUTPUT_TYPE_INFO) {
                l0(OUTPUT_TYPE_INFO, "Starting log. Messages displayed: INFO, ERROR.");
        }
}

char* get_wanted_type(int wanted_output_type)
{
        return wanted_output_type == OUTPUT_TYPE_DEBUG ? "DEBUG"
             : wanted_output_type == OUTPUT_TYPE_CONNECT ? "CONNECT"
             : wanted_output_type == OUTPUT_TYPE_INFO ? "INFO"
             : "ERROR";
}

void l_(int wanted_output_type, char* file, long line, const char* func, char* fmt, ...)
{
    char *msg;
    va_list args;
    if (output_type <= wanted_output_type) {
            int level = 0;
            va_start(args, fmt);
            msg = vasprintf_(fmt, args); // segfault later if no more memory :)
            va_end(args);
            if (wanted_output_type == OUTPUT_TYPE_DEBUG) {
                    level = LOG_DEBUG;
            } else if (wanted_output_type == OUTPUT_TYPE_CONNECT) {
                    level = LOG_NOTICE;
            } else if (wanted_output_type == OUTPUT_TYPE_INFO) {
                    level = LOG_INFO;
            } else if (wanted_output_type == OUTPUT_TYPE_ERROR) {
                    level = LOG_ERR;
            }
            if (debug_mode)
                    fprintf(stderr, "[%s] %s %s:%ld(%s): %s\n", get_current_date(), get_wanted_type(wanted_output_type), file, line, func, msg);
            else {
                    if (output_type == OUTPUT_TYPE_DEBUG)
                            syslog(level, "[%s] %s %s:%ld(%s): %s", get_current_date(), get_wanted_type(wanted_output_type), file, line, func, msg);
                    else
                            syslog(level, "%s %s", get_wanted_type(wanted_output_type), msg);
            }
            free(msg);
    }
}

