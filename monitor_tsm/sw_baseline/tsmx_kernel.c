/* Claude 04/11/2026: see tsmx_kernel.h. Line references are to golden/tsmx_golden/model.py. */
#include "tsmx_kernel.h"

#if defined(__SIZEOF_INT128__) && !defined(TS_PORTABLE)
/* ---------- 64-bit hosts (A53, x86-64): 256-bit two's complement as 4 x 64-bit limbs ---------- */
typedef unsigned __int128 u128;
typedef struct { uint64_t w[4]; } i256;
static inline i256 I(int64_t x) { i256 r; uint64_t s = x < 0 ? ~0ull : 0; r.w[0] = (uint64_t)x; r.w[1] = r.w[2] = r.w[3] = s; return r; }
static inline i256 add(i256 a, i256 b) {
  i256 r; u128 c = 0;
  for (int i = 0; i < 4; i++) { c += (u128)a.w[i] + b.w[i]; r.w[i] = (uint64_t)c; c >>= 64; }
  return r;
}
static inline i256 neg(i256 a) {
  i256 r; u128 c = 1;
  for (int i = 0; i < 4; i++) { c += (uint64_t)~a.w[i]; r.w[i] = (uint64_t)c; c >>= 64; }
  return r;
}
static inline i256 sub(i256 a, i256 b) { return add(a, neg(b)); }
static inline int isneg(i256 a) { return (int)(a.w[3] >> 63); }
static inline int iszero(i256 a) { return !(a.w[0] | a.w[1] | a.w[2] | a.w[3]); }
static inline i256 mul(i256 a, i256 b) {   /* two's complement product mod 2^256 */
  uint64_t r[4] = {0, 0, 0, 0};
  for (int i = 0; i < 4; i++) {
    u128 c = 0;
    for (int j = 0; i + j < 4; j++) { c += (u128)a.w[i] * b.w[j] + r[i + j]; r[i + j] = (uint64_t)c; c >>= 64; }
  }
  i256 o; o.w[0] = r[0]; o.w[1] = r[1]; o.w[2] = r[2]; o.w[3] = r[3]; return o;
}
static inline int ucmp(const i256 *a, const i256 *b) {
  for (int i = 3; i >= 0; i--) if (a->w[i] != b->w[i]) return a->w[i] > b->w[i] ? 1 : -1;
  return 0;
}
static inline int bitlen(const i256 *a) {
  for (int i = 3; i >= 0; i--) if (a->w[i]) return 64 * i + 64 - __builtin_clzll(a->w[i]);
  return 0;
}
static inline void shl(i256 *a, int s) {
  int L = s / 64, B = s % 64;
  for (int i = 3; i >= 0; i--) {
    uint64_t v = i - L >= 0 ? a->w[i - L] << B : 0;
    if (B && i - L - 1 >= 0) v |= a->w[i - L - 1] >> (64 - B);
    a->w[i] = v;
  }
}
static inline void shr1(i256 *a) { for (int i = 0; i < 4; i++) a->w[i] = (a->w[i] >> 1) | (i < 3 ? a->w[i + 1] << 63 : 0); }
static inline void usub(i256 *a, const i256 *b) {
  u128 br = 0;
  for (int i = 0; i < 4; i++) { u128 d = (u128)a->w[i] - b->w[i] - br; a->w[i] = (uint64_t)d; br = (d >> 64) & 1; }
}
#else
/* ---------- 32-bit targets (R5F) or TS_PORTABLE: 8 x 32-bit limbs, little endian ---------- */
#define TS_LIMB32 1
typedef struct { uint32_t w[8]; } i256;

static i256 I(int64_t x) {
  i256 r; uint64_t u = (uint64_t)x; uint32_t s = x < 0 ? 0xffffffffu : 0u;
  r.w[0] = (uint32_t)u; r.w[1] = (uint32_t)(u >> 32);
  for (int i = 2; i < 8; i++) r.w[i] = s;
  return r;
}
static i256 add(i256 a, i256 b) {
  i256 r; uint64_t c = 0;
  for (int i = 0; i < 8; i++) { c += (uint64_t)a.w[i] + b.w[i]; r.w[i] = (uint32_t)c; c >>= 32; }
  return r;
}
static i256 neg(i256 a) {
  i256 r; uint64_t c = 1;
  for (int i = 0; i < 8; i++) { c += (uint64_t)(uint32_t)~a.w[i]; r.w[i] = (uint32_t)c; c >>= 32; }
  return r;
}
static i256 sub(i256 a, i256 b) { return add(a, neg(b)); }
static int isneg(i256 a) { return (int)(a.w[7] >> 31); }
static int iszero(i256 a) { for (int i = 0; i < 8; i++) if (a.w[i]) return 0; return 1; }
static i256 mul(i256 a, i256 b) {          /* mod 2^256: exact whenever the true product fits */
  uint32_t r[8] = {0};
  int na = 8, nb = 8;
  /* skip high limbs that are pure sign extension of zero to save work on small operands */
  int sa = isneg(a), sb = isneg(b);
  if (sa) a = neg(a);
  if (sb) b = neg(b);
  while (na > 1 && a.w[na - 1] == 0) na--;
  while (nb > 1 && b.w[nb - 1] == 0) nb--;
  for (int i = 0; i < na; i++) {
    uint64_t c = 0;
    for (int j = 0; j < nb && i + j < 8; j++) {
      c += (uint64_t)a.w[i] * b.w[j] + r[i + j];
      r[i + j] = (uint32_t)c; c >>= 32;
    }
    if (i + nb < 8) r[i + nb] = (uint32_t)c;
  }
  i256 o; for (int i = 0; i < 8; i++) o.w[i] = r[i];
  return (sa ^ sb) ? neg(o) : o;
}
static int ucmp(const i256 *a, const i256 *b) {
  for (int i = 7; i >= 0; i--) if (a->w[i] != b->w[i]) return a->w[i] > b->w[i] ? 1 : -1;
  return 0;
}
static int bitlen(const i256 *a) {
  for (int i = 7; i >= 0; i--) if (a->w[i]) { int b = 32; while (!(a->w[i] >> (b - 1))) b--; return 32 * i + b; }
  return 0;
}
static void shl(i256 *a, int s) {
  int L = s / 32, B = s % 32;
  for (int i = 7; i >= 0; i--) {
    uint32_t v = i - L >= 0 ? a->w[i - L] << B : 0;
    if (B && i - L - 1 >= 0) v |= a->w[i - L - 1] >> (32 - B);
    a->w[i] = v;
  }
}
static void shr1(i256 *a) { for (int i = 0; i < 8; i++) a->w[i] = (a->w[i] >> 1) | (i < 7 ? a->w[i + 1] << 31 : 0); }
static void usub(i256 *a, const i256 *b) {
  int64_t c = 0;
  for (int i = 0; i < 8; i++) { c += (int64_t)a->w[i] - b->w[i]; a->w[i] = (uint32_t)c; c >>= 32; }
}
#endif
/* Python n // d for d > 0 (quotient returned as int64: every use in the golden fits). */
static int64_t floordiv(i256 n, i256 d) {
  int s = isneg(n); if (s) n = neg(n);
  uint64_t q = 0;
  if (ucmp(&n, &d) >= 0) {
    int sh = bitlen(&n) - bitlen(&d);
    i256 ds = d; shl(&ds, sh);
    for (int i = sh; i >= 0; i--) {
      if (ucmp(&n, &ds) >= 0) { usub(&n, &ds); q |= (uint64_t)1 << i; }
      shr1(&ds);
    }
  }
  int64_t r = (int64_t)q;
  if (s) r = -r - (iszero(n) ? 0 : 1);
  return r;
}
static int64_t ceildiv(i256 n, i256 d) { return -floordiv(neg(n), d); }

/* ---------- 64-bit Python division helpers (d > 0) ---------- */
static int64_t fdiv(int64_t n, int64_t d) { int64_t q = n / d; if ((n % d) && n < 0) q--; return q; }
static int64_t cdiv(int64_t n, int64_t d) { return -fdiv(-n, d); }
static int64_t mx(int64_t a, int64_t b) { return a > b ? a : b; }
static int64_t mn(int64_t a, int64_t b) { return a < b ? a : b; }
static int64_t ab(int64_t a) { return a < 0 ? -a : a; }

/* LIBRARY: b in (2,4,6,8) x j in (2,4,8,0) */
static const int64_t LIB_B[16] = {2,2,2,2,4,4,4,4,6,6,6,6,8,8,8,8};
static const int64_t LIB_J[16] = {2,4,8,0,2,4,8,0,2,4,8,0,2,4,8,0};

const ts_lane TS_LANE_DEFAULT = { -1800000, 1800000, 0, 950000, 50000, 500000 };

/* model.py:350 */
static int64_t profile_a(int cid, int64_t el, int64_t initial) {
  int64_t b = LIB_B[cid] * TS_S, j = LIB_J[cid] * TS_S;
  if (!j) return -b;
  int64_t change = fdiv(j * mx(0, el), TS_T);
  return mx(initial - change, mn(initial + change, -b));
}

/* model.py:358 ramp_integrals; vonly skips the position terms (only the sign of vn is used
 * by the root search, model.py:376) */
static void ramp(int64_t v, int64_t a, int64_t j, int64_t target, int64_t h, int vonly,
                 i256 *xn, i256 *xd, i256 *vn, i256 *vd) {
  int64_t d = j ? ab(j) : 1;
  int64_t n = j ? mn(h * d, ab(target - a) * TS_T) : 0;
  int64_t hd = h * d;
  i256 dd = I(d * d);
  *vd = mul(I(2 * TS_T * TS_T), dd);
  i256 jt = mul(I(j), sub(mul(I(2 * n), I(hd)), mul(I(n), I(n))));
  *vn = add(add(mul(I(v), *vd), mul(mul(I(2 * a * h), I(TS_T)), dd)), jt);
  if (vonly) return;
  i256 d3 = mul(dd, I(d));
  *xd = mul(mul(I(6 * TS_T), I(TS_T * TS_T)), d3);
  i256 c1 = mul(mul(I(hd), I(hd)), I(hd));
  i256 c2 = mul(mul(I(hd - n), I(hd - n)), I(hd - n));
  *xn = add(add(mul(mul(I(6 * v * h), I(TS_T * TS_T)), d3),
                mul(mul(mul(I(3 * a), I(h * h)), I(TS_T)), d3)),
            mul(I(j), sub(c1, c2)));
}

/* model.py:370 */
static void cadv(int64_t x, int64_t v, int64_t a, int64_t j, int64_t target, int64_t h, int up,
                 int64_t *nx, int64_t *nv) {
  i256 xn, xd, vn, vd;
  ramp(v, a, j, target, h, 0, &xn, &xd, &vn, &vd);
  if (isneg(vn)) {
    int64_t lo = 0, hi = h;
    while (hi - lo > 1) {
      int64_t mid = (lo + hi) / 2;
      i256 a1, a2, mvn, a3;
      ramp(v, a, j, target, mid, 1, &a1, &a2, &mvn, &a3);
      if (!isneg(mvn)) lo = mid; else hi = mid;
    }
    ramp(v, a, j, target, lo, 0, &xn, &xd, &vn, &vd);
    int64_t dx = up ? ceildiv(xn, xd) + cdiv(v, TS_T) : floordiv(xn, xd);
    *nx = x + dx; *nv = 0; return;
  }
  *nx = x + (up ? ceildiv(xn, xd) : floordiv(xn, xd));
  *nv = mx(0, up ? ceildiv(vn, vd) : floordiv(vn, vd));
}

/* model.py:406 */
void ts_b4_mrmgen(int64_t x, int64_t v, int64_t a, int cid, int64_t phase, int limit, ts_traj *o) {
  o->nrows = 0; o->stop = -1; o->accept = 0;
  if (!(0 <= cid && cid < 16 && ab(x) <= 10000 * TS_S && 0 <= v && v <= 10 * TS_S && -8 * TS_S <= a &&
        a <= 2 * TS_S && 0 <= phase && phase <= 12800000 && phase % TS_DT == 0 && 1 <= limit && limit <= 128)) {
    o->reason = R_RANGE; return;
  }
  int64_t xl = x, xh = x, vl = v, vh = v, stop = -1;
  int64_t b = LIB_B[cid] * TS_S, j = LIB_J[cid] * TS_S;
  for (int k = 0; k < limit; k++) {
    int64_t t = phase + k * TS_DT;
    int stopped = vh == 0 && (t >= TS_DT || a <= 0);
    int64_t start = stopped ? 0 : (t < TS_DT ? a : profile_a(cid, t - TS_DT, a));
    int64_t cmd = stopped ? 0 : (t < TS_DT ? a : profile_a(cid, t - TS_DT + TS_DT / 2, a));
    int64_t sgn = (t < TS_DT || stopped || start == -b) ? 0 : (start > -b ? -j : j);
    int64_t bound = ab(sgn);
    if (t < TS_DT && TS_DT < t + TS_DT) { o->reason = R_PHASE; o->stop = -1; return; }
    if (!j && t >= TS_DT) start = cmd;
    ts_row *r = &o->rows[o->nrows++];
    r->t = t; r->xl = xl; r->xh = xh; r->vl = vl; r->vh = vh; r->a = cmd; r->jerk = bound;
    cadv(xl, vl, start, sgn, -b, TS_DT, 0, &xl, &vl);
    cadv(xh, vh, start, sgn, -b, TS_DT, 1, &xh, &vh);
    if (vh == 0 && stop < 0) stop = t + TS_DT;
    if (stop >= 0 && t + TS_DT >= stop + 2 * TS_T) {
      r = &o->rows[o->nrows++];
      r->t = t + TS_DT; r->xl = xl; r->xh = xh; r->vl = vl; r->vh = vh; r->a = 0; r->jerk = 0;
      o->accept = 1; o->stop = stop; o->reason = R_OK; return;
    }
  }
  o->stop = stop; o->reason = R_HORIZON;
}

/* model.py:311-328 (G1c division-free envelopes) */
static int64_t disp_lb(int64_t v, int64_t a, int64_t h) { return mx(0, fdiv(2 * v * h * TS_T + a * h * h, 2 * TS_T * TS_T)); }
static int64_t disp_ub(int64_t v, int64_t a, int64_t h) {
  if (a >= 0 || v * TS_T + a * h >= 0) return mx(0, cdiv(2 * v * h * TS_T + a * h * h, 2 * TS_T * TS_T));
  return cdiv(v * h, 2 * TS_T);
}
static int g_motion_range;   /* golden would raise ValueError('motion_range'); counted, never expected */
static void adv_lb(int64_t *x, int64_t *v, int64_t a, int64_t h, int up) {
  if (!(0 <= *v && *v <= 20 * TS_S && -8 * TS_S <= a && a <= 2 * TS_S && 0 <= h && h <= 12800000)) g_motion_range++;
  int64_t dx = up ? disp_ub(*v, a, h) : disp_lb(*v, a, h);
  int64_t nv = mx(0, up ? cdiv(*v * TS_T + a * h, TS_T) : fdiv(*v * TS_T + a * h, TS_T));
  *x += dx; *v = nv;
}
static int64_t swept_lb(int64_t gap, int64_t va, int64_t aa, int64_t vb, int64_t abb, int64_t h) {
  int64_t la = aa < 0 ? disp_lb(va, aa, h) : fdiv(va * h, TS_T);
  int64_t ub = abb <= 0 ? cdiv(vb * h, TS_T) : disp_ub(vb, abb, h);
  return mn(gap, gap + la - ub);
}

/* model.py:439 */
void ts_b3_geom(const ts_traj *tr, const ts_obj *objs, int nobj, const ts_lane *ln, ts_geom *o) {
  o->accept = 0; o->margin = -1; o->steps = 0;
  if (!tr->accept || tr->nrows < 2 || tr->nrows > 129) { o->reason = R_TRAJ; return; }
  for (int k = 0; k < tr->nrows; k++) {
    const ts_row *r = &tr->rows[k];
    if (!(0 <= r->t && r->t <= 25600000 && -10070 * TS_S <= r->xl && r->xl <= r->xh && r->xh <= 10070 * TS_S &&
          0 <= r->vl && r->vl <= r->vh && r->vh <= 20 * TS_S && -8 * TS_S <= r->a && r->a <= 2 * TS_S &&
          0 <= r->jerk && r->jerk <= 8 * TS_S)) { o->reason = R_NUMERIC; return; }
  }
  if (!(-10000 * TS_S <= ln->lane0 && ln->lane0 <= ln->lane1 && ln->lane1 <= 10000 * TS_S && ab(ln->y) <= 10000 * TS_S &&
        0 < ln->half_width && ln->half_width <= 10 * TS_S && 0 <= ln->lateral_error && ln->lateral_error <= TS_S &&
        0 <= ln->reserve && ln->reserve <= 10 * TS_S)) { o->reason = R_LANE_RANGE; return; }
  if (nobj > TS_MAXOBJ) { o->reason = R_OBJ_OVF; return; }
  if (ln->lane0 > ln->y - ln->half_width - ln->lateral_error || ln->lane1 < ln->y + ln->half_width + ln->lateral_error) {
    o->reason = R_LANE; return;
  }
  for (int i = 0; i < nobj; i++) {
    const ts_obj *b = &objs[i];
    if (!(ab(b->x) <= 10000 * TS_S && 0 <= b->v && b->v <= 20 * TS_S && -8 * TS_S <= b->a && b->a <= 2 * TS_S &&
          -8 * TS_S <= b->after_a && b->after_a <= 2 * TS_S && 0 <= b->event && b->event <= 12800000 &&
          0 < b->length && b->length <= 20 * TS_S)) { o->reason = R_OBJ_RANGE; return; }
  }
  int64_t origin = tr->rows[0].t, horizon = tr->rows[tr->nrows - 1].t - origin;
  if (!(0 < horizon && horizon <= 12800000)) { o->reason = R_HORIZON; return; }
  for (int i = 0; i < nobj; i++)
    if (objs[i].v + cdiv(mx(0, mx(objs[i].a, objs[i].after_a)) * horizon, TS_T) > 20 * TS_S) { o->reason = R_OBJ_SPEED; return; }
  int64_t ol_[TS_MAXOBJ], oh_[TS_MAXOBJ], ovl_[TS_MAXOBJ], ovh_[TS_MAXOBJ];
  for (int i = 0; i < nobj; i++) { ol_[i] = oh_[i] = objs[i].x; ovl_[i] = ovh_[i] = objs[i].v; }
  int64_t minimum = 10000 * TS_S, reserve = ln->reserve;
  const i256 T3x8 = I(8 * TS_T * TS_T * TS_T);
  for (int k = 0; k + 1 < tr->nrows; k++) {
    const ts_row *r = &tr->rows[k];
    int64_t t = r->t, xl = r->xl, xh = r->xh, vl = r->vl, vh = r->vh, a = r->a, jerk = r->jerk;
    int64_t h = tr->rows[k + 1].t - t;
    if (!(0 < h && h <= TS_DT)) { o->margin = -1; o->reason = R_TIME; o->steps = k; return; }
    if (!(xl <= xh && 0 <= vl && vl <= vh && vh <= 20 * TS_S && -8 * TS_S <= a && a <= 2 * TS_S && 0 <= jerk && jerk <= 8 * TS_S)) {
      o->margin = -1; o->reason = R_NUMERIC; o->steps = k; return;
    }
    int64_t inflate = ceildiv(mul(I(jerk), I(h * h * h)), T3x8) + cdiv(h * h, 2 * TS_T * TS_T);
    for (int i = 0; i < nobj; i++) {
      const ts_obj *b = &objs[i];
      int64_t ol = ol_[i], oh = oh_[i], ovl = ovl_[i], ovh = ovh_[i];
      int64_t pieces[3]; int np = 0;
      pieces[np++] = 0;
      int64_t event = b->event - (t - origin);
      if (0 < event && event < h) pieces[np++] = event;
      pieces[np++] = h;
      int64_t exl = xl - inflate, exh = xh + inflate, evl = vl, evh = vh;
      int ahead = ol >= xh;
      for (int p = 0; p + 1 < np; p++) {
        int64_t left = pieces[p], width = pieces[p + 1] - left;
        int64_t oa = (t - origin + left < b->event) ? b->a : b->after_a;
        int64_t g = ahead ? swept_lb(ol - exh - b->length, ovl, oa, evh, a, width)
                          : swept_lb(exl - oh - b->length, evl, a, ovh, oa, width);
        minimum = mn(minimum, g - reserve);
        if (g < reserve) { o->margin = g - reserve; o->reason = R_SEPARATION; o->steps = k + 1; return; }
        adv_lb(&ol, &ovl, oa, width, 0); adv_lb(&oh, &ovh, oa, width, 1);
        ovh = mn(20 * TS_S, ovh);
        adv_lb(&exl, &evl, a, width, 0); adv_lb(&exh, &evh, a, width, 1);
      }
      ol_[i] = ol; oh_[i] = oh; ovl_[i] = ovl; ovh_[i] = ovh;
    }
  }
  o->accept = 1; o->margin = minimum; o->reason = R_OK; o->steps = tr->nrows - 1;
}

/* model.py:683 */
static ts_traj g_tr;
int ts_select_world(int64_t x, int64_t v, int64_t a, const ts_obj *objs, int nobj, const ts_lane *ln) {
  ts_geom g;
  for (int cid = 0; cid < 16; cid++) {
    if (!LIB_J[cid]) continue;
    ts_b4_mrmgen(x, v, a, cid, 0, 128, &g_tr);
    ts_b3_geom(&g_tr, objs, nobj, ln, &g);
    if (g.accept) return cid;
  }
  return 15;
}
int ts_motion_range_count(void) { return g_motion_range; }
