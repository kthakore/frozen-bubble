/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

#include <stdlib.h>
#include <stdarg.h>

#include <glib.h>

int charstar_to_int(const char * s);
char * trim_newline(char * s);
char * asprintf_(const char *msg, ...);
char * vasprintf_(const char *msg, va_list args);
void * memdup(void *src, size_t size);

void * GListp2data(GList * elem);
typedef gpointer (*GFoldFunc) (gpointer data, gpointer partial, gpointer user_data);
gpointer g_list_fold_left(GList * list, gpointer first, GFoldFunc func, gpointer user_data);
typedef gboolean (*GTruthFunc) (gconstpointer data, gconstpointer user_data);
gboolean g_list_any(GList * list, GTruthFunc func, gpointer user_data);

#define str_begins_static_str(pointer, static_str) \
        (!strncmp(pointer, static_str, sizeof(static_str) - 1))
#define streq(a, b) (!strcmp(a, b))

