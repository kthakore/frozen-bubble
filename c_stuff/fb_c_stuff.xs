/*******************************************************************************
 *
 * Copyright (c) 2001, 2002 Guillaume Cottenceau (guillaume.cottenceau at free.fr)
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

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <SDL/SDL.h>
#include <SDL/SDL_mixer.h>

const int XRES = 640;
const int YRES = 480;

int x, y;
int i, j;


int ANIM_SPEED = 20;
Uint32 ticks;
Uint32 to_wait;
void myLockSurface(SDL_Surface * s)
{
	while (SDL_MUSTLOCK(s) == 1 && SDL_LockSurface(s) < 0)
		SDL_Delay(10);
}
void myUnlockSurface(SDL_Surface * s)
{
	if (SDL_MUSTLOCK(s))
		SDL_UnlockSurface(s);
}
void synchro_before(SDL_Surface * s)
{
	ticks = SDL_GetTicks();	
	myLockSurface(s);
}
void synchro_after(SDL_Surface * s)
{
	myUnlockSurface(s);
	SDL_Flip(s);
	to_wait = SDL_GetTicks() - ticks;
	if (to_wait < ANIM_SPEED) {
		SDL_Delay(ANIM_SPEED - to_wait);
	}
//	else { printf("slow (%d)", ANIM_SPEED - to_wait); }
}
void fb__out_of_memory(void)
{
	fprintf(stderr, "**ERROR** Out of memory\n");
	abort();
}

int rand_(double val) { return 1+(int) (val*rand()/(RAND_MAX+1.0)); }


/************************** Graphical effects ****************************/

/*
 * Features:
 *
 *   - plasma-ordered fill (with top-bottom and/or left-right mirrored plasma's)
 *   - random points
 *   - horizontal blinds
 *   - vertical blinds
 *   - center=>edge circle
 *   - up=>down bars
 *   - top-left=>bottom-right squares
 *
 */

/* -------------- Double Store ------------------ */

void store_effect(SDL_Surface * s, SDL_Surface * img)
{
	void copy_line(int l) {
		memcpy(s->pixels + l*img->pitch, img->pixels + l*img->pitch, img->pitch);
	}
	void copy_column(int c) {
		int bpp = img->format->BytesPerPixel;
		for (y=0; y<YRES; y++)
			memcpy(s->pixels + y*img->pitch + c*bpp, img->pixels + y*img->pitch + c*bpp, bpp);
	}

	int step = 0;
	int store_thickness = 15;

	if (rand_(2) == 1) {
		while (step < YRES/2/store_thickness + store_thickness) {
			
			synchro_before(s);
			
			for (i=0; i<=YRES/2/store_thickness; i++) {
				int v = step - i;
				if (v >= 0 && v < store_thickness) {
					copy_line(i*store_thickness + v);
					copy_line(YRES - 1 - (i*store_thickness + v));
				}
			}
			step++;
			
			synchro_after(s);
		}
	}
	else {
		while (step < XRES/2/store_thickness + store_thickness) {
			
			synchro_before(s);
			
			for (i=0; i<=XRES/2/store_thickness; i++) {
				int v = step - i;
				if (v >= 0 && v < store_thickness) {
					copy_column(i*store_thickness + v);
					copy_column(XRES - 1 - (i*store_thickness + v));
				}
			}
			step++;
			
			synchro_after(s);
		}
	}
}


/* -------------- Bars ------------------ */

void bars_effect(SDL_Surface * s, SDL_Surface * img)
{
	int bpp = img->format->BytesPerPixel;
	const int bars_max_steps = 40;
	const int bars_num = 16;
	
	for (i=0; i<bars_max_steps; i++) {

		synchro_before(s);

		for (y=0; y<YRES/bars_max_steps; y++) {
			int y_  = (i*YRES/bars_max_steps + y) * img->pitch;
			int y__ = (YRES - 1 - (i*YRES/bars_max_steps + y)) * img->pitch;
			
			for (j=0; j<bars_num/2; j++) {
				int x_ =    (j*2) * (XRES/bars_num) * bpp;
				int x__ = (j*2+1) * (XRES/bars_num) * bpp;
				memcpy(s->pixels + y_ + x_,   img->pixels + y_ + x_,   (XRES/bars_num) * bpp);
				memcpy(s->pixels + y__ + x__, img->pixels + y__ + x__, (XRES/bars_num) * bpp);
			}
		}

		synchro_after(s);
	}
}


/* -------------- Squares ------------------ */

void squares_effect(SDL_Surface * s, SDL_Surface * img)
{
	int bpp = img->format->BytesPerPixel;
	const int squares_size = 32;

	int fillrect(int i, int j) {
		int c, v;
		if (i >= XRES/squares_size || j >= YRES/squares_size)
			return 0;
		v = i*squares_size*bpp + j*squares_size*img->pitch;
		for (c=0; c<squares_size; c++)
			memcpy(s->pixels + v + c*img->pitch, img->pixels + v + c*img->pitch, squares_size*bpp);
		return 1;
	}

	int still_moving = 1;

	for (i=0; still_moving; i++) {
		int k = 0;

		synchro_before(s);

		still_moving = 0;
		for (j=i; j>=0; j--) {
			if (fillrect(j, k))
				still_moving = 1;
			k++;
		}

		synchro_after(s);
	}
}


/* -------------- Circle ------------------ */

int * circle_steps;
const int circle_max_steps = 40;
void circle_init(void)
{
	int sqr(int v) { return v*v; }

	circle_steps = malloc(XRES * YRES * sizeof(int));
	if (!circle_steps)
		fb__out_of_memory();

	for (y=0; y<YRES; y++)
		for (x=0; x<XRES; x++) {
			int max = sqrt(sqr(XRES/2) + sqr(YRES/2));
			int value = sqrt(sqr(x-XRES/2) + sqr(y-YRES/2));
			circle_steps[x+y*XRES] = (max-value)*circle_max_steps/max;
		}
}

void circle_effect(SDL_Surface * s, SDL_Surface * img)
{
	int step = circle_max_steps;

	while (step >= 0) {

		synchro_before(s);
		
		for (y=0; y<YRES; y++)
			for (x=0; x<XRES; x++)
				if (circle_steps[x+y*XRES] == step)
					((Uint16*)s->pixels)[x+y*XRES] = ((Uint16*)img->pixels)[x+y*XRES];
		step--;
				
		synchro_after(s);
	}

}


/* -------------- Plasma ------------------ */

unsigned char * plasma, * plasma2;
int plasma_max;
const int plasma_steps = 40;
void plasma_init(char * datapath)
{
	char * finalpath;
	char mypath[] = "/data/plasma.raw";
	FILE * f;
	finalpath = malloc(strlen(datapath) + sizeof(mypath) + 1);
	if (!finalpath)
		fb__out_of_memory();
	sprintf(finalpath, "%s%s", datapath, mypath);
	f = fopen(finalpath, "rb");
	free(finalpath);

	if (!f) {
		fprintf(stderr, "Ouch, could not open plasma.raw for reading\n");
		exit(1);
	}

	plasma = malloc(XRES * YRES);
	if (!plasma)
		fb__out_of_memory();
	if (fread(plasma, 1, XRES * YRES, f) != XRES * YRES) {
		fprintf(stderr, "Ouch, could not read %d bytes from plasma file\n", XRES * YRES);
		exit(1);
	}

	plasma_max = -1;
	for (x=0; x<XRES; x++)
		for (y=0; y<YRES; y++)
			if (plasma[x+y*XRES] > plasma_max)
				plasma_max = plasma[x+y*XRES];

	for (y=0; y<YRES; y++)
		for (x=0; x<XRES; x++)
			plasma[x+y*XRES] = (plasma[x+y*XRES]*plasma_steps)/plasma_max;


	plasma2 = malloc(XRES * YRES);
	if (!plasma2)
		fb__out_of_memory();
	for (i=0; i<XRES*YRES; i++)
		plasma2[i] = rand_(256) - 1;

	for (y=0; y<YRES; y++)
		for (x=0; x<XRES; x++)
			plasma2[x+y*XRES] = (plasma2[x+y*XRES]*plasma_steps)/256;
}

void plasma_effect(SDL_Surface * s, SDL_Surface * img)
{
	int step = 0;

	int plasma_or_random = rand_(2) == 1;
	int rnd_plasma = rand_(4);

	while (step <= plasma_steps) {

		synchro_before(s);

		if (plasma_or_random) {
			/* I need to un-factorize the `plasma' call in order to let gcc optimize (tested!) */
			for (y=0; y<YRES; y++)
				if (rnd_plasma == 1) {
					for (x=0; x<XRES; x++)
						if (plasma[x+y*XRES] == step)
							((Uint16*)s->pixels)[x+y*XRES] = ((Uint16*)img->pixels)[x+y*XRES];
				}
				else if (rnd_plasma == 2) {
					for (x=0; x<XRES; x++)
						if (plasma[(XRES-1-x)+y*XRES] == step)
							((Uint16*)s->pixels)[x+y*XRES] = ((Uint16*)img->pixels)[x+y*XRES];
				}
				else if (rnd_plasma == 3) {
					for (x=0; x<XRES; x++)
						if (plasma[x+(YRES-1-y)*XRES] == step)
							((Uint16*)s->pixels)[x+y*XRES] = ((Uint16*)img->pixels)[x+y*XRES];
				}
				else {
					for (x=0; x<XRES; x++)
						if (plasma[(XRES-1-x)+(YRES-1-y)*XRES] == step)
							((Uint16*)s->pixels)[x+y*XRES] = ((Uint16*)img->pixels)[x+y*XRES];
				}
		} else {
			for (y=0; y<YRES; y++)
				for (x=0; x<XRES; x++)
					if (plasma2[x+y*XRES] == step)
						((Uint16*)s->pixels)[x+y*XRES] = ((Uint16*)img->pixels)[x+y*XRES];
		}

		step++;
				
		synchro_after(s);
	}
}


/************************** Shrinking image ****************************/

void shrink_(SDL_Surface * dest, SDL_Surface * orig, int xpos, int ypos, SDL_Rect * orig_rect, int factor)
{
	int bpp = dest->format->BytesPerPixel;
	int rx = orig_rect->x / factor;
	int rw = orig_rect->w / factor;
	int ry = orig_rect->y / factor;
	int rh = orig_rect->h / factor;
	xpos -= rx;
	ypos -= ry;
	myLockSurface(orig);
	myLockSurface(dest);
	for (x=rx; x<rx+rw; x++) {
		for (y=ry; y<ry+rh; y++) {
			if (!dest->format->palette) {
				/* there is no palette, it's cool, I can do (uber-slow) high-quality shrink */
				Uint32 pixelvalue; /* this should also be okay for 16-bit and 24-bit formats */
				int r = 0; int g = 0; int b = 0;
				for (i=0; i<factor; i++) {
					for (j=0; j<factor; j++) {
						pixelvalue = 0;
						memcpy(&pixelvalue, orig->pixels + (x*factor+i)*bpp + (y*factor+j)*orig->pitch, bpp);
						r += (pixelvalue & orig->format->Rmask) >> orig->format->Rshift;
						g += (pixelvalue & orig->format->Gmask) >> orig->format->Gshift;
						b += (pixelvalue & orig->format->Bmask) >> orig->format->Bshift;
					}
				}
				pixelvalue =
					((r/(factor*factor)) << orig->format->Rshift) +
					((g/(factor*factor)) << orig->format->Gshift) +
					((b/(factor*factor)) << orig->format->Bshift);
				memcpy(dest->pixels + (xpos+x)*bpp + (ypos+y)*dest->pitch, &pixelvalue, bpp);
			} else {
				/* there is a palette... I don't care of the bloody oldskoolers who still use
				   8-bit displays & al, they can suffer and die ;p */
				memcpy(dest->pixels + (xpos+x)*bpp + (ypos+y)*dest->pitch,
				       orig->pixels + (x*factor)*bpp + (y*factor)*orig->pitch, bpp);
			}
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}


inline void put_pixel(SDL_Surface * surf, int x, int y, Uint32 pixelvalue, int bpp)
{
        memcpy(surf->pixels + x*bpp + y*surf->pitch, &pixelvalue, bpp);
}

/************************** 262144 colours demo effect ****************************/

void tv_(SDL_Surface * dest, SDL_Surface * orig, int xpos, int ypos, SDL_Rect * orig_rect)
{
	int bpp = dest->format->BytesPerPixel;
        Uint32 rmax = orig->format->Rmask >> orig->format->Rshift;
        Uint32 gmax = orig->format->Gmask >> orig->format->Gshift;
        Uint32 bmax = orig->format->Bmask >> orig->format->Bshift;
        Uint32 grmul = gmax/rmax;
        Uint32 gbmul = gmax/bmax;
	myLockSurface(orig);
	myLockSurface(dest);
	for (x = orig_rect->x; x < orig_rect->x + orig_rect->w; x++) {
		for (y = orig_rect->y; y < orig_rect->y + orig_rect->h; y+=3) {
			if (!dest->format->palette) {
				/* no palette */
                                Uint32 pixelvalue; /* this should also be okay for 16-bit and 24-bit formats */
				Uint32 rvalue;
				Uint32 gvalue;
				Uint32 bvalue;
				Uint32 r = 0; Uint32 g = 0; Uint32 b = 0;
				Uint32 r_, g_, b_;
                                for (j=0; j<3; j++) {
                                        memcpy(&pixelvalue, orig->pixels + x*bpp + (y+j)*orig->pitch, bpp);
                                        r += (pixelvalue & orig->format->Rmask) >> orig->format->Rshift;
                                        g += (pixelvalue & orig->format->Gmask) >> orig->format->Gshift;
                                        b += (pixelvalue & orig->format->Bmask) >> orig->format->Bshift;
				}
                                r_ = (r/3) << orig->format->Rshift;
                                g_ = (g/3) << orig->format->Gshift;
                                b_ = (b/3) << orig->format->Bshift;

                                rvalue = r_ + ((b_ >> 0) & orig->format->Bmask) + ((g_ >> 0) & orig->format->Gmask);
                                gvalue = g_ + ((r_ >> 0) & orig->format->Rmask) + ((b_ >> 0) & orig->format->Bmask);
                                bvalue = b_ + ((g_ >> 0) & orig->format->Gmask) + ((r_ >> 0) & orig->format->Rmask);

                                put_pixel(dest, x - orig_rect->x + xpos,     y - orig_rect->y + ypos,     rvalue, bpp);
                                put_pixel(dest, x - orig_rect->x + xpos,     y - orig_rect->y + ypos + 1, gvalue, bpp);
                                put_pixel(dest, x - orig_rect->x + xpos,     y - orig_rect->y + ypos + 2, bvalue, bpp);
			} else {
				/* there is a palette... I don't care of the bloody oldskoolers who still use
				   8-bit displays & al, they can suffer and die ;p */
                                printf("not implemented\n");
                                abort();
			}
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}



/************************** Gateway to Perl ****************************/

MODULE = fb_c_stuff		PACKAGE = fb_c_stuff
PROTOTYPES : DISABLE

void
init_effects(datapath)
     char * datapath
	CODE:
		circle_init();
		plasma_init(datapath);
		srand(time(NULL));

void
effect(s, img)
     SDL_Surface * s
     SDL_Surface * img
	CODE:
		if (s->format->BytesPerPixel == 2) {
			int randvalue = rand_(7);
			if (randvalue == 1 || randvalue == 2)
				store_effect(s, img);
			else if (randvalue == 3 || randvalue == 4)
				plasma_effect(s, img);
			else if (randvalue == 5)
				circle_effect(s, img);
			else if (randvalue == 6)
				bars_effect(s, img);
			else
				squares_effect(s, img);
		} else {
			int randvalue = rand_(3);
			if (randvalue == 1)
				store_effect(s, img);
			else if (randvalue == 2)
				bars_effect(s, img);
			else
				squares_effect(s, img);
		}
			
int
get_synchro_value()
	CODE:
		RETVAL = Mix_GetSynchroValue();
	OUTPUT:
		RETVAL

void
set_music_position(pos)
	double pos
	CODE:
		Mix_SetMusicPosition(pos);

int
fade_in_music_position(music, loops, ms, pos)
	Mix_Music *music
	int loops
	int ms
	int pos
	CODE:
		RETVAL = Mix_FadeInMusicPos(music, loops, ms, pos);
	OUTPUT:
		RETVAL

void
shrink(dest, orig, xpos, ypos, orig_rect, factor)
        SDL_Surface * dest
        SDL_Surface * orig
        int xpos
	int ypos
        SDL_Rect * orig_rect
        int factor
	CODE:
		shrink_(dest, orig, xpos, ypos, orig_rect, factor);

void
tv(dest, orig, xpos, ypos, orig_rect)
        SDL_Surface * dest
        SDL_Surface * orig
        int xpos
	int ypos
        SDL_Rect * orig_rect
	CODE:
		tv_(dest, orig, xpos, ypos, orig_rect);

void
_exit(status)
        int status

void
fbdelay(ms)
        int ms
	CODE:
                     /* Beuh, SDL::App::delay is bugged, sometimes it doesn't sleep, must be related to signals
			or something... but doing the do/while in Perl seems to slow down the game too much on
			some machines, so I'll do it from here */
		     int then;
		     do {
			 then = SDL_GetTicks();
			 SDL_Delay(ms);
			 ms -= SDL_GetTicks() - then;
		     } while (ms > 1);
		     
