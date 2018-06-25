// dtexpand 2017-03-10 18:00
//
// expands the dirty-tiles list as provided by osm2pgsql
// example: dtexpand 4 17 <dirty_tiles >dirty_tiles_ex
// (c) 2017 Markus Weber, Nuernberg, License LGPLv3
#include <ctype.h>
#include <inttypes.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

int main(int argc,char** argv) {
  int fieldedge[20];
  uint8_t* field[20],*fieldend[20];
  int zoom_min,zoom_max,zoom_sub;
  int z,x,y,zz,xx,yy,xd,yd,q; uint64_t u;
  uint8_t b; uint8_t* bp,*bpa,*bpe;
  char line[40]; char* sp;
  typedef struct {int zs,tx_min,tx_max,ty_min,ty_max;} sub_t;
  sub_t* sub,*subp; int subn;

  if(argc<3 || (argc-3)%5!=0) { fprintf(stderr,
    "Usage: dtexpand ZOOM_MIN ZOOM_MAX <DT_IN >DT_OUT\n"
    "Optional value sets each: ZOOM_SUB TX_MIN TX_MAX TY_MIN TY_MAX\n"
    "         ZOOM_SUB: max zoom level for blindly adding subtiles\n"
    "         TX...TY: concerning tile range at ZOOM_MAX level\n"
      ); return 1; }
  zoom_min= atoi(argv[1]); zoom_max= atoi(argv[2]);
  subn= (argc-3)/5;
  sub= (sub_t*)malloc(sizeof(sub_t)*(subn+1));
  argv+= 2; subp= sub;
  for(z= 0;z<subn;z++) {  // for each subtile value set
    subp->zs= atoi(*++argv);
    subp->tx_min= atoi(*++argv); subp->tx_max= atoi(*++argv);
    subp->ty_min= atoi(*++argv); subp->ty_max= atoi(*++argv);
    if(zoom_min<0 || zoom_min>19 || zoom_max<zoom_min || zoom_max>19 ||
        subp->zs<=zoom_max || subp->zs>19) { fprintf(stderr,
        "Unsupported zoom value(s).\n"); return 2; }
    subp++; }  // for each subtile value set
  subp->zs= 0;
  for(z= zoom_max-1;z>=zoom_min;z--) {  // for each zoom level
    fieldedge[z]= u= UINT32_C(1)<<z; u= u*u+7>>3;
    if((field[z]= (uint8_t*) malloc(u))==NULL) { fprintf(stderr,
      "Not enough main memory.\n"); return 3; }
    memset(field[z],0,u);
    fieldend[z]= field[z]+u;
    }  // for each zoom level
  while(fgets(line,sizeof(line),stdin)!=NULL) {  // for each input line
    sp= line;
    z= 0; while(isdigit(*sp)) z= z*10+*sp++-'0'; if(*sp=='/') sp++;
    x= 0; while(isdigit(*sp)) x= x*10+*sp++-'0'; if(*sp=='/') sp++;
    y= 0; while(isdigit(*sp)) y= y*10+*sp++-'0';
    if(z<zoom_min || z>zoom_max)
  continue;
    zz= z-1; xx= x>>1; yy= y>>1;
    while(zz>=zoom_min) {  // for all lower zoom levels
      u= xx; u*= fieldedge[zz]; u+= yy; bp= &field[zz][u/8];
      if(bp<fieldend[zz]) *bp|= 1<<(u&7);  // (preventing overflow)
      zz--; xx>>= 1; yy>>= 1;
      }  // for all lower zoom levels
    q= 1;
    do {  // for this and all higher zoom levels
      for(xd= 0;xd<q;xd++) for(yd= 0;yd<q;yd++) {  // all these tiles
        xx= x+xd; yy= y+yd;
        if(z<zoom_max) {
          u= xx; u*= fieldedge[z]; u+= yy; bp= &field[z][u/8];
          if(bp<fieldend[z]) *bp|= 1<<(u&7);  // (preventing overflow)
          }
        else {  // at zoom_max level
          printf("%i/%i/%i\n",z,xx,yy);
          // determine relevant subtile zoom level 
          zoom_sub= zoom_max;
          subp= sub;
          while(subp->zs!=0) {  // for each subtile value set
            if(subp->zs>zoom_sub &&
                xx>=subp->tx_min && xx<=subp->tx_max &&
                yy>=subp->ty_min && yy<=subp->ty_max) zoom_sub= subp->zs;
            subp++; }  // for each subtile value set
          // write subtiles
          int xxd,yyd,qq;
          zz= z; qq= 1;
          while(zz<zoom_sub) {  // for each subtile level
            zz++; xx<<= 1; yy<<= 1; qq<<= 1;
            for(xxd= 0;xxd<qq;xxd++) for(yyd= 0;yyd<qq;yyd++)
              printf("%i/%i/%i\n",zz,xx+xxd,yy+yyd);
            }  // for each subtile level
          }  // at zoom_max level
        }  // all these tiles
      z++; x<<= 1; y<<= 1; q<<= 1;
      } while(z<=zoom_max);  // for this and all higher zoom levels
    }  // for each input line
  for(z= zoom_max-1;z>=zoom_min;z--) {  // for each zoom level
    bp= bpa= field[z]; bpe= fieldend[z];
    do {  // for each byte in bitfield
      b= *bp;
      if(b) {  // at least one bit in byte is set
        int be= fieldedge[z];
        for(int bi=0;bi<8;bi++) {  // for each bit in byte
          if(b&1) {  // bit is set
            u= (bp-bpa)*8+bi; x= u/be; y= u&be-1;
            printf("%i/%i/%i\n",z,x,y);
            }  // bit is set
          b>>= 1;
          }  // for each bit in byte
        }  // at least one bit in byte is set
      } while(++bp<bpe);  // for each byte in bitfield
    free(field[z]);
    }  // for each zoom level
  free(sub); return 0;
  }  // main()
