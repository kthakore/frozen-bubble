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
#include <ctype.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <glib.h>

#include "tools.h"
#include "log.h"
#include "net.h"

// converts a char* to the number it represents, with:
// - when failing it returns 0
// - it stops on first non-digit char
int charstar_to_int(const char * s)
{
        int number = 0;
        while (*s && isdigit(*s)) {
                number = (number * 10) + (*s - '0');
                s++;
        }
        return number;
}

char * vasprintf_(const char *msg, va_list args)
{
        char s[8192];
        vsnprintf(s, sizeof(s), msg, args);
        return strdup(s);
}

// _GNU_SOURCE's asprintf like, but
// - doesn't need _GNU_SOURCE
// - returns allocated string
// - never returns NULL (prints failure and exit on out of memory)
char * asprintf_(const char *msg, ...)
{
        char * results;
        va_list arg_ptr;
        va_start(arg_ptr, msg);
        results = vasprintf_(msg, arg_ptr);
        va_end(arg_ptr);
        return results;
}

void * malloc_(size_t size)
{
        void * ret = malloc(size);
        if (ret == NULL) {
                fprintf(stderr, "Out of memory, exiting - size was %zd.\n", size);
                exit(EXIT_FAILURE);
        }
        return ret;
}

void * realloc_(void * ptr, size_t size)
{
        void * ret = realloc(ptr, size);
        if (ret == NULL) {
                fprintf(stderr, "Out of memory, exiting - size was %zd.\n", size);
                exit(EXIT_FAILURE);
        }
        return ret;
}

void * memdup(void *src, size_t size)
{
        void * r = malloc_(size);
        memcpy(r, src, size);
        return r;
}

/** Should be using strlcat but could not find a GPL implementation.
    Check http://www.courtesan.com/todd/papers/strlcpy.html it rulz. */
size_t strconcat(char *dst, const char *src, size_t size)
{
        char *ptr = dst + strlen(dst);
        while (ptr - dst < size - 1) {
                *ptr = *src;
                ptr++;
                src++;
                if (!*src)
                        break;
        }
        *ptr = '\0';
        return ptr - dst;
}


// is there a glist function to do that already?
void * GListp2data(GList * elem)
{
        if (elem)
                return elem->data;
        else
                return NULL;
}


static gpointer _g_list_fold_left_partial;
static GFoldFunc _g_list_fold_left_func;
static void _g_list_fold_left_aux(gpointer data, gpointer user_data)
{
        _g_list_fold_left_partial = _g_list_fold_left_func(data, _g_list_fold_left_partial, user_data);
}

gpointer g_list_fold_left(GList * list, gpointer first, GFoldFunc func, gpointer user_data)
{
        _g_list_fold_left_partial = first;
        _g_list_fold_left_func = func;
        g_list_foreach(list, _g_list_fold_left_aux, user_data);
        return _g_list_fold_left_partial;
}


static GTruthFunc _g_list_any_func;
static gint _g_list_any_aux(gconstpointer data, gconstpointer user_data)
{
        if (_g_list_any_func(data, user_data) == TRUE)
                return 0;
        else
                return 1;
}

gboolean g_list_any(GList * list, GTruthFunc func, gpointer user_data)
{
        _g_list_any_func = func;
        if (g_list_find_custom(list, user_data, _g_list_any_aux) == NULL)
                return FALSE;
        else
                return TRUE;
}

static void close_fds(gpointer data, gpointer user_data)
{
        close(GPOINTER_TO_INT(data));
}

void daemonize() {
        pid_t pid, sid;
        GList * retained_fds = NULL;
        int fd;

        // Using the file descriptor number 10 is not possible because newlines are checked
        // for message termination. Retain it.
        while (1) {
                fd = open("/dev/null", 0);
                if (fd == -1) {
                        l1(OUTPUT_TYPE_ERROR, "opening /dev/null: %s", strerror(errno));
                        exit(EXIT_FAILURE);
                }
                if (fd < 10) {
                        retained_fds = g_list_append(retained_fds, GINT_TO_POINTER(fd));
                } else if (fd == 10) {
                        break;
                } else {
                        // Past 10, so close this one and break
                        close(fd);
                        break;
                }
        }
        if (retained_fds) {
                g_list_foreach(retained_fds, close_fds, NULL);
                g_list_free(retained_fds);
        }

        if (debug_mode)
                return;

        pid = fork();
        if (pid < 0) {
                l1(OUTPUT_TYPE_ERROR, "Cannot fork: %s", strerror(errno));
                exit(EXIT_FAILURE);
        }
        if (pid > 0) {
                // Need to register from a separate process because master server will test us
                register_server();
                exit(EXIT_SUCCESS);
        }
        
        // Don't stay orphan
        sid = setsid();
        if (sid < 0) {
                l1(OUTPUT_TYPE_ERROR, "Cannot setsid: %s", strerror(errno));
                exit(EXIT_FAILURE);
        }

        // Don't lock a directory
        if (chdir("/") < 0) {
                l1(OUTPUT_TYPE_ERROR, "Cannot chdir: %s", strerror(errno));
                exit(EXIT_FAILURE);
        }
        printf("Entering daemon mode.\n");

        close(STDIN_FILENO);
        close(STDOUT_FILENO);
        close(STDERR_FILENO);

        // Using the file descriptor number 0 is not possible due to the string-oriented protocol when
        // negociating the game (since C strings cannot contain the NULL char). Retain one file descriptor.
        fd = open("/dev/null", 0);
        if (fd == -1) {
                l1(OUTPUT_TYPE_ERROR, "opening /dev/null: %s", strerror(errno));
                exit(EXIT_FAILURE);
        }

        l0(OUTPUT_TYPE_INFO, "Entered daemon mode.");
}
