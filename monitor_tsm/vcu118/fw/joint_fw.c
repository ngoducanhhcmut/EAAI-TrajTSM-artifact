/* Claude 10/11/2026 - VCU118 joint run firmware (MicroBlaze, bare metal, no BSP).
 * Traj planner (PL) -> firmware E2 packet (tsm_fw_packet.c) -> TSM-X (PL, AXI-Stream FIFO) -> command frames.
 * Data: DDR images from make_joint_data.py, loaded by board_run_joint.tcl before the planner is released.
 *
 * PASS1  reference replay of the RTL end-to-end bench (E2E_PASS frames=35 jobs=207): same job order, time and
 *        acknowledgement presented together (shim TIME_ACK), golden expected response and command CRC per job.
 * PASS2  real time: shim time base 1 us, firmware paces each job to its time stamp, executor model holds the
 *        acknowledgement (ACK_HOLD) from command receipt until the plan leaves the pending slot.
 *        Measures planner, packet formation, FIFO transfer, decision, response-to-command, end to end.
 * PASS3  acknowledgement withheld on one committed-path job: brake rise time minus command time (expect 40 ms).
 * All times are core-clock cycles of the 100 MHz TSM-X clock (shim FREE_CYC), printed raw for the checker. */
#include <stdint.h>
#include <string.h>
#include "tsm_fw_packet.h"
#include "joint_data/joint_layout.h"

#define GPIO   0x40000000u
#define UART   0x40600000u
#define PLAN   0x44A00000u
#define SHIM   0x44A10000u
#define TCSR   0x44A20000u
#define FIFO   0x44A30000u
#define DDR(p) (DDR_MB_BASE + (uint32_t)(p))
#define WM_A_PHYS 0x00640000u
#define WM_BUF_BYTES 0x00800000u
#define RD(a)    (*(volatile uint32_t *)(uintptr_t)(a))
#define WR(a, v) (*(volatile uint32_t *)(uintptr_t)(a) = (uint32_t)(v))

/* ---------------- console ---------------- */
static void putch(char c) { while (RD(UART + 8) & 0x8u) {} WR(UART + 4, (uint8_t)c); }
static void puts_(const char *s) { while (*s) putch(*s++); }
static void putu(uint32_t v) { char b[11]; int i = 0; do { b[i++] = (char)('0' + v % 10u); v /= 10u; } while (v); while (i) putch(b[--i]); }
static void puti(int32_t v) { if (v < 0) { putch('-'); putu((uint32_t)(-v)); } else putu((uint32_t)v); }
static void putx(uint32_t v, int n) { for (int i = n - 1; i >= 0; i--) putch("0123456789abcdef"[(v >> (4 * i)) & 15u]); }
static void kv(const char *k, uint32_t v) { putch(' '); puts_(k); putch('='); putu(v); }

static uint32_t cyc(void) { return RD(SHIM + 0x2C); }                    /* FREE_CYC, 100 MHz */
static uint32_t now_us(void) { return RD(SHIM + 0x04); }

/* ---------------- bit access on MSB-first byte arrays ---------------- */
static inline int getb(const uint8_t *buf, uint32_t W, uint32_t b) { uint32_t p = W - 1u - b; return (buf[p >> 3] >> (7u - (p & 7u))) & 1; }
static inline void putb(uint8_t *buf, uint32_t W, uint32_t b, int v) {
    uint32_t p = W - 1u - b; uint8_t m = (uint8_t)(1u << (7u - (p & 7u)));
    if (v) buf[p >> 3] |= m; else buf[p >> 3] &= (uint8_t)~m;
}
static uint32_t getf(const uint8_t *buf, uint32_t W, uint32_t hi, uint32_t lo) {
    uint32_t v = 0; for (uint32_t b = hi + 1u; b-- > lo;) v = (v << 1) | (uint32_t)getb(buf, W, b); return v;
}
/* Request frame: 44673-bit request + 7 zero bits = 5585 bytes; request bit b is frame bit b+7. Packet = req[44384:43664]. */
#define REQ_W 44680u
#define PKT_LO (43664u + 7u)
static void pkt_get(const uint8_t *req, tsm_packet_t *p) {
    memset(p, 0, sizeof *p);
    p->valid = (uint8_t)getb(req, REQ_W, PKT_LO + 720u);
    for (uint32_t k = 0; k < 560u; k++) if (getb(req, REQ_W, PKT_LO + 719u - k)) p->plan[k >> 3] |= (uint8_t)(0x80u >> (k & 7u));
    p->crc = getf(req, REQ_W, PKT_LO + 159u, PKT_LO + 128u);
    for (uint32_t k = 0; k < 128u; k++) if (getb(req, REQ_W, PKT_LO + 127u - k)) p->ids[k >> 3] |= (uint8_t)(0x80u >> (k & 7u));
}
static void pkt_put(uint8_t *req, const tsm_packet_t *p) {
    putb(req, REQ_W, PKT_LO + 720u, p->valid);
    for (uint32_t k = 0; k < 560u; k++) putb(req, REQ_W, PKT_LO + 719u - k, (p->plan[k >> 3] >> (7u - (k & 7u))) & 1);
    for (uint32_t k = 0; k < 32u; k++) putb(req, REQ_W, PKT_LO + 128u + k, (int)((p->crc >> k) & 1u));
    for (uint32_t k = 0; k < 128u; k++) putb(req, REQ_W, PKT_LO + 127u - k, (p->ids[k >> 3] >> (7u - (k & 7u))) & 1);
}
static int pkt_same(const tsm_packet_t *a, const tsm_packet_t *b) {
    return a->valid == b->valid && a->crc == b->crc && !memcmp(a->plan, b->plan, 70) && !memcmp(a->ids, b->ids, 16);
}

/* ---------------- planner ---------------- */
/* 12/11/2026 board finding: the planner AXI-Lite read channel (planning_top rvalid_hold) returns the data of the
 * read issued 3 reads earlier behind the MicroBlaze/SmartConnect path (measured with xsdb, constant lag 3).
 * Workaround without touching RTL: read the same register PRD_N times and keep the last value; the last 4 reads
 * must agree, otherwise prd_bad is counted and reported. */
#define PRD_N 8
static uint32_t prd_bad;
static uint32_t prd(uint32_t off) {
    uint32_t v[PRD_N];
    for (int i = 0; i < PRD_N; i++) v[i] = RD(PLAN + off);
    for (int i = PRD_N - 4; i < PRD_N - 1; i++) if (v[i] != v[PRD_N - 1]) { prd_bad++; break; }
    return v[PRD_N - 1];
}
static int plan_run(uint32_t wp[8], uint32_t *cycles) {
    WR(PLAN + 0x000, 0x100);                                  /* clear a stale done flag before starting */
    WR(PLAN + 0x000, 0x1);
    uint32_t t0 = cyc();
    while (!(prd(0x004) & (1u << 4))) if (cyc() - t0 > 50000000u) return -1;   /* 500 ms */
    *cycles = cyc() - t0;
    WR(PLAN + 0x000, 0x100);
    for (int k = 0; k < 8; k++) wp[k] = prd(0x010 + 4 * k);
    return 0;
}

/* ---------------- TSM-X ---------------- */
static void fifo_reset(void) { WR(FIFO + 0x28, 0xA5); WR(FIFO + 0x08, 0xA5); WR(FIFO + 0x18, 0xA5); WR(FIFO + 0x00, 0xFFFFFFFFu); }
static int tsm_bringup(void) {
    WR(SHIM + 0x00, 0); for (volatile int i = 0; i < 100; i++) {} WR(SHIM + 0x00, 1);
    WR(TCSR + 0x00, 0x4);
    for (uint32_t n = 0; RD(TCSR + 0x4C) != 1u; n++) if (n > 2000000u) return -1;
    WR(TCSR + 0x00, 0x1);
    return RD(TCSR + 0x00) == 1u ? 0 : -2;
}
static uint8_t reqbuf[5600] __attribute__((aligned(4)));
static uint8_t cmdbuf[256];
static void send_req(const uint8_t *r) {
    WR(FIFO + 0x10, 1u); WR(FIFO + 0x10, 5585u);
    for (uint32_t i = 0; i < 5585u; i += 4) {
        uint32_t w = 0;
        for (uint32_t b = 0; b < 4 && i + b < 5585u; b++) w |= (uint32_t)r[i + b] << (8 * b);
        WR(FIFO + 0x10, w);
    }
    WR(FIFO + 0x14, 5593u);                                   /* store and forward: transmit starts here */
}
/* returns payload bytes (238) of one command frame, -1 if none within limit cycles */
static int read_cmd(uint32_t limit) {
    uint32_t t0 = cyc();
    while (RD(FIFO + 0x1C) == 0u) if (cyc() - t0 > limit) return -1;
    uint32_t bytes = RD(FIFO + 0x24), nw = (bytes + 3u) / 4u;
    uint32_t type = 0, len = 0;
    for (uint32_t k = 0; k < nw; k++) {
        uint32_t w = RD(FIFO + 0x20);
        if (k == 0) type = w; else if (k == 1) len = w;
        else for (uint32_t b = 0; b < 4; b++) { uint32_t i = 4 * (k - 2) + b; if (i < sizeof cmdbuf) cmdbuf[i] = (uint8_t)(w >> (8 * b)); }
    }
    return (type == 2u && len == 238u && bytes == 246u) ? 238 : -2;
}
#define CMD_W 1904u
static uint32_t cmd_type(void) { return getf(cmdbuf, CMD_W, 1903, 1901); }
static uint32_t cmd_seq(void)  { return getf(cmdbuf, CMD_W, 1881, 1850); }

typedef struct { uint32_t fmap, rsp_lo, rsp_hi, cmd_crc, reset, ack, now, pad; } meta_t;
static const meta_t *meta(int j) { return (const meta_t *)DDR(TSM_META_PHYS + (uint32_t)j * META_STRIDE); }

/* one TSM job; returns response; fills timing */
typedef struct { uint32_t fifo, decide, rsp2cmd, rsp_lo, rsp_hi, ct0, seq0; int ncmd, cmd_ok; } jt_t;   /* ct0/seq0: FIRST command of the job */
static int tsm_job(const uint8_t *req, const meta_t *m, jt_t *t, int check) {
    uint32_t a = cyc(); send_req(req); uint32_t b = cyc(); t->fifo = b - a;
    uint32_t t0 = cyc();
    while (!(RD(SHIM + 0x10) & 1u)) if (cyc() - t0 > 300000000u) return -1;       /* 3 s */
    uint32_t r = cyc();
    t->rsp_lo = RD(SHIM + 0x14); t->rsp_hi = RD(SHIM + 0x18);
    while (!(RD(SHIM + 0x10) & 0x10u)) {}
    t->decide = RD(SHIM + 0x1C);
    WR(SHIM + 0x10, 1);                                                             /* consume response */
    t->ncmd = 0; t->cmd_ok = 1; t->rsp2cmd = 0;
    int n;
    while ((n = read_cmd(t->ncmd ? 20000u : 5000000u)) > 0) {
        if (!t->ncmd) { t->rsp2cmd = cyc() - r; t->ct0 = cmd_type(); t->seq0 = cmd_seq(); }
        t->ncmd++;
        /* 12/11/2026: golden cmd_crc is zlib.crc32 (init ~0, final xor); v1 compared an init-0 CRC */
        if (check && ~tsm_crc32(cmdbuf, 238, 0xFFFFFFFFu) != m->cmd_crc) t->cmd_ok = 0;
    }
    if (n == -2) t->cmd_ok = 0;
    return 0;
}

static uint32_t pending_seq;
static int prepare_req(int j, uint32_t wp_out[8], int *frame, uint32_t *plan_cyc, uint32_t *pack_cyc, int *wp_exact, int *pkt_ok) {
    const meta_t *m = meta(j);
    memcpy(reqbuf, (const void *)DDR(TSM_REQ_PHYS + (uint32_t)j * REQ_STRIDE), 5585);
    *frame = (int)m->fmap - 1; *plan_cyc = *pack_cyc = 0; *wp_exact = *pkt_ok = -1;
    if (*frame < 0) return 0;
    memcpy((void *)DDR(WM_A_PHYS), (const void *)DDR(WM_BANK_PHYS + (uint32_t)*frame * WM_STRIDE), WM_STRIDE);
    if (plan_run(wp_out, plan_cyc)) return -1;
    const uint32_t *g = (const uint32_t *)DDR(WP_GOLD_PHYS + (uint32_t)*frame * 32u);
    *wp_exact = 1; for (int k = 0; k < 8; k++) if (wp_out[k] != g[k]) *wp_exact = 0;
    uint32_t a = cyc();
    tsm_packet_t ref, fw; pkt_get(reqbuf, &ref); fw = ref;
    int e = tsm_fw_encode(&fw, wp_out);
    pkt_put(reqbuf, &fw);
    *pack_cyc = cyc() - a;
    *pkt_ok = (!e && pkt_same(&fw, &ref));
    return 0;
}

/* PASS2 pipelining (12/11/2026): the planner is its own hardware and its input (WM frame) does not depend on
 * TSM-X output, so it computes the next frame while the firmware serves TSM-X jobs, as in the deployed system.
 * v1 ran planner and TSM-X back to back; frame jobs that the bench places 30 ms after the previous job then left
 * ~30 ms late and their stale requests were answered by braking. */
static void plan_kick(int frame) {
    memcpy((void *)DDR(WM_A_PHYS), (const void *)DDR(WM_BANK_PHYS + (uint32_t)frame * WM_STRIDE), WM_STRIDE);
    WR(PLAN + 0x000, 0x100);
    WR(PLAN + 0x000, 0x1);
}
static int plan_isdone(void) { return (prd(0x004) >> 4) & 1u; }
static void finish_req(int j, const uint32_t wp[8], uint32_t *pack_cyc, int *pkt_ok) {
    memcpy(reqbuf, (const void *)DDR(TSM_REQ_PHYS + (uint32_t)j * REQ_STRIDE), 5585);
    uint32_t a = cyc();
    tsm_packet_t ref, fw; pkt_get(reqbuf, &ref); fw = ref;
    int e = tsm_fw_encode(&fw, wp);
    pkt_put(reqbuf, &fw);
    *pack_cyc = cyc() - a;
    *pkt_ok = (!e && pkt_same(&fw, &ref));
}
static int next_frame_job(int j) { for (; j < N_JOBS; j++) if (meta(j)->fmap) return j; return -1; }
typedef struct { uint32_t late, rsp_lo, rsp_hi, plan, pack, fifo, decide, rsp2cmd, e2e, ncmd, ct, ack_us, brake, frame, wpx; } p2rec_t;
static p2rec_t p2log[N_JOBS];

static uint32_t region_crc(uint32_t phys, uint32_t n) { return tsm_crc32((const uint8_t *)DDR(phys), n, 0); }

int main(void) {
    puts_("\r\nJOINT_FW v1 (Claude 10/11/2026) VCU118 Traj+TSM-X\r\n");
    uint32_t id = RD(SHIM + 0x28);
    puts_("SHIM_ID "); putx(id, 8); puts_("\r\n");
    if (id != 0x75B0A1D4u) { puts_("FATAL shim id\r\n"); for (;;) {} }
    /* DDR images were loaded by xsdb; report their CRC so the host checker can compare */
    puts_("DDRCRC tsm_req "); putx(region_crc(TSM_REQ_PHYS, N_JOBS * REQ_STRIDE), 8);
    puts_(" tsm_meta "); putx(region_crc(TSM_META_PHYS, N_JOBS * META_STRIDE), 8);
    puts_(" wm_bank "); putx(region_crc(WM_BANK_PHYS, N_FRAMES * WM_STRIDE), 8);
    puts_(" wp_golden "); putx(region_crc(WP_GOLD_PHYS, N_FRAMES * 32u), 8);
    puts_(" bert "); putx(region_crc(0x0, 6291456u), 8); puts_("\r\n");
    memset((void *)DDR(WM_A_PHYS), 0, WM_BUF_BYTES);          /* bench: WM buffer beyond the frame reads zero */
    WR(GPIO + 0x0, 1);                                         /* release planner reset: it now loads weights */
    uint32_t t0 = cyc(); uint32_t st;
    while (((st = prd(0x004)) & 0x500u) != 0x500u) if (cyc() - t0 > 500000000u) { puts_("FATAL planner boot\r\n"); for (;;) {} }
    puts_("PLANNER_BOOT"); kv("cycles", cyc() - t0); puts_("\r\n");
    WR(PLAN + 0x034, 1); WR(PLAN + 0x008, 0);

    /* ================= PASS1: reference replay ================= */
    fifo_reset(); WR(SHIM + 0x00, 0x1);
    int wp_ok = 0, pk_ok = 0, rsp_ok = 0, cmd_ok = 0, frames = 0; pending_seq = 0;
    for (int j = 0; j < N_JOBS; j++) {
        const meta_t *m = meta(j); uint32_t wp[8], plan_cyc, pack_cyc; int frame, wpx, pko; jt_t t;
        if (m->reset) { if (tsm_bringup()) { puts_("FATAL bringup\r\n"); for (;;) {} } pending_seq = 0; }
        if (prepare_req(j, wp, &frame, &plan_cyc, &pack_cyc, &wpx, &pko)) { puts_("FATAL planner timeout\r\n"); for (;;) {} }
        if (frame >= 0) { frames++; wp_ok += wpx; pk_ok += pko; }
        WR(SHIM + 0x08, pending_seq);
        if (m->ack) WR(SHIM + 0x3C, m->now); else WR(SHIM + 0x04, m->now);   /* time (+ACK) in one clock */
        if (tsm_job(reqbuf, m, &t, 1)) { puts_("FATAL tsm timeout\r\n"); for (;;) {} }
        int ro = (t.rsp_lo == m->rsp_lo && (t.rsp_hi & 0x3Fu) == m->rsp_hi);
        rsp_ok += ro; cmd_ok += (t.cmd_ok && t.ncmd > 0);
        if (t.ncmd > 0 && t.ct0 == 0u) pending_seq = t.seq0;
        puts_("P1 j="); putu((uint32_t)j); kv("f", (uint32_t)(frame + 1)); kv("wpx", (uint32_t)(wpx + 1)); kv("pko", (uint32_t)(pko + 1));
        puts_(" rsp="); putx(t.rsp_hi, 2); putx(t.rsp_lo, 8); kv("rspok", (uint32_t)ro); kv("cmdok", (uint32_t)t.cmd_ok); kv("ncmd", (uint32_t)t.ncmd); kv("ct", t.ncmd ? t.ct0 : 9u);
        kv("plan", plan_cyc); kv("pack", pack_cyc); kv("fifo", t.fifo); kv("decide", t.decide); kv("rsp2cmd", t.rsp2cmd);
        if (frame >= 0) { puts_(" wp="); for (int k = 0; k < 8; k++) { putx(wp[k], 8); putch(k < 7 ? ',' : ' '); } }
        puts_("\r\n");
    }
    puts_("PASS1_SUMMARY"); kv("frames", (uint32_t)frames); kv("wp_exact", (uint32_t)wp_ok); kv("packets", (uint32_t)pk_ok);
    kv("responses", (uint32_t)rsp_ok); kv("commands", (uint32_t)cmd_ok); kv("jobs", N_JOBS); puts_("\r\n");

    /* ================= PASS2: real time, 1 us time base, ACK-holding executor ================= */
    fifo_reset(); if (tsm_bringup()) { puts_("FATAL bringup2\r\n"); for (;;) {} }
    WR(SHIM + 0x04, meta(0)->now); WR(SHIM + 0x00, 0x3);                       /* core_run + time_auto */
    int commits = 0, late = 0; pending_seq = 0;
    /* planner pipelined with TSM-X (see plan_kick); no UART output inside the timed loop (one P2 line costs ~23 ms
     * at 115200 baud and delayed the following job); records are printed after the pass */
    int kj = next_frame_job(0);
    uint32_t kick_cyc = 0, done_cyc = 0; int done_seen = 0;
    if (kj >= 0) { plan_kick((int)meta(kj)->fmap - 1); kick_cyc = cyc(); }
#define POLL_PLAN() do { if (kj >= 0 && !done_seen && plan_isdone()) { done_cyc = cyc(); done_seen = 1; } } while (0)
    for (int j = 0; j < N_JOBS; j++) {
        const meta_t *m = meta(j); uint32_t wp[8] = {0}, plan_cyc = 0, pack_cyc = 0; int frame = (int)m->fmap - 1, wpx = -1, pko = -1; jt_t t;
        if (frame >= 0) {                                                       /* this job's frame was kicked earlier */
            uint32_t tw = cyc();
            while (!done_seen) { POLL_PLAN(); if (cyc() - tw > 50000000u) { puts_("FATAL planner timeout2\r\n"); for (;;) {} } }
            plan_cyc = done_cyc - kick_cyc;
            WR(PLAN + 0x000, 0x100);
            for (int k = 0; k < 8; k++) wp[k] = prd(0x010 + 4 * k);
            const uint32_t *g = (const uint32_t *)DDR(WP_GOLD_PHYS + (uint32_t)frame * 32u);
            wpx = 1; for (int k = 0; k < 8; k++) if (wp[k] != g[k]) wpx = 0;
            finish_req(j, wp, &pack_cyc, &pko);
            kj = next_frame_job(j + 1); done_seen = 0;                          /* start the next frame now */
            if (kj >= 0) { plan_kick((int)meta(kj)->fmap - 1); kick_cyc = cyc(); }
        } else {
            memcpy(reqbuf, (const void *)DDR(TSM_REQ_PHYS + (uint32_t)j * REQ_STRIDE), 5585);
        }
        while ((int32_t)(now_us() - m->now) < 0) POLL_PLAN();                  /* request leaves at the job time */
        uint32_t lateness = now_us() - m->now; if (lateness > 1000u) late++;
        uint32_t ereq = cyc();
        WR(SHIM + 0x00, 0x3);                                                     /* release any ACK hold */
        /* replay the bench acknowledgements (172 ack jobs) as in PASS1 */
        if (m->ack) { WR(SHIM + 0x08, pending_seq); WR(SHIM + 0x0C, 1); }
        if (tsm_job(reqbuf, m, &t, 0)) { puts_("FATAL tsm timeout2\r\n"); for (;;) {} }
        uint32_t e1 = cyc();
        POLL_PLAN();
        uint32_t ack_us = 0;
        if (t.ncmd > 0 && t.ct0 == 0u) {                                   /* executor: hold ACK for this plan */
            pending_seq = t.seq0; commits++;
            WR(SHIM + 0x08, t.seq0); WR(SHIM + 0x38, 0); WR(SHIM + 0x00, 0x7); ack_us = now_us();
        }
        p2rec_t *r = &p2log[j];
        r->late = lateness; r->rsp_lo = t.rsp_lo; r->rsp_hi = t.rsp_hi; r->plan = plan_cyc; r->pack = pack_cyc;
        r->fifo = t.fifo; r->decide = t.decide; r->rsp2cmd = t.rsp2cmd;
        r->e2e = frame >= 0 ? plan_cyc + pack_cyc + (e1 - ereq) : 0;        /* planner start -> command, idle excluded */
        r->ncmd = (uint32_t)t.ncmd; r->ct = t.ncmd ? t.ct0 : 9u; r->ack_us = ack_us; r->brake = (RD(SHIM + 0x10) >> 1) & 1u;
        r->frame = (uint32_t)(frame + 1); r->wpx = (uint32_t)(wpx + 1); (void)pko;
    }
    WR(SHIM + 0x00, 0x3);
    for (int j = 0; j < N_JOBS; j++) {
        const p2rec_t *r = &p2log[j];
        puts_("P2 j="); putu((uint32_t)j); kv("f", r->frame); kv("wpx", r->wpx); kv("late_us", r->late);
        puts_(" rsp="); putx(r->rsp_hi, 2); putx(r->rsp_lo, 8);
        kv("plan", r->plan); kv("pack", r->pack); kv("fifo", r->fifo); kv("decide", r->decide); kv("rsp2cmd", r->rsp2cmd);
        if (r->frame) kv("e2e", r->e2e);
        kv("ncmd", r->ncmd); kv("ct", r->ct); kv("ack_us", r->ack_us); kv("brake", r->brake);
        puts_("\r\n");
    }
    puts_("PASS2_SUMMARY"); kv("jobs", N_JOBS); kv("late_jobs", (uint32_t)late); kv("nominal_cmds", (uint32_t)commits); puts_("\r\n");

    /* ================= PASS3: acknowledgement withheld ================= */
    /* replay jobs from the start until a nominal command is issued, then withhold ACK and capture the brake rise */
    fifo_reset(); if (tsm_bringup()) { puts_("FATAL bringup3\r\n"); for (;;) {} }
    WR(SHIM + 0x04, meta(0)->now); WR(SHIM + 0x00, 0x3); pending_seq = 0;
    int p3_done = 0;
    for (int j = 0; j < N_JOBS; j++) {
        const meta_t *m = meta(j); uint32_t wp[8], plan_cyc, pack_cyc; int frame, wpx, pko; jt_t t;
        if (prepare_req(j, wp, &frame, &plan_cyc, &pack_cyc, &wpx, &pko)) { puts_("FATAL planner timeout3\r\n"); for (;;) {} }
        while ((int32_t)(now_us() - m->now) < 0) {}                            /* request at the job time (as PASS2) */
        if (m->ack) { WR(SHIM + 0x08, pending_seq); WR(SHIM + 0x0C, 1); }          /* bench acknowledgements up to the test job */
        WR(SHIM + 0x38, 0);                                                       /* arm brake capture */
        if (tsm_job(reqbuf, m, &t, 0)) { puts_("FATAL tsm timeout3\r\n"); for (;;) {} }
        if (t.ncmd > 0 && t.ct0 == 0u && !((RD(SHIM + 0x10) >> 1) & 1u)) {
            uint32_t tc = now_us(), cc = cyc();
            while (!(RD(SHIM + 0x38) & 1u)) if (cyc() - cc > 20000000u) break;  /* 200 ms */
            uint32_t bt = RD(SHIM + 0x30), bc = RD(SHIM + 0x34);
            puts_("P3 j="); putu((uint32_t)j); kv("cmd_time_us", tc); kv("brake_time_us", bt);
            kv("job_time_us", m->now); kv("age_at_brake_us", bt - m->now); kv("brake_after_cmd_us", bt - tc); kv("brake_after_cmd_cyc", bc - cc);
            kv("pending", (RD(TCSR + 0x04) >> 6) & 1u); kv("captured", RD(SHIM + 0x38) & 1u); puts_("\r\n");
            p3_done = 1;
            break;
        }
        if (t.ncmd > 0 && t.ct0 == 0u) pending_seq = t.seq0;   /* nominal while braking: keep acknowledging it */
    }
    if (!p3_done) puts_("P3_NONE no nominal command with the brake low\r\n");
    puts_("PRD_BAD"); kv("count", prd_bad); puts_("\r\n");
    puts_("JOINT_DONE\r\n");
    for (;;) {}
}
