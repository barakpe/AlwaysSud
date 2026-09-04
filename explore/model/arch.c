/* arch.c - event-counting models of candidate solver architectures.
 *
 * WHY EVENTS AND NOT JUST CYCLES: each architecture is described by how many times
 * it enters each FSM state. Cycles are events x a per-state cost the RTL fixes.
 * Keeping them separate is what lets a cycle prediction be *validated* against
 * simulation rather than asserted.
 *
 * The geometry is a units table, the same shape as bench/units.py, so every
 * architecture here is variant-clean by construction: classic 27 units, diagonal
 * (X-Sudoku) 29, windoku 31. Nothing below does /3 arithmetic.
 *
 * THE LADDER - each rung adds exactly one mechanism to the one before it:
 *   v0   raster DFS, 1 digit trial per cycle, 1 cell scan per cycle   (the baseline)
 *   m1   + used-masks and priority encoders          -> 1 cycle per node, same tree
 *   s0   + forward check (any empty cell with 0 candidates -> fail)
 *   s1   + naked singles placed as forced, non-branching moves
 *   s2   + hidden singles likewise
 *   s2m  + MRV for the cell to guess at when nothing is forced
 *   m2   m1 + MRV only (no singles, no propagation) - the other single-step branch
 *   p*   parallel-commit variants: every forced cell placed in ONE cycle
 *
 * usage: arch <arch> <board> [--variant classic|diagonal|windoku] [--quiet]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NC 81
#define MAXU 32
#define ALL 0x1FF

static int NU;
static int unit[MAXU][9];
static int uof[NC][6];
static int nuof[NC];

static void add_unit(const int *cells) {
    for (int k = 0; k < 9; k++) { int c = cells[k]; unit[NU][k] = c; uof[c][nuof[c]++] = NU; }
    NU++;
}
static void build_units(const char *variant) {
    int t[9]; NU = 0; memset(nuof, 0, sizeof nuof);
    for (int r = 0; r < 9; r++) { for (int c = 0; c < 9; c++) t[c] = r*9+c; add_unit(t); }
    for (int c = 0; c < 9; c++) { for (int r = 0; r < 9; r++) t[r] = r*9+c; add_unit(t); }
    for (int b = 0; b < 9; b++) { int br=(b/3)*3, bc=(b%3)*3;
        for (int k = 0; k < 9; k++) t[k] = (br+k/3)*9 + bc + k%3; add_unit(t); }
    if (!strcmp(variant, "diagonal")) {
        for (int i = 0; i < 9; i++) t[i] = i*9+i;     add_unit(t);
        for (int i = 0; i < 9; i++) t[i] = i*9+(8-i); add_unit(t);
    } else if (!strcmp(variant, "windoku")) {
        int brs[2]={1,5}, bcs[2]={1,5};
        for (int a=0;a<2;a++) for (int b=0;b<2;b++) {
            for (int k=0;k<9;k++) t[k]=(brs[a]+k/3)*9+bcs[b]+k%3; add_unit(t); }
    } else if (strcmp(variant, "classic")) { fprintf(stderr,"unknown variant %s\n",variant); exit(2); }
}

typedef struct {
    long long init, find, try_, advance, backtrack, prop, undo;
    long long nodes, guesses, forced, contradict;
    int maxdepth, solved;
} ev_t;

static int val[NC], lvl[NC], used[MAXU];
static long long CAP = 0;      /* 0 = no cap */
static long long CYC;          /* events so far, for the cap only */
#define CAPPED (CAP && ++CYC > CAP)

static inline int allowed(int c) {
    int m = ALL;
    for (int k = 0; k < nuof[c]; k++) m &= ~used[uof[c][k]];
    return m;
}
static inline int lowbit(int m){ return m & -m; }
static inline int bit2dig(int b){ int d=0; while (b>>=1) d++; return d+1; }
static inline int popc(int m){ int n=0; while(m){m&=m-1;n++;} return n; }
static void rebuild_used(void){
    for (int u=0;u<NU;u++) used[u]=0;
    for (int c=0;c<NC;c++) if (val[c])
        for (int k=0;k<nuof[c];k++) used[uof[c][k]] |= 1<<(val[c]-1);
}
static inline void place(int c,int b){ val[c]=bit2dig(b);
    for(int k=0;k<nuof[c];k++) used[uof[c][k]] |= b; }
static inline void unplace(int c){ int b=1<<(val[c]-1);
    for(int k=0;k<nuof[c];k++) used[uof[c][k]] &= ~b; val[c]=0; }

/* ================= v0: the measured baseline ============================= */
static void run_v0(const int *start, ev_t *e) {
    int sr[NC], sv[NC], sp=0, cell=0, d=1;
    for (int c=0;c<NC;c++) val[c]=start[c];
    e->init = 1;
    enum { FIND, TRY, BACK } st = FIND;
    for (;;) {
        if (CAPPED) { e->solved = -1; return; }
        if (st==FIND) { e->find++;
            if (!val[cell]) { d=1; st=TRY; }
            else if (cell==80) { e->solved=1; return; } else cell++;
        } else if (st==TRY) { e->try_++;
            if (d>9) { val[cell]=0; st=BACK; }
            else { int ok=1;
                for (int k=0;k<nuof[cell]&&ok;k++)
                    for (int j=0;j<9;j++) if (val[unit[uof[cell][k]][j]]==d){ok=0;break;}
                if (ok){ val[cell]=d; sr[sp]=cell; sv[sp]=d; sp++;
                         if(sp>e->maxdepth)e->maxdepth=sp; e->nodes++; d=1; st=FIND; }
                else d++; }
        } else { e->backtrack++;
            if (sp==0){ e->solved=0; return; }
            sp--; cell=sr[sp]; d=sv[sp]+1; st=TRY; }
    }
}

/* ============ serial archs: one placement or one pop per cycle =========== */
/* sel  : cell chosen when nothing is forced.  0 = raster first-empty, 1 = MRV  */
/* fc   : 1 = forward check, any empty cell with an empty domain -> backtrack   */
/* naked: 1 = a cell with exactly one candidate is placed as a forced move      */
/* hid  : 1 = a digit with exactly one home in a unit is placed as a forced move*/
static void run_serial(const int *start, ev_t *e, int sel, int fc, int naked, int hid) {
    int sc[NC], sd[NC], sf[NC], sp = 0;   /* cell / digit / was-forced */
    for (int c=0;c<NC;c++) val[c]=start[c];
    rebuild_used(); e->init = 1;
    int backtracking = 0;
    for (;;) {
        if (CAPPED) { e->solved = -1; return; }
        if (!backtracking) {
            e->advance++;
            int pickc = -1, pickb = 0, isforced = 0, dead = 0;
            int nempty = 0, first = -1, best = -1, bestn = 10;
            for (int c=0;c<NC;c++) {
                if (val[c]) continue;
                nempty++;
                int a = allowed(c);
                if (first < 0) first = c;
                if (fc && a == 0) { dead = 1; break; }
                if (naked && pickc < 0 && a && !(a & (a-1))) { pickc = c; pickb = a; isforced = 1; }
                if (sel == 1) { int n = popc(a); if (n < bestn) { bestn = n; best = c; } }
            }
            if (dead) { e->contradict++; backtracking = 1; continue; }
            if (!nempty) { e->solved = 1; return; }
            if (pickc < 0 && hid) {
                for (int u=0; u<NU && pickc<0 && !dead; u++)
                    for (int d=1; d<=9; d++) {
                        int b = 1<<(d-1);
                        if (used[u] & b) continue;
                        int spot=-1, n=0;
                        for (int k=0;k<9;k++){ int c=unit[u][k];
                            if (!val[c] && (allowed(c)&b)) { spot=c; n++; if(n>1) break; } }
                        if (n==0){ dead=1; break; }
                        if (n==1){ pickc=spot; pickb=b; isforced=1; break; }
                    }
                if (dead) { e->contradict++; backtracking = 1; continue; }
            }
            if (pickc < 0) {                       /* nothing forced: guess */
                pickc = (sel == 1) ? best : first;
                pickb = lowbit(allowed(pickc));
                if (!pickb) { e->contradict++; backtracking = 1; continue; }
                isforced = 0; e->guesses++;
            } else e->forced++;
            place(pickc, pickb);
            sc[sp]=pickc; sd[sp]=bit2dig(pickb); sf[sp]=isforced; sp++;
            if (sp>e->maxdepth) e->maxdepth=sp;
            e->nodes++;
        } else {
            e->backtrack++;
            if (sp==0){ e->solved=0; return; }
            int c=sc[sp-1], d=sd[sp-1], f=sf[sp-1];
            unplace(c);
            if (f) { sp--; continue; }             /* forced: no alternative to try */
            int m = allowed(c) & ~((1<<d)-1);
            if (m) { int nb=lowbit(m); place(c,nb); sd[sp-1]=bit2dig(nb);
                     e->nodes++; e->guesses++; backtracking=0; }
            else sp--;
        }
    }
}


/* ---- s2u: the "unified one-hot" rule the s2fast RTL implements ------------
 * s2 asks three questions in sequence (empty domain? naked single? hidden
 * single?) and each answer is an index that then has to be decoded again to
 * reach the cell. The measured m1 critical path was exactly that encode-then-
 * decode round trip, so s2fast never forms an index on the decision path: it
 * marks every cell that is forced, for any reason, and takes the lowest one.
 *
 * That makes the contradiction test global (any empty cell with no candidate,
 * OR any unit-digit with no home), which prunes slightly harder than s2. Same
 * search, different tie-break; the numbers are what say whether it costs.
 */
static void run_unified(const int *start, ev_t *e, int sel) {
    int sc[NC], sd[NC], sf[NC], sp = 0;
    for (int c=0;c<NC;c++) val[c]=start[c];
    rebuild_used(); e->init = 1;
    int backtracking = 0;
    for (;;) {
        if (CAPPED) { e->solved = -1; return; }
        if (!backtracking) {
            e->advance++;
            int a[NC], forced[NC], dead = 0, nempty = 0;
            for (int c=0;c<NC;c++) {
                forced[c] = 0;
                if (val[c]) { a[c] = 0; continue; }
                nempty++;
                a[c] = allowed(c);
                if (a[c] == 0) dead = 1;
                else if (!(a[c] & (a[c]-1))) forced[c] = a[c];   /* naked single */
            }
            if (!nempty) { e->solved = 1; return; }
            if (!dead) {
                for (int u = 0; u < NU; u++)
                    for (int d = 1; d <= 9; d++) {
                        int b = 1 << (d-1);
                        if (used[u] & b) continue;
                        int spot = -1, n = 0;
                        for (int k = 0; k < 9; k++) {
                            int c = unit[u][k];
                            if (!val[c] && (a[c] & b)) { spot = c; n++; }
                        }
                        if (n == 0) { dead = 1; }
                        else if (n == 1) forced[spot] |= b;      /* hidden single */
                    }
            }
            if (dead) { e->contradict++; backtracking = 1; continue; }
            int pickc = -1, best = -1, bestn = 10, first = -1;
            for (int c = 0; c < NC; c++) {
                if (val[c]) continue;
                if (first < 0) first = c;
                if (pickc < 0 && forced[c]) pickc = c;
                if (sel == 1) { int n = popc(a[c]); if (n < bestn) { bestn = n; best = c; } }
            }
            int pickb, isf;
            if (pickc >= 0) { pickb = lowbit(forced[pickc]); isf = 1; e->forced++; }
            else { pickc = (sel == 1) ? best : first;
                   pickb = lowbit(a[pickc]); isf = 0; e->guesses++; }
            place(pickc, pickb);
            sc[sp]=pickc; sd[sp]=bit2dig(pickb); sf[sp]=isf; sp++;
            if (sp>e->maxdepth) e->maxdepth=sp;
            e->nodes++;
        } else {
            e->backtrack++;
            if (sp==0){ e->solved=0; return; }
            int c=sc[sp-1], d=sd[sp-1], f=sf[sp-1];
            unplace(c);
            if (f) { sp--; continue; }
            int m = allowed(c) & ~((1<<d)-1);
            if (m) { int nb=lowbit(m); place(c,nb); sd[sp-1]=bit2dig(nb);
                     e->nodes++; e->guesses++; backtracking=0; }
            else sp--;
        }
    }
}

/* ======== parallel-commit propagation: every forced cell in ONE cycle ===== */
static void run_prop(const int *start, ev_t *e, int hid, int sel) {
    int dc[NC], dd[NC]; int L = 0;
    for (int c=0;c<NC;c++){ val[c]=start[c]; lvl[c]=0; }
    rebuild_used(); e->init = 1;
    for (;;) {
        int bad = 0;
        for (;;) {
            if (CAPPED) { e->solved = -1; return; }
            e->prop++;
            int force[NC]; for (int c=0;c<NC;c++) force[c]=0;
            for (int c=0;c<NC;c++) { if (val[c]) continue; int a=allowed(c);
                if (!a){ bad=1; break; } if (!(a&(a-1))) force[c]=a; }
            if (bad) break;
            if (hid) { for (int u=0;u<NU && !bad;u++) for (int d=1;d<=9;d++){
                    int b=1<<(d-1); if (used[u]&b) continue;
                    int spot=-1,n=0;
                    for (int k=0;k<9;k++){ int c=unit[u][k];
                        if(!val[c] && (allowed(c)&b)){spot=c;n++;if(n>1)break;} }
                    if (n==0){ bad=1; break; } if (n==1) force[spot]|=b; }
                if (bad) break; }
            int nset=0;
            for (int c=0;c<NC;c++){ if(!force[c])continue;
                if (force[c]&(force[c]-1)){ bad=1; break; } nset++; }
            if (bad) break;
            if (!nset) break;
            for (int u=0;u<NU && !bad;u++){ int seen=0;
                for (int k=0;k<9;k++){ int c=unit[u][k];
                    if (force[c]){ if (seen&force[c]){bad=1;break;} seen|=force[c]; } } }
            if (bad) break;
            for (int c=0;c<NC;c++) if (force[c]) {
                val[c]=bit2dig(force[c]); lvl[c]=L; e->nodes++; e->forced++;
                for (int k=0;k<nuof[c];k++) used[uof[c][k]] |= force[c]; }
        }
        if (bad) {
            e->contradict++;
            for (;;) {
                if (CAPPED) { e->solved = -1; return; }
                e->undo++;
                if (L==0){ e->solved=0; return; }
                for (int c=0;c<NC;c++) if (lvl[c]>=L){ val[c]=0; lvl[c]=0; }
                rebuild_used();
                int c=dc[L], d=dd[L];
                int m = allowed(c) & ~((1<<d)-1);
                if (m){ int b=lowbit(m); val[c]=bit2dig(b); lvl[c]=L; dd[L]=val[c];
                        for(int k=0;k<nuof[c];k++) used[uof[c][k]]|=b;
                        e->nodes++; e->guesses++; break; }
                L--;
            }
            continue;
        }
        int best=-1, bestn=10;
        for (int c=0;c<NC;c++){ if(val[c])continue; int n=popc(allowed(c));
            if (sel==0){best=c;break;} if(n<bestn){bestn=n;best=c;} }
        if (best<0){ e->solved=1; return; }
        e->advance++; e->guesses++;
        L++; if (L>e->maxdepth) e->maxdepth=L;
        int b=lowbit(allowed(best));
        val[best]=bit2dig(b); lvl[best]=L;
        for(int k=0;k<nuof[best];k++) used[uof[best][k]]|=b;
        dc[L]=best; dd[L]=val[best]; e->nodes++;
    }
}

/* ------------------------------------------------------------------ */
static void read_board(const char *path, int *out) {
    FILE *f = fopen(path,"r");
    if (!f){ fprintf(stderr,"cannot open %s\n",path); exit(2); }
    char buf[65536]; size_t n=fread(buf,1,sizeof buf-1,f); buf[n]=0; fclose(f);
    /* course format = whitespace-separated 2-char hex bytes; compact = 81 chars of 0-9/. */
    int hexish = 1, tok = 0;
    for (size_t i=0;i<n;) {
        while (i<n && (buf[i]==' '||buf[i]=='\n'||buf[i]=='\r'||buf[i]=='\t')) i++;
        if (i>=n) break;
        size_t j=i; while (j<n && !(buf[j]==' '||buf[j]=='\n'||buf[j]=='\r'||buf[j]=='\t')) j++;
        if (j-i != 2) hexish = 0;
        tok++; i=j;
    }
    int cnt=0;
    if (hexish && tok==NC) {
        const char *p=buf;
        while (cnt<NC) {
            while (*p==' '||*p=='\n'||*p=='\r'||*p=='\t') p++;
            if (!*p) break;
            int v=0,k=0;
            while (*p && *p!=' ' && *p!='\n' && *p!='\r' && *p!='\t'){
                v=v*16+(*p<='9'?*p-'0':(*p|32)-'a'+10); p++; k++; }
            if (k) out[cnt++]=v;
        }
    } else {
        for (size_t i=0;i<n && cnt<NC;i++){ char ch=buf[i];
            if (ch=='.'||ch=='0') out[cnt++]=0;
            else if (ch>='1'&&ch<='9') out[cnt++]=ch-'0'; }
    }
    if (cnt!=NC){ fprintf(stderr,"%s: got %d cells\n",path,cnt); exit(2); }
}


typedef void (*runner_t)(const int*, ev_t*);
static const char *g_arch;
static void dispatch(const int *start, ev_t *e) {
    if      (!strcmp(g_arch,"v0"))  run_v0(start,e);
    else if (!strcmp(g_arch,"m1"))  run_serial(start,e,0,0,0,0);
    else if (!strcmp(g_arch,"s0"))  run_serial(start,e,0,1,0,0);
    else if (!strcmp(g_arch,"s1"))  run_serial(start,e,0,1,1,0);
    else if (!strcmp(g_arch,"s2"))  run_serial(start,e,0,1,1,1);
    else if (!strcmp(g_arch,"s2m")) run_serial(start,e,1,1,1,1);
    else if (!strcmp(g_arch,"m2"))  run_serial(start,e,1,1,0,0);
    else if (!strcmp(g_arch,"s2u")) run_unified(start,e,0);
    else if (!strcmp(g_arch,"s2um"))run_unified(start,e,1);
    else if (!strcmp(g_arch,"p1"))  run_prop(start,e,0,0);
    else if (!strcmp(g_arch,"p2"))  run_prop(start,e,0,1);
    else if (!strcmp(g_arch,"p3"))  run_prop(start,e,1,0);
    else if (!strcmp(g_arch,"p4"))  run_prop(start,e,1,1);
    else { fprintf(stderr,"unknown arch %s\n",g_arch); exit(2); }
}

static long long cycles_of(const ev_t *e) {
    return e->init + e->find + e->try_ + e->advance + e->backtrack + e->prop + e->undo + 1;
}

/* returns 0 ok, 1 illegal/incomplete, 2 capped-out */
static int check(const int *start, const ev_t *e) {
    if (e->solved < 0) return 2;
    if (!e->solved)    return 1;
    for (int c=0;c<NC;c++) if(!val[c]) return 1;
    for (int u=0;u<NU;u++){int s=0;for(int k=0;k<9;k++){int b=1<<(val[unit[u][k]]-1);
        if(s&b)return 1; s|=b;}}
    for (int c=0;c<NC;c++) if(start[c]&&val[c]!=start[c]) return 1;
    return 0;
}

static int cmpll(const void*a,const void*b){ long long x=*(long long*)a,y=*(long long*)b;
    return x<y?-1:x>y?1:0; }

int main(int argc, char **argv) {
    if (argc<3){ fprintf(stderr,
        "usage: arch <arch> <board>            [--variant v] [--cap N] [--quiet]\n"
        "       arch <arch> --list <file.txt>  [--variant v] [--cap N] [--each]\n"); return 2; }
    g_arch = argv[1];
    const char *variant="classic", *listf=NULL, *board=NULL;
    int quiet=0, each=0;
    for (int i=2;i<argc;i++){
        if(!strcmp(argv[i],"--variant")&&i+1<argc) variant=argv[++i];
        else if(!strcmp(argv[i],"--list")&&i+1<argc) listf=argv[++i];
        else if(!strcmp(argv[i],"--cap")&&i+1<argc) CAP=atoll(argv[++i]);
        else if(!strcmp(argv[i],"--quiet")) quiet=1;
        else if(!strcmp(argv[i],"--each")) each=1;
        else if(argv[i][0]!='-') board=argv[i];
    }
    build_units(variant);

    if (listf) {
        FILE *f = fopen(listf,"r");
        if(!f){ fprintf(stderr,"cannot open %s\n",listf); return 2; }
        char line[512];
        long long *cy = malloc(sizeof(long long)*200000);
        long long sum=0, worst=-1; int n=0, nbad=0, ncap=0, worst_i=-1;
        char worst_line[128]="";
        while (fgets(line,sizeof line,f)) {
            int L=0; while(line[L]&&line[L]!='\n'&&line[L]!='\r') L++;
            if (L < NC) continue;
            int start[NC], k=0;
            for (int i=0;i<L && k<NC;i++){ char ch=line[i];
                if (ch=='.'||ch=='0') start[k++]=0;
                else if (ch>='1'&&ch<='9') start[k++]=ch-'0'; }
            if (k!=NC) continue;
            ev_t e; memset(&e,0,sizeof e); CYC=0;
            dispatch(start,&e);
            int st = check(start,&e);
            long long c = cycles_of(&e);
            if (st==2){ ncap++; c = CAP; }
            else if (st==1){ nbad++; fprintf(stderr,"BAD RESULT on line %d: %.81s\n",n+1,line); }
            cy[n]=c; sum+=c;
            if (c>worst){ worst=c; worst_i=n+1; snprintf(worst_line,sizeof worst_line,"%.81s",line); }
            if (each) printf("%d\t%lld\t%s\t%.81s\n", n+1, c, st==2?"CAP":st?"BAD":"ok", line);
            n++;
        }
        fclose(f);
        qsort(cy,n,sizeof(long long),cmpll);
        printf("%-4s %-9s %-22s n=%-5d bad=%d cap=%d  med=%lld  p99=%lld  MAX=%lld  mean=%.1f\n",
               g_arch, variant, listf, n, nbad, ncap,
               n?cy[n/2]:0, n?cy[(int)((n-1)*0.99)]:0, worst, n?(double)sum/n:0.0);
        if (!quiet && worst_i>0) printf("     worst is line %d: %s\n", worst_i, worst_line);
        return nbad?3:0;
    }

    int start[NC]; read_board(board, start);
    ev_t e; memset(&e,0,sizeof e); CYC=0;
    dispatch(start,&e);
    int st = check(start,&e);
    long long cyc = cycles_of(&e);
    if (quiet) {
        printf("%s\t%s\t%lld\t%lld\t%lld\t%lld\t%lld\t%lld\t%lld\t%lld\t%d\t%d\t%d\n",
               g_arch, variant, cyc, e.nodes, e.guesses, e.forced, e.contradict,
               e.advance+e.prop, e.backtrack+e.undo, e.find+e.try_, e.maxdepth, e.solved, st);
    } else {
        printf("arch           %s (%s)\n", g_arch, variant);
        printf("solved         %s%s\n", e.solved>0?"yes":e.solved<0?"CAPPED":"NO",
               st==1?"   *** BAD ***":"");
        printf("CYCLES (1/ev)  %lld\n", cyc);
        if (e.find)      printf("  find steps   %lld\n", e.find);
        if (e.try_)      printf("  try steps    %lld\n", e.try_);
        if (e.advance)   printf("  advance      %lld\n", e.advance);
        if (e.prop)      printf("  prop rounds  %lld\n", e.prop);
        if (e.backtrack) printf("  backtrack    %lld\n", e.backtrack);
        if (e.undo)      printf("  undo         %lld\n", e.undo);
        printf("placements     %lld  (forced %lld / guessed %lld)\n", e.nodes, e.forced, e.guesses);
        printf("contradictions %lld\n", e.contradict);
        printf("max depth      %d\n", e.maxdepth);
        printf("grid           "); for(int c=0;c<NC;c++) printf("%d",val[c]); printf("\n");
    }
    return st==1 ? 3 : 0;
}
