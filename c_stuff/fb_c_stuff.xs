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
#include <math.h>
#include <sys/time.h>
#include <unistd.h>

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

#include <fontconfig/fontconfig.h>

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
        int bpp = img->format->BytesPerPixel;
        int in_or_out = rand_(2);

	while (step >= 0) {

		synchro_before(s);
		
		for (y=0; y<YRES; y++) {
                        void* src_line = img->pixels + y*img->pitch;
                        void* dest_line = s->pixels + y*img->pitch;
			for (x=0; x<XRES; x++) 
                                if (in_or_out == 1) {
                                        if (circle_steps[x+y*XRES] == step)
                                                memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
                                } else {
                                        if (circle_steps[x+y*XRES] == circle_max_steps - step)
                                                memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
                                }
                }
		step--;
				
		synchro_after(s);
	}

}


/* -------------- Plasma ------------------ */

unsigned char * plasma, * plasma2, * plasma3;
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
			plasma[x+y*XRES] = (plasma[x+y*XRES]*plasma_steps)/(plasma_max+1);


	plasma2 = malloc(XRES * YRES);
	if (!plasma2)
		fb__out_of_memory();
	for (i=0; i<XRES*YRES; i++)
		plasma2[i] = rand_(256) - 1;

	for (y=0; y<YRES; y++)
		for (x=0; x<XRES; x++)
			plasma2[x+y*XRES] = (plasma2[x+y*XRES]*plasma_steps)/256;

	plasma3 = malloc(XRES * YRES);
	if (!plasma3)
		fb__out_of_memory();
}

void plasma_effect(SDL_Surface * s, SDL_Surface * img)
{
	int step = 0;
        int bpp = img->format->BytesPerPixel;
        int rnd_plasma = rand_(4);

	int plasma_type;
        if (!img->format->palette) {
                plasma_type = rand_(3);
        } else {
                plasma_type = rand_(2);
        }

        if (plasma_type == 3) {
                int int_or_out = rand_(2);
                // pixel brightness
                for (y=0; y<YRES; y++)
                        for (x=0; x<XRES; x++) {
                                Uint32 pixelvalue = 0;
                                float r, g, b;
                                memcpy(&pixelvalue, img->pixels + y*img->pitch + x*bpp, bpp);
                                r = ( (float) ( ( pixelvalue & img->format->Rmask ) >> img->format->Rshift ) ) / ( img->format->Rmask >> img->format->Rshift );
                                g = ( (float) ( ( pixelvalue & img->format->Gmask ) >> img->format->Gshift ) ) / ( img->format->Gmask >> img->format->Gshift );
                                b = ( (float) ( ( pixelvalue & img->format->Bmask ) >> img->format->Bshift ) ) / ( img->format->Bmask >> img->format->Bshift );
                                plasma3[x+y*XRES] = 255 * ( r * .299 + g * .587 + b * .114 ) * plasma_steps / 256;
                                if (int_or_out == 1)
                                        plasma3[x+y*XRES] = plasma_steps - 1 - plasma3[x+y*XRES];
                        }
        }

	while (step < plasma_steps) {

		synchro_before(s);

		if (plasma_type == 1) {
                        // with plasma file
			/* I need to un-factorize the 'plasma' call in order to let gcc optimize (tested!) */
			for (y=0; y<YRES; y++) {
                                void* src_line = img->pixels + y*img->pitch;
                                void* dest_line = s->pixels + y*img->pitch;
				if (rnd_plasma == 1) {
					for (x=0; x<XRES; x++)
						if (plasma[x+y*XRES] == step)
                                                        memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
				}
				else if (rnd_plasma == 2) {
					for (x=0; x<XRES; x++)
						if (plasma[(XRES-1-x)+y*XRES] == step)
                                                        memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
				}
				else if (rnd_plasma == 3) {
					for (x=0; x<XRES; x++)
						if (plasma[x+(YRES-1-y)*XRES] == step)
                                                        memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
				}
				else {
					for (x=0; x<XRES; x++)
						if (plasma[(XRES-1-x)+(YRES-1-y)*XRES] == step)
                                                        memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
				}
                        }
		} else {
                        // random points or brightness
                        unsigned char* p = plasma_type == 2 ? plasma2 : plasma3;
			for (y=0; y<YRES; y++) {
                                void* src_line = img->pixels + y*img->pitch;
                                void* dest_line = s->pixels + y*img->pitch;
				for (x=0; x<XRES; x++)
					if (p[x+y*XRES] == step)
                                                memcpy(dest_line + x*bpp, src_line + x*bpp, bpp);
                        }
		}

		step++;
				
		synchro_after(s);
	}
}


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

struct timeval tv1;
struct timeval tv2;

void rotate_nearest_(SDL_Surface * dest, SDL_Surface * orig, double angle)
{
	int bpp = dest->format->BytesPerPixel;
        int x_, y_;
        double cosval = cos(angle);
        double sinval = sin(angle);
	if (orig->format->BytesPerPixel != dest->format->BytesPerPixel) {
                printf("rotate_nearest: orig and dest surface must be of equal bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        gettimeofday(&tv1, NULL);
        for (x = 0; x < dest->w; x++) {
                for (y = 0; y < dest->h; y++) {
                        x_ = (x - dest->w/2)*cosval - (y - dest->h/2)*sinval + dest->w/2;
                        y_ = (y - dest->h/2)*cosval + (x - dest->w/2)*sinval + dest->h/2;
                        if (x_ < 0 || x_ > dest->w - 2 || y_ < 0 || y_ > dest->h - 2) {
                                *( (Uint32*) ( dest->pixels + x*bpp + y*dest->pitch ) ) = orig->format->Amask;
                                continue;
                        }
                        memcpy(dest->pixels + x*bpp + y*dest->pitch,
                               orig->pixels + x_*bpp + y_*orig->pitch, bpp);
                }
        }
        gettimeofday(&tv2, NULL);
        printf("nearest: %ld usec (%.2f images/sec, %.2f Mpixels/sec)\n", tv2.tv_usec - tv1.tv_usec, 1/(((double)(tv2.tv_usec - tv1.tv_usec))/1000000), (dest->w*dest->h)/(((double)(tv2.tv_usec - tv1.tv_usec))/1000000)/1000000);
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void rotate_bilinear_(SDL_Surface * dest, SDL_Surface * orig, double angle)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint32 *ptr;
        int x_, y_;
        int r, g, b, a;
        float dx, dy;
        float cosval = cos(angle);
        float sinval = sin(angle);
	if (orig->format->BytesPerPixel != 4) {
                printf("rotate_bilinear: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                printf("rotate_bilinear: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        gettimeofday(&tv1, NULL);
        for (y = 0; y < dest->h; y++) {
                float x__ = - dest->w/2*cosval - (y - dest->h/2)*sinval + dest->w/2;
                float y__ = (y - dest->h/2)*cosval - dest->w/2*sinval + dest->h/2;
                ptr = dest->pixels + y*dest->pitch;
                for (x = 0; x < dest->w; x++) {
                        Uint32 *A, *B, *C, *D;
                        x_ = floor(x__);
                        y_ = floor(y__);
                        if (x_ < 0 || x_ > orig->w - 2 || y_ < 0 || y_ > orig->h - 2) {
                                // out of band
                                *ptr = 0;

                        } else {
                                dx = x__ - x_;
                                dy = y__ - y_;
                                A = orig->pixels + x_*Bpp     + y_*orig->pitch;
                                B = orig->pixels + (x_+1)*Bpp + y_*orig->pitch;
                                C = orig->pixels + x_*Bpp     + (y_+1)*orig->pitch;
                                D = orig->pixels + (x_+1)*Bpp + (y_+1)*orig->pitch;
#define getr(pixeladdr) ( *( (Uint8*) pixeladdr ) )
#define getg(pixeladdr) ( *( (Uint8*) pixeladdr + 1 ) )
#define getb(pixeladdr) ( *( (Uint8*) pixeladdr + 2 ) )
#define geta(pixeladdr) ( *( (Uint8*) pixeladdr + 3 ) )
                                a = (geta(A) * ( 1 - dx ) + geta(B) * dx) * ( 1 - dy ) + (geta(C) * ( 1 - dx ) + geta(D) * dx) * dy;
                                if (a == 0) {
                                        // fully transparent, no use working
                                        r = g = b = 0;
                                } else if (a == 255) {
                                        // fully opaque, optimized
                                        r = (getr(A) * ( 1 - dx ) + getr(B) * dx) * ( 1 - dy ) + (getr(C) * ( 1 - dx ) + getr(D) * dx) * dy;
                                        g = (getg(A) * ( 1 - dx ) + getg(B) * dx) * ( 1 - dy ) + (getg(C) * ( 1 - dx ) + getg(D) * dx) * dy;
                                        b = (getb(A) * ( 1 - dx ) + getb(B) * dx) * ( 1 - dy ) + (getb(C) * ( 1 - dx ) + getb(D) * dx) * dy;
                                } else {
                                        // not fully opaque, means A B C or D was not fully opaque, need to weight channels with
                                        r = ( (getr(A) * geta(A) * ( 1 - dx ) + getr(B) * geta(B) * dx) * ( 1 - dy ) + (getr(C) * geta(C) * ( 1 - dx ) + getr(D) * geta(D) * dx) * dy ) / a;
                                        g = ( (getg(A) * geta(A) * ( 1 - dx ) + getg(B) * geta(B) * dx) * ( 1 - dy ) + (getg(C) * geta(C) * ( 1 - dx ) + getg(D) * geta(D) * dx) * dy ) / a;
                                        b = ( (getb(A) * geta(A) * ( 1 - dx ) + getb(B) * geta(B) * dx) * ( 1 - dy ) + (getb(C) * geta(C) * ( 1 - dx ) + getb(D) * geta(D) * dx) * dy ) / a;
                                }
//                                *ptr = (r << orig->format->Rshift) + (g << orig->format->Gshift) + (b << orig->format->Bshift) + (a << orig->format->Ashift);
                                * ( ( (Uint8*) ptr ) ) = r;  // it is slightly faster to not recompose the 32-bit pixel - at least on my p4
                                * ( ( (Uint8*) ptr ) + 1 ) = g;
                                * ( ( (Uint8*) ptr ) + 2 ) = b;
                                * ( ( (Uint8*) ptr ) + 3 ) = a;
                        }
                        x__ += cosval;
                        y__ += sinval;
                        ptr++;
		}
	}
        gettimeofday(&tv2, NULL);
//        printf("bilinear: %ld usec (%.2f images/sec, %.2f Mpixels/sec)\n", tv2.tv_usec - tv1.tv_usec, 1/(((double)(tv2.tv_usec - tv1.tv_usec))/1000000), (dest->w*dest->h)/(((double)(tv2.tv_usec - tv1.tv_usec))/1000000)/1000000);
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

#define CLAMP(x, low, high)  (((x) > (high)) ? (high) : (((x) < (low)) ? (low) : (x)))

enum spline_type { CATMULL_ROM, B_SPLINE, LINEAR, SIMPLE_CUBIC };

/* access interleaved pixels */
#define CUBIC_ROW(dx, row, type) transform_cubic(dx, (row)[0], (row)[4], (row)[8], (row)[12], type)

#define CUBIC_SCALED_ROW(dx, row, arow, type) transform_cubic(dx, (arow)[0] * (row)[0], (arow)[4] * (row)[4], (arow)[8] * (row)[8], (arow)[12] * (row)[12], type)

static inline float
transform_cubic (float dx, int jm1, int j, int jp1, int jp2, int type)
{
        if (type == CATMULL_ROM) {
                // Catmull-Rom yields the best results
                return ((( (     - jm1 + 3 * j - 3 * jp1 + jp2 ) * dx +
                           (   2 * jm1 - 5 * j + 4 * jp1 - jp2 ) ) * dx +
                           (     - jm1             + jp1       ) ) * dx +
                           (             2 * j                 ) ) / 2.0;
        } else if (type == B_SPLINE) {
                return ((( (     - jm1 + 3 * j - 3 * jp1 + jp2 ) * dx +
                           (   3 * jm1 - 6 * j + 3 * jp1       ) ) * dx +
                           ( - 3 * jm1         + 3 * jp1       ) ) * dx +
                           (       jm1 + 4 * j     + jp1       ) ) / 6.0;
        } else if (type == LINEAR) {
                return  (( 
                           
                           (               - j     + jp1       ) ) * dx +
                           (                 j                 ) );
        } else if (type == SIMPLE_CUBIC) {
                return ((( (             2 * j - 2 * jp1       ) * dx +
                           (           - 3 * j + 3 * jp1       ) ) * dx  
                                                                 ) * dx +
                           (                 j                 ) );
        } else {
                return 0;
        }
}

void rotate_bicubic_(SDL_Surface * dest, SDL_Surface * orig, double angle, char* type)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptr;
        int x_, y_;
        float cosval = cos(angle);
        float sinval = sin(angle);
        float a_val, a_recip;
        int   i;
        float dx, dy;
        int itype;
        if (!strcmp(type, "catmull-rom")) {
                itype = CATMULL_ROM;
        } else if (!strcmp(type, "b-spline")) {
                itype = B_SPLINE;
        } else if (!strcmp(type, "linear")) {
                itype = LINEAR;
        } else if (!strcmp(type, "simple-cubic")) {
                itype = SIMPLE_CUBIC;
        } else {
                printf("rotate_bicubic: type not known\n");
                abort();
        }
	if (orig->format->BytesPerPixel != 4) {
                printf("rotate_bicubic: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                printf("rotate_bicubic: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        gettimeofday(&tv1, NULL);
        for (y = 0; y < dest->h; y++) {
                float x__ = - dest->w/2*cosval - (y - dest->h/2)*sinval + dest->w/2 - 1;
                float y__ = (y - dest->h/2)*cosval - dest->w/2*sinval + dest->h/2 - 1;
                ptr = dest->pixels + y*dest->pitch;
                for (x = 0; x < dest->w; x++) {
                        x_ = floor(x__);
                        y_ = floor(y__);
                        if (x_ == 50 && y_ == 67)
                                printf("pixel:%x\n", * ( (Uint32*) ( orig->pixels + x_*Bpp + y_*orig->pitch ) ));
                        if (x_ < 0 || x_ > orig->w - 4 || y_ < 0 || y_ > orig->h - 4) {
                                //*( (Uint32*) ptr ) = orig->format->Amask;

                        } else {
                                Uint8* origptr = orig->pixels + x_*Bpp + y_*orig->pitch;

                                /* the fractional error */
                                dx = x__ - x_;
                                dy = y__ - y_;
                                /* calculate alpha of result */
                                a_val = transform_cubic(dy,
                                                        CUBIC_ROW(dx, origptr + 3, itype),
                                                        CUBIC_ROW(dx, origptr + 3 + dest->pitch, itype),
                                                        CUBIC_ROW(dx, origptr + 3 + dest->pitch * 2, itype),
                                                        CUBIC_ROW(dx, origptr + 3 + dest->pitch * 3, itype),
                                                        itype);
                                if (a_val <= 0.0) {
                                        a_recip = 0.0; 
                                        *(ptr+3) = 0;
                                } else if (a_val > 255.0) {
                                        a_recip = 1.0 / a_val;
                                        *(ptr+3) = 255;
                                } else { 
                                        a_recip = 1.0 / a_val;
                                        *(ptr+3) = (int) a_val;
                                }
                                /* for RGB, result = bicubic (c * alpha) / bicubic (alpha) */
                                for (i = 0; i < 3; i++) { 
                                        int newval = a_recip * transform_cubic(dy,
                                                                               CUBIC_SCALED_ROW (dx, origptr + i,                   origptr + 3, itype),
                                                                               CUBIC_SCALED_ROW (dx, origptr + i + dest->pitch,     origptr + 3 + dest->pitch, itype),
                                                                               CUBIC_SCALED_ROW (dx, origptr + i + dest->pitch * 2, origptr + 3 + dest->pitch * 2, itype),
                                                                               CUBIC_SCALED_ROW (dx, origptr + i + dest->pitch * 3, origptr + 3 + dest->pitch * 3, itype),
                                                                               itype);
                                        *(ptr+i) = CLAMP (newval, 0, 255);
                                }
                        }
                        x__ += cosval;
                        y__ += sinval;
                        ptr += 4;
		}
	}
        gettimeofday(&tv2, NULL);
        printf("bicubic: %ld usec (%.2f images/sec, %.2f Mpixels/sec)\n", tv2.tv_usec - tv1.tv_usec, 1/(((double)(tv2.tv_usec - tv1.tv_usec))/1000000), (dest->w*dest->h)/(((double)(tv2.tv_usec - tv1.tv_usec))/1000000)/1000000);
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

void flipflop_(SDL_Surface * dest, SDL_Surface * orig, int offset)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptr;
        int r, g, b, a;
        float dx;
	if (orig->format->BytesPerPixel != 4) {
                printf("flipflop: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                printf("flipflop: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        gettimeofday(&tv1, NULL);
        for (x = 0; x < dest->w; x++) {
                float sinval = sin((2*x+offset)/50.0)*5;
                float shading = 1.1 + cos((2*x+offset)/50.0) / 10;  // based on sinval derivative
                float x__ = x + sinval;
                int x_ = floor(x__);
                ptr = dest->pixels + x*Bpp;
                for (y = 0; y < dest->h; y++) {
                        Uint32 *A, *B, *C, *D;
                        x_ = floor(x__);
                        if (x_ < 0 || x_ > orig->w - 2) {
                                // out of band
                                * ( (Uint32*) ptr ) = 0;

                        } else {
                                dx = x__ - x_;  // (mono)linear filtering
                                A = orig->pixels + x_*Bpp     + y*orig->pitch;
                                B = orig->pixels + (x_+1)*Bpp + y*orig->pitch;
                                C = orig->pixels + x_*Bpp     + (y+1)*orig->pitch;
                                D = orig->pixels + (x_+1)*Bpp + (y+1)*orig->pitch;
#define getr(pixeladdr) ( *( (Uint8*) pixeladdr ) )
#define getg(pixeladdr) ( *( (Uint8*) pixeladdr + 1 ) )
#define getb(pixeladdr) ( *( (Uint8*) pixeladdr + 2 ) )
#define geta(pixeladdr) ( *( (Uint8*) pixeladdr + 3 ) )
                                a = geta(A) * ( 1 - dx ) + geta(B) * dx;
                                if (a == 0) {
                                        // fully transparent, no use working
                                        r = g = b = 0;
                                } else if (a == 255) {
                                        // fully opaque, optimized
                                        r = getr(A) * ( 1 - dx ) + getr(B) * dx;
                                        g = getg(A) * ( 1 - dx ) + getg(B) * dx;
                                        b = getb(A) * ( 1 - dx ) + getb(B) * dx;
                                } else {
                                        // not fully opaque, means A B C or D was not fully opaque, need to weight channels with
                                        r = (getr(A) * geta(A) * ( 1 - dx ) + getr(B) * geta(B) * dx) / a;
                                        g = (getg(A) * geta(A) * ( 1 - dx ) + getg(B) * geta(B) * dx) / a;
                                        b = (getb(A) * geta(A) * ( 1 - dx ) + getb(B) * geta(B) * dx) / a;
                                }
                                r = CLAMP(r*shading, 0, 255);
                                g = CLAMP(g*shading, 0, 255);
                                b = CLAMP(b*shading, 0, 255);
                                * ( ptr ) = r;  // it is slightly faster to not recompose the 32-bit pixel - at least on my p4
                                * ( ptr + 1 ) = g;
                                * ( ptr + 2 ) = b;
                                * ( ptr + 3 ) = a;
                        }
                        ptr += dest->pitch;
		}
	}
        gettimeofday(&tv2, NULL);
//        printf("bilinear: %ld usec (%.2f images/sec, %.2f Mpixels/sec)\n", tv2.tv_usec - tv1.tv_usec, 1/(((double)(tv2.tv_usec - tv1.tv_usec))/1000000), (dest->w*dest->h)/(((double)(tv2.tv_usec - tv1.tv_usec))/1000000)/1000000);
	myUnlockSurface(orig);
	myUnlockSurface(dest);
}

float sqr(float a) { return a*a; }

void enlighten_(SDL_Surface * dest, SDL_Surface * orig, int offset)
{
	int Bpp = dest->format->BytesPerPixel;
        Uint8 *ptrdest, *ptrorig;
        int lightx, lighty;
        float sqdistbase, sqdist, shading;
	if (orig->format->BytesPerPixel != 4) {
                printf("enlighten: orig surface must be 32bpp\n");
                abort();
        }
	if (dest->format->BytesPerPixel != 4) {
                printf("enlighten: dest surface must be 32bpp\n");
                abort();
        }
	myLockSurface(orig);
	myLockSurface(dest);
        lightx = dest->w/(2.5+0.3*sin((float)offset/500)) * sin((float)offset/100) + dest->w/2;
        lighty = dest->h/(2.5+0.3*cos((float)offset/500)) * cos((float)offset/100) + dest->h/2 + 10;
        for (y = 0; y < dest->h; y++) {
                ptrdest = dest->pixels + y*dest->pitch;
                ptrorig = orig->pixels + y*orig->pitch;
                sqdistbase = sqr(y - lighty) - 3;
                if (y == lighty)
                        sqdistbase -= 4;
                for (x = 0; x < dest->w; x++) {
                        sqdist = sqdistbase + sqr(x - lightx);
                        if (x == lightx)
                                sqdist -= 2;
                        shading = sqdist <= 0 ? 50 : 1 + 20/sqdist;
                        if (shading >= 1.03) {
                                * ( ptrdest ) = CLAMP(*( ptrorig )*shading, 0, 255);
                                * ( ptrdest + 1 ) = CLAMP(*( ptrorig + 1 )*shading, 0, 255);
                                * ( ptrdest + 2 ) = CLAMP(*( ptrorig + 2 )*shading, 0, 255);
                                * ( ptrdest + 3 ) = *( ptrorig + 3 );
                        } else {
                                * ( (Uint32*) ptrdest ) = *( (Uint32*) ptrorig );
                        }
                        ptrdest += Bpp;
                        ptrorig += Bpp;
		}
	}
	myUnlockSurface(orig);
	myUnlockSurface(dest);
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

SV* locatefont_(char *pattern) {
        FcFontSet   *fs;
        FcPattern   *pat;
        FcPattern   *match;
        FcResult    result;
        SV* retval = NULL;

        if (!FcInit()) {
                fprintf(stderr, "Ouch, can't init font config library\n");
                exit(1);
        }

        pat = FcNameParse((FcChar8 *) pattern);
        if (!pat) {
                fprintf(stderr, "Failed to parse pattern (%s)\n", pattern);
                exit(1);
        }

        FcConfigSubstitute(0, pat, FcMatchPattern);
        FcDefaultSubstitute(pat);
        fs = FcFontSetCreate();
        match = FcFontMatch(0, pat, &result);
        if (match)
            FcFontSetAdd(fs, match);
        FcPatternDestroy(pat);

        if (fs) {
                if (fs->nfont > 0) {
                        FcChar8 *file;
                        if (FcPatternGetString(fs->fonts[0], FC_FONTFORMAT, 0, &file) == FcResultMatch) {
                                if (!strcmp((char*)file, "TrueType")) {
                                        if (FcPatternGetString(fs->fonts[0], FC_FILE, 0, &file) == FcResultMatch) {
                                                retval = newSVpv((char*)file, 0);
                                        }
                                }
                        }
                }
                FcFontSetDestroy(fs);
        }

        return retval;
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
		int randvalue = rand_(8);
		if (randvalue == 1 || randvalue == 2)
			store_effect(s, img);
		else if (randvalue == 3 || randvalue == 4 || randvalue == 5)
			plasma_effect(s, img);
                else if (randvalue == 6)
			circle_effect(s, img);
		else if (randvalue == 7)
			bars_effect(s, img);
		else
                        squares_effect(s, img);

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
rotate_nearest(dest, orig, angle)
        SDL_Surface * dest
        SDL_Surface * orig
        double angle
	CODE:
		rotate_nearest_(dest, orig, angle);

void
rotate_bilinear(dest, orig, angle)
        SDL_Surface * dest
        SDL_Surface * orig
        double angle
	CODE:
		rotate_bilinear_(dest, orig, angle);

void
rotate_bicubic(dest, orig, angle, type)
        SDL_Surface * dest
        SDL_Surface * orig
        double angle
        char* type
	CODE:
		rotate_bicubic_(dest, orig, angle, type);

void
flipflop(dest, orig, offset)
        SDL_Surface * dest
        SDL_Surface * orig
        int offset
	CODE:
		flipflop_(dest, orig, offset);

void
enlighten(dest, orig, offset)
        SDL_Surface * dest
        SDL_Surface * orig
        int offset
	CODE:
		enlighten_(dest, orig, offset);

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


SV *
locatefont(pattern)
  char *pattern
  CODE:
  RETVAL = locatefont_(pattern);
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
