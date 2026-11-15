/* Claude 04/11/2026: TSM-X software baseline. (1) bit-exactness of tsmx_kernel.c against the Python
 * golden (cases.h), (2) decision-kernel timing: per-case select_world and the worst-case bound analogue
 * of the hardware model (all 16 candidates, B4 + B3 against 32 objects, full rows, two sweeps).
 * Host build: gcc -O2 -DHOST bench.c tsmx_kernel.c ; board builds: see build_cpu.sh.
 * Board result: struct ts_out at OUT_ADDR (A53 0xFFFC0000, R5 0xFFFD0000), magic last.
 */
#include <stdint.h>
#include "tsmx_kernel.h"
#include "cases.h"
int ts_motion_range_count(void);

#define MAGIC_DONE 0x75B0C0DEu
typedef struct {
  uint32_t cpu;               /* 1 = A53, 2 = R5F, 3 = host */
  uint32_t ncases, mism_b4, mism_b3, mism_sel, first_bad_case, first_bad_what, motion_range;
  uint64_t tick_hz;           /* system counter frequency (A53 CNTFRQ / ZynqMP IOU_SCNTRS) */
  uint64_t sel_max_ticks, sel_sum_ticks, sel_max_case;
  uint64_t full_b4_ticks, full_b3_ticks, full_rows, full_sweep_ticks;  /* one full sweep, worst ego */
  uint64_t full_b4_cyc, full_b3_cyc, full_sweep_cyc;                   /* CPU cycles (PMU) */
  uint64_t full2_sweep_ticks, full2_rows;                              /* second worst ego (v=10, a=0) */
  uint64_t reps;
  uint32_t magic;
} ts_out;

/* ------------------------------------------------------------------ timers */
#if defined(HOST)
#include <stdio.h>
#include <time.h>
static ts_out g_o_mem; static volatile ts_out *const out = &g_o_mem;
static uint64_t ticks(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000000000ull + t.tv_nsec; }
static uint64_t cyc(void) { return 0; }
static uint64_t tick_hz(void) { return 1000000000ull; }
static void tinit(void) {}
#define CPU_ID 3
#elif defined(__aarch64__)
static volatile ts_out *const out = (volatile ts_out *)0xFFFC0000u;
static uint64_t ticks(void) { uint64_t v; __asm__ volatile("isb; mrs %0, cntpct_el0" : "=r"(v)); return v; }
static uint64_t cyc(void) { uint64_t v; __asm__ volatile("isb; mrs %0, pmccntr_el0" : "=r"(v)); return v; }
static uint64_t tick_hz(void) { uint64_t v; __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(v)); return v; }
static void tinit(void) {
  volatile uint32_t *cntcr = (volatile uint32_t *)0xFF260000u;   /* IOU_SCNTRS: enable the system counter */
  if (!(*cntcr & 1)) *cntcr = 1;
  uint64_t v; __asm__ volatile("mrs %0, pmcr_el0" : "=r"(v)); v |= 1 | 4; __asm__ volatile("msr pmcr_el0, %0" ::"r"(v));
  __asm__ volatile("msr pmcntenset_el0, %0" ::"r"((uint64_t)1 << 31));
  __asm__ volatile("msr pmccfiltr_el0, %0" ::"r"((uint64_t)0));
}
#define CPU_ID 1
#else /* Cortex-R5F */
static volatile ts_out *const out = (volatile ts_out *)0xFFFD0000u;
static uint64_t ticks(void) {   /* IOU_SCNTRS counter value (lower/upper), read consistently */
  volatile uint32_t *lo = (volatile uint32_t *)0xFF260008u, *hi = (volatile uint32_t *)0xFF26000Cu;
  uint32_t h1, l, h2; do { h1 = *hi; l = *lo; h2 = *hi; } while (h1 != h2);
  return ((uint64_t)h1 << 32) | l;
}
static uint64_t cyc(void) { uint32_t v; __asm__ volatile("mrc p15, 0, %0, c9, c13, 0" : "=r"(v)); return v; }
static uint64_t tick_hz(void) { return *(volatile uint32_t *)0xFF260020u; }  /* CNTFID0 */
static void tinit(void) {
  volatile uint32_t *cntcr = (volatile uint32_t *)0xFF260000u;
  if (!(*cntcr & 1)) *cntcr = 1;
  uint32_t v; __asm__ volatile("mrc p15, 0, %0, c9, c12, 0" : "=r"(v)); v |= 1 | 4;
  __asm__ volatile("mcr p15, 0, %0, c9, c12, 0" ::"r"(v));
  __asm__ volatile("mcr p15, 0, %0, c9, c12, 1" ::"r"(0x80000000u));
}
#define CPU_ID 2
#endif

static ts_obj g_objs[TS_MAXOBJ];
static ts_traj g_tr;

static int load_case(int c) {
  for (int i = 0; i < CASE_NOBJ[c]; i++) {
    const int64_t *o = CASE_OBJ[c][i];
    g_objs[i].x = o[0]; g_objs[i].v = o[1]; g_objs[i].a = o[2]; g_objs[i].length = o[3]; g_objs[i].event = o[4]; g_objs[i].after_a = o[5];
  }
  return CASE_NOBJ[c];
}
static uint64_t row_cs(const ts_traj *t) {
  uint64_t cs = 0;
  for (int k = 0; k < t->nrows; k++) {
    const ts_row *r = &t->rows[k];
    int64_t f[7] = {r->t, r->xl, r->xh, r->vl, r->vh, r->a, r->jerk};
    for (int i = 0; i < 7; i++) cs = cs * 1000003ull + (uint64_t)f[i];
  }
  return cs;
}
static void bad(int c, int what) { if (out->first_bad_case == 0xffffffffu) { out->first_bad_case = c; out->first_bad_what = what; } }

/* one full sweep: all 16 candidates, B4 then B3 against the objects (no early exit) */
static void full_sweep(int64_t x, int64_t v, int64_t a, int nobj, uint64_t *b4t, uint64_t *b3t,
                       uint64_t *b4c, uint64_t *b3c, uint64_t *rows) {
  ts_geom g; *b4t = *b3t = *b4c = *b3c = *rows = 0;
  for (int cid = 0; cid < 16; cid++) {
    uint64_t t0 = ticks(), c0 = cyc();
    ts_b4_mrmgen(x, v, a, cid, 0, 128, &g_tr);
    uint64_t t1 = ticks(), c1 = cyc();
    ts_b3_geom(&g_tr, g_objs, nobj, &TS_LANE_DEFAULT, &g);
    uint64_t t2 = ticks(), c2 = cyc();
    *b4t += t1 - t0; *b3t += t2 - t1; *b4c += c1 - c0; *b3c += c2 - c1; *rows += g_tr.nrows;
    if (!g.accept) bad(9999, 100 + cid);   /* worst-case scenario must accept every candidate (full rows) */
  }
}

int main(void) {
  tinit();
  out->magic = 0; out->cpu = CPU_ID; out->ncases = NCASES; out->tick_hz = tick_hz();
  out->mism_b4 = out->mism_b3 = out->mism_sel = 0; out->first_bad_case = 0xffffffffu; out->first_bad_what = 0;
  /* ---- (1) bit-exactness ---- */
  for (int c = 0; c < NCASES; c++) {
    int n = load_case(c);
    for (int cid = 0; cid < 16; cid++) {
      ts_geom g;
      ts_b4_mrmgen(CASE_EGO[c][0], CASE_EGO[c][1], CASE_EGO[c][2], cid, 0, 128, &g_tr);
      const int64_t *e4 = CASE_B4[c][cid], *e3 = CASE_B3[c][cid];
      if (g_tr.accept != e4[0] || g_tr.nrows != e4[1] || g_tr.stop != e4[2] || (int64_t)row_cs(&g_tr) != e4[3] || g_tr.reason != e4[4]) {
        out->mism_b4++; bad(c, 1);
      }
      ts_b3_geom(&g_tr, g_objs, n, &TS_LANE_DEFAULT, &g);
      if (e3[2] != 99 && (g.accept != e3[0] || g.margin != e3[1] || g.reason != e3[2] || g.steps != e3[3])) { out->mism_b3++; bad(c, 2); }
    }
    if (ts_select_world(CASE_EGO[c][0], CASE_EGO[c][1], CASE_EGO[c][2], g_objs, n, &TS_LANE_DEFAULT) != CASE_SEL[c]) { out->mism_sel++; bad(c, 3); }
  }
  out->motion_range = ts_motion_range_count();
  /* ---- (2a) per-case select_world timing (best of 3 runs per case, max over cases) ---- */
  out->sel_max_ticks = out->sel_sum_ticks = out->sel_max_case = 0;
  for (int c = 0; c < NCASES; c++) {
    int n = load_case(c); uint64_t best = ~0ull;
    for (int r = 0; r < 3; r++) {
      uint64_t t0 = ticks();
      ts_select_world(CASE_EGO[c][0], CASE_EGO[c][1], CASE_EGO[c][2], g_objs, n, &TS_LANE_DEFAULT);
      uint64_t d = ticks() - t0; if (d < best) best = d;
    }
    out->sel_sum_ticks += best;
    if (best > out->sel_max_ticks) { out->sel_max_ticks = best; out->sel_max_case = c; }
  }
  /* ---- (2b) worst-case bound analogue: ego 9.8 m/s, a=+2 (worst_apos), 32 non-interfering objects ---- */
  for (int i = 0; i < TS_MAXOBJ; i++) {   /* stationary objects far ahead: every row is checked, nothing rejects */
    g_objs[i].x = 400 * TS_S + i * 10 * TS_S; g_objs[i].v = 0; g_objs[i].a = 0; g_objs[i].length = 4800000;
    g_objs[i].event = 0; g_objs[i].after_a = 0;
  }
  uint64_t b4t, b3t, b4c, b3c, rows, best_t = ~0ull;
  out->reps = 5;
  for (int r = 0; r < 5; r++) {
    full_sweep(0, 9800000, 2 * TS_S, TS_MAXOBJ, &b4t, &b3t, &b4c, &b3c, &rows);
    if (b4t + b3t < best_t) {
      best_t = b4t + b3t; out->full_b4_ticks = b4t; out->full_b3_ticks = b3t; out->full_rows = rows;
      out->full_b4_cyc = b4c; out->full_b3_cyc = b3c; out->full_sweep_cyc = b4c + b3c;
    }
  }
  out->full_sweep_ticks = best_t;
  best_t = ~0ull;
  for (int r = 0; r < 5; r++) {
    full_sweep(0, 10 * TS_S, 0, TS_MAXOBJ, &b4t, &b3t, &b4c, &b3c, &rows);
    if (b4t + b3t < best_t) { best_t = b4t + b3t; out->full2_rows = rows; }
  }
  out->full2_sweep_ticks = best_t;
  out->magic = MAGIC_DONE;
#if !defined(HOST)
  { extern void Xil_DCacheFlush(void); Xil_DCacheFlush(); }
#endif
#if defined(HOST)
  double hz = (double)out->tick_hz;
  printf("cases=%u mismatch b4=%u b3=%u sel=%u first_bad=%d/%u motion_range=%u\n", out->ncases, out->mism_b4, out->mism_b3,
         out->mism_sel, (int)out->first_bad_case, out->first_bad_what, out->motion_range);
  printf("select_world: max %.1f us (case %llu), mean %.1f us\n", out->sel_max_ticks / hz * 1e6,
         (unsigned long long)out->sel_max_case, out->sel_sum_ticks / hz * 1e6 / NCASES);
  printf("full sweep (16 cand, 32 obj, v=9.8 a=+2): %.1f us (B4 %.1f, B3 %.1f), rows %llu; two sweeps %.1f us\n",
         out->full_sweep_ticks / hz * 1e6, out->full_b4_ticks / hz * 1e6, out->full_b3_ticks / hz * 1e6,
         (unsigned long long)out->full_rows, 2 * out->full_sweep_ticks / hz * 1e6);
  printf("full sweep (v=10 a=0): %.1f us rows %llu\n", out->full2_sweep_ticks / hz * 1e6, (unsigned long long)out->full2_rows);
  return (out->mism_b4 || out->mism_b3 || out->mism_sel) ? 1 : 0;
#endif
  for (;;) { }
  return 0;
}
