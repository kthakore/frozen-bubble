/*
 * Copyright (c) 2004 Guillaume Cottenceau
 *
 */

#ifndef _LOG_H_
#define _LOG_H_

double get_current_time(void);

extern char current_date[50];
char* get_current_date(void);

void l_(char* file, long line, const char* func, char* fmt, ...);

#define l0(f)             l_(__FILE__, (long) __LINE__, __func__, \
                             f)
#define l1(f, a1)         l_(__FILE__, (long) __LINE__, __func__, \
                             f, a1)
#define l2(f, a1, a2)     l_(__FILE__, (long) __LINE__, __func__, \
                             f, a1, a2)
#define l3(f, a1, a2, a3) l_(__FILE__, (long) __LINE__, __func__, \
                             f, a1, a2, a3)

#endif
