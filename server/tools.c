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
#include <stdio.h>
#include <stdarg.h>
#include <ctype.h>
#include <glib.h>

#include "log.h"
#include "tools.h"

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
                fprintf(stderr, "Out of memory, exiting - size was " ZD ".\n", size);
                exit(EXIT_FAILURE);
        }
        return ret;
}

void * realloc_(void * ptr, size_t size)
{
        void * ret = realloc(ptr, size);
        if (ret == NULL) {
                fprintf(stderr, "Out of memory, exiting - size was " ZD ".\n", size);
                exit(EXIT_FAILURE);
        }
        return ret;
}

char* strdup_(char* input)
{
        char* ret = strdup(input);
        if (ret == NULL) {
                fprintf(stderr, "Out of memory, exiting - input was %s.\n", input);
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
        while (ptr - dst < size - 1 && *src) {
                *ptr = *src;
                ptr++;
                src++;
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
