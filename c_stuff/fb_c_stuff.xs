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
#include <iconv.h>

#include <SDL/SDL.h>
#include <SDL/SDL_mixer.h>
#include <SDL/SDL_ttf.h>
#define TEXT_SOLID      1
#define TEXT_SHADED     2
#define TEXT_BLENDED    4
#define UTF8_SOLID      8
#define UTF8_SHADED     16      
#define UTF8_BLENDED    32
#define UNICODE_SOLID   64
#define UNICODE_SHADED  128
#define UNICODE_BLENDED 256

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

        fclose(f);

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

SV* utf8key_(SDL_Event * e) {
        iconv_t cd;
        char source[2];
        char* retval = "";
        source[0] = e->key.keysym.unicode & 0xFF;
        source[1] = ( e->key.keysym.unicode & 0xFF00 ) >> 8;
        cd = iconv_open("UTF8", "UTF16LE");
        if (cd != (iconv_t) (-1)) {
                // an utf8 char is maximum 4 bytes long
                char dest[5];
                char *src = source;
                char *dst = dest;
                size_t source_len = 2;
                size_t dest_len = 4;
                bzero(dest, 5);
                if ((iconv(cd, &src, &source_len, &dst, &dest_len)) != (size_t) (-1)) {
                        *dst = 0;
                        retval = dest;
                }
        }
        iconv_close(cd);
        return newSVpv(retval, 0);
}

void TTFPutSt_() {
                printf("1\n");
                SDL_GetTicks();
                printf("1b\n");
                SDL_Delay(10);
                printf("1c\n");
                TTF_Init();
                printf("1d\n");
}

/************************** Gateway to Perl ****************************/

MODULE = fb_c_stuff		PACKAGE = fb_c_stuff

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
		     
SV *
utf8key(event)
  SDL_Event * event
  CODE:
  RETVAL = utf8key_(event);
  OUTPUT:
  RETVAL


SDL_Surface*
TTFPutString ( font, mode, surface, x, y, fg, bg, text )
	TTF_Font *font
	int mode
	SDL_Surface *surface
	int x
	int y
	SDL_Color *fg
	SDL_Color *bg
	char *text
	CODE:
		SDL_Surface *img;
		SDL_Rect dest;
		int w,h;
		dest.x = x;
		dest.y = y;
		RETVAL = NULL;
		switch (mode) {
			case TEXT_SOLID:
				img = TTF_RenderText_Solid(font,text,*fg);
				TTF_SizeText(font,text,&w,&h);
				dest.w = w;
				dest.h = h;
				break;
			case TEXT_SHADED:
				img = TTF_RenderText_Shaded(font,text,*fg,*bg);
				TTF_SizeText(font,text,&w,&h);
				dest.w = w;
				dest.h = h;
				break;
			case TEXT_BLENDED:
				img = TTF_RenderText_Blended(font,text,*fg);
				TTF_SizeText(font,text,&w,&h);
				dest.w = w;
				dest.h = h;
				break;
			case UTF8_SOLID:
				img = TTF_RenderUTF8_Solid(font,text,*fg);
				TTF_SizeUTF8(font,text,&w,&h);
				dest.w = w;
				dest.h = h;
				break;
			case UTF8_SHADED:
				img = TTF_RenderUTF8_Shaded(font,text,*fg,*bg);
				TTF_SizeUTF8(font,text,&w,&h);
				dest.w = w;
				dest.h = h;
				break;
			case UTF8_BLENDED:
				img = TTF_RenderUTF8_Blended(font,text,*fg);
				TTF_SizeUTF8(font,text,&w,&h);
				dest.w = w;
				dest.h = h;
				break;
			case UNICODE_SOLID:
				img = TTF_RenderUNICODE_Solid(font,(Uint16*)text,*fg);
				TTF_SizeUNICODE(font,(Uint16*)text,&w,&h);
				dest.w = w;
				dest.h = h;
				break;
			case UNICODE_SHADED:
				img = TTF_RenderUNICODE_Shaded(font,(Uint16*)text,*fg,*bg);
				TTF_SizeUNICODE(font,(Uint16*)text,&w,&h);
				dest.w = w;
				dest.h = h;
				break;
			case UNICODE_BLENDED:
				img = TTF_RenderUNICODE_Blended(font,(Uint16*)text,*fg);
				TTF_SizeUNICODE(font,(Uint16*)text,&w,&h);
				dest.w = w;
				dest.h = h;
				break;
			default:
				img = TTF_RenderText_Shaded(font,text,*fg,*bg);
				TTF_SizeText(font,text,&w,&h);
				dest.w = w;
				dest.h = h;
		}
		if ( img && img->format ) {
                        if ( img->format->palette ) {
                                SDL_Color *c = &img->format->palette->colors[0];
                                Uint32 key = SDL_MapRGB( img->format, c->r, c->g, c->b );
                                SDL_SetColorKey(img,SDL_SRCCOLORKEY,key );
                                if (0 > SDL_BlitSurface(img,NULL,surface,&dest)) {
                                        SDL_FreeSurface(img);
                                        RETVAL = NULL;	
                                } else {
                                        RETVAL = img;
                                }
                        } else {
                                if (0 > SDL_BlitSurface(img,NULL,surface,&dest)) {
                                        SDL_FreeSurface(img);
                                        RETVAL = NULL;	
                                } else {
                                        RETVAL = img;
                                }
                        }
		}
	OUTPUT:
		RETVAL
