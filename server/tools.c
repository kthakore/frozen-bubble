/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <ctype.h>

#include <glib.h>

#include "tools.h"
#include "log.h"

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

char * trim_newline(char * s)
{
        if (s && s[strlen(s)-1] == '\n')
                s[strlen(s)-1] = '\0';
        return s;
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
char * asprintf_(const char *msg, ...)
{
        char * results;
        va_list arg_ptr;
        va_start(arg_ptr, msg);
        results = vasprintf_(msg, arg_ptr);
        va_end(arg_ptr);
        return results;
}

void * memdup(void *src, size_t size)
{
        void * r = malloc(size);
        memcpy(r, src, size);
        return r;
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
