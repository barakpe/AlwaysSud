/* Cycle-accurate model of alwaysud_solver's FSM, run to completion on hard1.
   INIT 1; FIND_EMPTY 1/cell inspected; TRY_VAL 1/digit tested (+1 for val>9); BACKTRACK 1. */
#include <stdio.h>
#include <string.h>
static int g[81];
static int ok(int r,int c,int v){
    int k,dr,dc,br=(r/3)*3,bc=(c/3)*3;
    for(k=0;k<9;k++){ if(g[r*9+k]==v) return 0; if(g[k*9+c]==v) return 0; }
    for(dr=0;dr<3;dr++) for(dc=0;dc<3;dc++) if(g[(br+dr)*9+bc+dc]==v) return 0;
    return 1;
}
int main(int argc,char**argv){
    FILE*f=fopen(argv[1],"r"); int i,v;
    for(i=0;i<81;i++){ if(fscanf(f,"%x",&v)!=1){printf("parse err\n");return 1;} g[i]=v; }
    fclose(f);
    int sr[81],sc[81],sv[81],sp=0;
    int row=0,col=0,val=1;
    long long cyc=1, checks=0, backs=0, finds=0, tries=0;
    enum{FIND,TRY,BACK} st=FIND;
    for(;;){
        if(st==FIND){
            cyc++; finds++;
            if(g[row*9+col]==0){ val=1; st=TRY; }
            else { if(col==8){ if(row==8){ cyc++; break; } col=0; row++; } else col++; }
        } else if(st==TRY){
            cyc++; tries++;
            if(val>9){ g[row*9+col]=0; st=BACK; }
            else { checks++;
                if(ok(row,col,val)){ g[row*9+col]=val; sr[sp]=row; sc[sp]=col; sv[sp]=val; sp++; val=1; st=FIND; }
                else val++; }
        } else {
            cyc++; backs++;
            if(sp==0){ printf("NO SOLUTION\n"); return 2; }
            sp--; row=sr[sp]; col=sc[sp]; val=sv[sp]+1; st=TRY;
        }
    }
    printf("cycles      %lld\n", cyc);
    printf("checks      %lld\n", checks);
    printf("backtracks  %lld\n", backs);
    printf("find steps  %lld\n", finds);
    printf("try steps   %lld\n", tries);
    printf("grid        "); for(i=0;i<81;i++) printf("%d", g[i]); printf("\n");
    return 0;
}
