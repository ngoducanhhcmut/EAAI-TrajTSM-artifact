/* Claude 09/11/2026 - see tsm_fw_packet.h. Compile with -ffp-contract=off (no FMA) to keep the
 * binary64 evaluation order of the reference: alpha = ((A0*w0 + A1*w2) + A2*w4) + A3*w6. */
#include "tsm_fw_packet.h"
#include <math.h>

/* packetizer_v2._fit[1] (equal-weight quadratic LS, origin constrained), exact binary64 values. */
static const double FIT_A0 = -0.45161290322580672;
static const double FIT_A1 = -0.51612903225806406;
static const double FIT_A2 = -0.19354838709677388;
static const double FIT_A3 =  0.51612903225806417;

/* plan bit b (0 = LSB of the 560-bit plan) lives in byte 69 - b/8 */
static int64_t get_field(const uint8_t *plan, unsigned lsb, unsigned bits) {
    uint64_t v = 0;
    for (unsigned k = 0; k < bits / 8; k++) v = (v << 8) | plan[TSM_PLAN_BYTES - 1 - (lsb + bits) / 8 + 1 + k];
    if (bits < 64 && (v >> (bits - 1)) & 1u) v |= ~0ull << bits;      /* sign extend */
    return (int64_t)v;
}
static void put_field(uint8_t *plan, unsigned lsb, unsigned bits, int64_t val) {
    uint64_t v = (uint64_t)val;
    for (unsigned k = 0; k < bits / 8; k++) {
        plan[TSM_PLAN_BYTES - 1 - lsb / 8 - k] = (uint8_t)(v & 0xffu);
        v >>= 8;
    }
}

/* IEEE binary32 -> binary64, exact; -1 on Inf/NaN (the RTL bench $fatal's on these). */
static int f2d(uint32_t b, double *out) {
    unsigned e = (b >> 23) & 0xffu;
    uint32_t m = b & 0x7fffffu;
    double r;
    if (e == 255) return -1;
    r = (e == 0) ? (double)m / 8388608.0 : 1.0 + (double)m / 8388608.0;
    r = ldexp(r, (e == 0 ? 1 : (int)e) - 127);
    *out = (b >> 31) ? -r : r;
    return 0;
}

/* Python round(): nearest, ties to even (also for negative values). */
static int64_t round_even(double r) {
    double fl = floor(r);
    int64_t n = (int64_t)fl;
    double f = r - fl;
    if (f > 0.5 || (f == 0.5 && (n & 1))) n++;
    return n;
}
static int64_t floor_div(int64_t n, int64_t d) {
    return n / d - ((n < 0 && n % d != 0) ? 1 : 0);
}

uint32_t tsm_crc32(const uint8_t *buf, unsigned n, uint32_t c) {
    for (unsigned i = 0; i < n; i++) {
        c ^= buf[i];
        for (int k = 0; k < 8; k++) c = (c >> 1) ^ ((c & 1u) ? 0xedb88320u : 0u);
    }
    return c;
}
uint32_t tsm_packet_crc(const tsm_packet_t *p) {
    uint32_t c = tsm_crc32(p->plan, TSM_PLAN_BYTES, 0xffffffffu);
    c = tsm_crc32(p->ids, TSM_IDS_BYTES, c);
    return ~c;
}

int tsm_fw_encode(tsm_packet_t *p, const uint32_t wp[8]) {
    double w0, w2, w4, w6, alpha, ca;
    int64_t x, v, a, pv, pa, dx;
    if (f2d(wp[0], &w0) || f2d(wp[2], &w2) || f2d(wp[4], &w4) || f2d(wp[6], &w6)) return -1;
    /* snapshot = plan[527:272]; x = snap[223:160], v = snap[159:128], a = snap[127:96] */
    x = get_field(p->plan, 272 + 160, 64);
    v = get_field(p->plan, 272 + 128, 32);
    a = get_field(p->plan, 272 + 96, 32);
    alpha = FIT_A0 * w0;
    alpha = alpha + FIT_A1 * w2;
    alpha = alpha + FIT_A2 * w4;
    alpha = alpha + FIT_A3 * w6;
    ca = 2.0 * alpha;
    ca = ca < -8.0 ? -8.0 : (ca > 2.0 ? 2.0 : ca);
    pa = round_even(ca * 1000000.0);
    if (v >= 0 && v <= 20000000 && a >= -8000000 && a <= 2000000) {
        if (a < 0 && 100000 * (-a) >= v * 1000000) dx = floor_div(v * v, -2 * a);
        else dx = floor_div(20 * v + a, 200);
        pv = floor_div(10 * v + a, 10);
        if (pv < 0) pv = 0;
        x = x + dx;
    } else {
        double raw_x = (double)x + (double)v * 0.1 + 0.5 * (double)a * 0.1 * 0.1;
        double raw_v = (double)v + (double)a * 0.1;
        x = round_even(raw_x);
        pv = round_even(raw_v);
    }
    put_field(p->plan, 144, 64, x);   /* plan[207:144] */
    put_field(p->plan, 112, 32, pv);  /* plan[143:112] */
    put_field(p->plan, 80, 32, pa);   /* plan[111:80]  */
    p->valid = 1;
    p->crc = tsm_packet_crc(p);
    return 0;
}
