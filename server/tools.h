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
#include <stdarg.h>

#include <glib.h>

int charstar_to_int(const char* s);
char* asprintf_(const char* msg, ...);
char* vasprintf_(const char* msg, va_list args);
void* malloc_(size_t size);
void* realloc_(void* ptr, size_t size);
char* strdup_(char* input);
void* memdup(void* src, size_t size);
size_t strconcat(char *dst, const char *src, size_t size);

void * GListp2data(GList * elem);
typedef gpointer (*GFoldFunc) (gpointer data, gpointer partial, gpointer user_data);
gpointer g_list_fold_left(GList * list, gpointer first, GFoldFunc func, gpointer user_data);
typedef gboolean (*GTruthFunc) (gconstpointer data, gconstpointer user_data);
gboolean g_list_any(GList * list, GTruthFunc func, gpointer user_data);

void daemonize();
void reregister_server_if_needed();

#define str_begins_static_str(pointer, static_str) \
        (!strncmp(pointer, static_str, sizeof(static_str) - 1))
#define streq(a, b) (!strcmp(a, b))
