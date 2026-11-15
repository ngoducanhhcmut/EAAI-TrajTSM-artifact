/* =============================================================================
 * tsm_demo.c - firmware R5 (bare-metal) chay tren ZCU106 (RAM SO-DIMM x16 8Gb, psu_init_zcu106_ram_x16_8gb) cho ban build v2d.
 *
 * Ba che do, chay lien tiep, in bang ket qua qua UART (115200 8N1):
 *   [A] E2E Traj -> TSM : 35 khung nuScenes (scene-0103). Moi khung: nap world model cho
 *       VLA-Traj, chay suy luan, doc 4 waypoint, mo rong 50 diem + dong goi + CRC-32 tren PS,
 *       ghi DDR, chay TSM, doc GRANT/VETO. So voi ket qua mo phong RTL (demo_golden.h):
 *       waypoint lech <= 1 mm (tieu chi E2E RTL), quyet dinh TSM khop.
 *   [B] Kich ban TSM : cac cap (quy dao, vat can) nuScenes chon san - va cham that va an toan.
 *   [C] Tiem loi     : CRC sai, NaN, va cham dat ngay truoc mui xe -> TSM phai VETO + bit loi.
 * Do tre do bang bo dem he thong IOU_SCNTRS (~100 MHz): TSM luon ~8,0 ms.
 *
 * Ban do (khop block design v2d):
 *   0xA000_0000 planning_top CSR   0xA001_0000 axi_gpio_0 (start / irq_clear TSM)
 *   0xA002_0000 axi_gpio_1 (ket qua TSM, chi doc - tsm_status_pack.v)
 *   DDR: trong so Traj 0x0000_0000..0x0193_FFFF, WM_A 0x0064_0000,
 *        bo dem TSM 0x7030_0000 (quy dao), 0x7040_0000 (world model),
 *        ngan du lieu demo 0x6000_0000 (nap bang xsdb, xem scripts/board_run_demo.tcl).
 * ============================================================================= */
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "demo_golden.h"

#define PLAN_BASE        0xA0000000u
#define GPIO0_BASE       0xA0010000u
#define GPIO1_BASE       0xA0020000u
#define TSM_TRAJ_BUF     0x70300000u
#define TSM_WM_BUF       0x70400000u
#define WM_A_ADDR        0x00640000u
#define BANK             0x60000000u
#define BANK_TRAJ_WM     (BANK + 0x000000u)   /* n * 0x10000 */
#define BANK_A_TSMWM     (BANK + 0x300000u)   /* n * 0x2000  */
#define BANK_B_TRAJ      (BANK + 0x400000u)   /* n * 0x800   */
#define BANK_B_TSMWM     (BANK + 0x480000u)   /* n * 0x2000  */
#define TRAJ_WM_BYTES    0x10000u
#define TSM_WM_BYTES     (100u * 64u)
#define TRAJ_BYTES       1404u

#define CSR(o)           (PLAN_BASE + (o))
#define ST_DONE          (1u << 4)
#define ST_BOOT_OK       ((1u << 8) | (1u << 10))

/* [06/10] Bo dem he thong IOU_SCNTRS (~100 MHz, tan so doc tu thanh ghi) thay XTime: khi nap qua XSDB
 * khong FSBL, XTime cua R5 dem sai (do duoc "11 us" cho TSM 8 ms). psu_init da bat bo dem nay. */
#define SCNT_BASE 0xFF260000u
static uint32_t scnt_freq = 100000000u;
static uint64_t scnt(void) {
    uint32_t hi, lo, hi2;
    do { hi = Xil_In32(SCNT_BASE + 0x0Cu); lo = Xil_In32(SCNT_BASE + 0x08u); hi2 = Xil_In32(SCNT_BASE + 0x0Cu); }
    while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}
static double now_ms(void) { return (double)scnt() * 1000.0 / (double)scnt_freq; }
static void scnt_init(void) {
    if (!(Xil_In32(SCNT_BASE) & 1u)) Xil_Out32(SCNT_BASE, 1u);
    uint32_t f = Xil_In32(SCNT_BASE + 0x20u);
    if (f) scnt_freq = f;
}

/* [06/10] UART0 tu khoi tao + outbyte truc tiep (nhu tsm_onecase.c): khi XSDB bo qua FSBL, driver UART
 * cua BSP co the khong in duoc. 115200 8N1 voi psu_init ZCU106. */
#define UART0_BASE 0xFF000000u
void outbyte(char c) {
    while (Xil_In32(UART0_BASE + 0x2Cu) & 0x10u) { }
    Xil_Out32(UART0_BASE + 0x30u, (uint8_t)c);
}
static void uart0_init(void) {
    Xil_Out32(UART0_BASE + 0x00u, 0x28u);
    Xil_Out32(UART0_BASE + 0x00u, 0x03u);
    Xil_Out32(UART0_BASE + 0x04u, 0x20u);
    Xil_Out32(UART0_BASE + 0x18u, 0x33u);
    Xil_Out32(UART0_BASE + 0x34u, 0x10u);
    Xil_Out32(UART0_BASE + 0x00u, 0x14u);
}

/* ---------------------------------------------------------------- CRC-32 (zlib) */
static uint32_t crc_tab[256];
static void crc_init(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int k = 0; k < 8; k++) c = (c & 1u) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        crc_tab[i] = c;
    }
}
static uint32_t crc32_ieee(const uint8_t *p, uint32_t n) {
    uint32_t c = 0xFFFFFFFFu;
    while (n--) c = crc_tab[(c ^ *p++) & 0xFFu] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}

/* ---------------------------------------------------------------- 4 -> 50 waypoint
 * Giong sw/gen_hmao_collision_e2e_dataset.py: polyfit bac 3 qua (0,0) + 4 waypoint tai
 * t = 0..2 s, lay mau 50 diem dt = 0,1 s, van toc sai phan tien (diem cuoi lui), kep 35 m/s,
 * huong atan2, giu huong cu khi |v| < 0,5 m/s. He so polyfit = PINV (4x5, tinh san bang numpy). */
static void fit_cubic(const double v[5], double c[4]) {
    for (int r = 0; r < 4; r++) {
        c[r] = 0.0;
        for (int k = 0; k < 5; k++) c[r] += PINV[r][k] * v[k];
    }
}
static double polyval3(const double c[4], double t) { return ((c[0] * t + c[1]) * t + c[2]) * t + c[3]; }

static void build_traj(const float wp[8], uint8_t out[TRAJ_BYTES]) {
    double vx_[5] = {0, wp[0], wp[2], wp[4], wp[6]}, vy_[5] = {0, wp[1], wp[3], wp[5], wp[7]};
    double cx[4], cy[4], x[50], y[50];
    fit_cubic(vx_, cx); fit_cubic(vy_, cy);
    for (int i = 0; i < 50; i++) { x[i] = polyval3(cx, 0.1 * i); y[i] = polyval3(cy, 0.1 * i); }
    float *f = (float *)out;
    double hd_prev = 0.0;
    for (int i = 0; i < 50; i++) {
        double dx, dy;
        if (i < 49) { dx = (x[i + 1] - x[i]) / 0.1; dy = (y[i + 1] - y[i]) / 0.1; }
        else        { dx = (x[i] - x[i - 1]) / 0.1; dy = (y[i] - y[i - 1]) / 0.1; }
        double sp = sqrt(dx * dx + dy * dy);
        if (sp > 35.0) { dx *= 35.0 / sp; dy *= 35.0 / sp; }
        double hd = (sp >= 0.5) ? atan2(dy, dx) : (i ? hd_prev : 0.0);
        hd_prev = hd;
        f[i * 7 + 0] = (float)x[i]; f[i * 7 + 1] = (float)y[i]; f[i * 7 + 2] = 0.0f;
        f[i * 7 + 3] = (float)dx;   f[i * 7 + 4] = (float)dy;   f[i * 7 + 5] = (float)hd;
        f[i * 7 + 6] = (float)(0.1 * i);
    }
    uint32_t crc = crc32_ieee(out, 1400);
    memcpy(out + 1400, &crc, 4);
}

/* ---------------------------------------------------------------- VLA-Traj */
static int traj_run(float wp[8], double *ms) {
    Xil_Out32(CSR(0x000), 0x1);                         /* START */
    double t0 = now_ms();
    /* gioi han kep: thoi gian (neu bo dem chay) va so vong lap (neu bo dem dung) */
    for (uint32_t it = 0; !(Xil_In32(CSR(0x004)) & ST_DONE); it++)
        if (now_ms() - t0 > 500.0 || it > 200000000u) return -1;
    *ms = now_ms() - t0;
    Xil_Out32(CSR(0x000), 0x100);                       /* xoa IRQ */
    for (int k = 0; k < 8; k++) { uint32_t u = Xil_In32(CSR(0x010 + 4 * k)); memcpy(&wp[k], &u, 4); }
    return 0;
}

/* ---------------------------------------------------------------- TSM */
typedef struct { int grant, fault, stage, vtype, step, obs; uint32_t st, det; double ms; } tsm_res_t;

static int tsm_run(tsm_res_t *r) {
    Xil_Out32(GPIO0_BASE + 0x0, 1); Xil_Out32(GPIO0_BASE + 0x0, 0);   /* start: suon len */
    double t0 = now_ms();
    for (uint32_t it = 0; !(Xil_In32(GPIO1_BASE + 0x0) & 0x2u); it++)
        if (now_ms() - t0 > 100.0 || it > 50000000u) return -1;
    r->ms = now_ms() - t0;
    r->st = Xil_In32(GPIO1_BASE + 0x0); r->det = Xil_In32(GPIO1_BASE + 0x8);
    r->grant = r->st & 1u; r->fault = (r->st >> 8) & 0x7Fu;
    r->vtype = (r->st >> 16) & 0xFFu; r->stage = (r->st >> 24) & 0xFFu;
    r->step = r->det & 0xFFFFu; r->obs = (r->det >> 16) & 0xFFFFu;
    Xil_Out32(GPIO0_BASE + 0x8, 1); Xil_Out32(GPIO0_BASE + 0x8, 0);   /* xoa ngat */
    return 0;
}

static void put_tsm_inputs(const void *traj, const void *wm) {
    memcpy((void *)TSM_TRAJ_BUF, traj, TRAJ_BYTES);
    memcpy((void *)TSM_WM_BUF, wm, TSM_WM_BYTES);
    Xil_DCacheFlushRange(TSM_TRAJ_BUF, TRAJ_BYTES);
    Xil_DCacheFlushRange(TSM_WM_BUF, TSM_WM_BYTES);
}

static const char *dec(int g) { return g ? "GRANT" : "VETO "; }
static void print_ms(double v) { int i = (int)(v * 100.0 + 0.5); xil_printf("%d.%02d", i / 100, i % 100); }

/* ---------------------------------------------------------------- main */
int main(void) {
    static uint8_t traj[TRAJ_BYTES];
    int okA = 0, okWp = 0, okB = 0, okC = 0, nC = 0;
    double tsm_min = 1e9, tsm_max = 0.0, traj_sum = 0.0, wp_dev_max = 0.0;
    tsm_res_t r;

    uart0_init();
    scnt_init();
    crc_init();
    { double a = now_ms(); for (volatile int k = 0; k < 2000000; k++) {} double b = now_ms();
      if (b <= a) xil_printf("CANH BAO: bo dem thoi gian khong chay - cot ms se bang 0.\r\n"); }
    xil_printf("\r\n=== VLA-Traj + TSM v2.1 - demo tren ZCU106 (ban build v2d) ===\r\n");
    uint32_t st = Xil_In32(CSR(0x004));
    xil_printf("STATUS Traj = 0x%08x (boot %s)\r\n", st, ((st & ST_BOOT_OK) == ST_BOOT_OK) ? "OK" : "CHUA XONG");
    if ((st & ST_BOOT_OK) != ST_BOOT_OK) {
        xil_printf("LOI: VLA-Traj chua nap xong trong so. Kiem tra thu tu nap DDR truoc khi nha reset PL.\r\n");
        return 1;
    }
    Xil_Out32(CSR(0x034), 0x1); Xil_Out32(CSR(0x008), 0x0);

    /* ---------------- [A] E2E */
    xil_printf("\r\n[A] E2E Traj -> TSM tren %d khung nuScenes (%s)\r\n", N_A, SCENE_A);
    xil_printf(" #  | WP3 (x, y) m          | WP khop | Traj ms | TSM     | mong doi | TSM ms\r\n");
    for (int n = 0; n < N_A; n++) {
        float wp[8]; double tms;
        memcpy((void *)WM_A_ADDR, (const void *)(BANK_TRAJ_WM + n * TRAJ_WM_BYTES), TRAJ_WM_BYTES);
        Xil_DCacheFlushRange(WM_A_ADDR, TRAJ_WM_BYTES);
        if (traj_run(wp, &tms)) { xil_printf("%2d | Traj HET GIO\r\n", n); continue; }
        /* so voi GRU tuong duong RTL (cung tieu chi E2E RTL: lech <= 1 mm) */
        double dmax = 0.0;
        for (int k = 0; k < 8; k++) { float e; memcpy(&e, &A_WP_BITS[n][k], 4); dmax = fmax(dmax, fabs((double)wp[k] - e)); }
        int wp_ok = dmax <= 1e-3;
        wp_dev_max = fmax(wp_dev_max, dmax);
        build_traj(wp, traj);
        put_tsm_inputs(traj, (const void *)(BANK_A_TSMWM + n * 0x2000u));
        if (tsm_run(&r)) { xil_printf("%2d | TSM HET GIO\r\n", n); continue; }
        int ok = (r.grant == A_EXP_GRANT[n]) && r.fault == 0;
        okA += ok; okWp += wp_ok; traj_sum += tms;
        tsm_min = fmin(tsm_min, r.ms); tsm_max = fmax(tsm_max, r.ms);
        int ix = (int)(wp[6] * 100.0f), iy = (int)(wp[7] * 100.0f);
        xil_printf("%2d | (%4d.%02d, %4d.%02d) | %s     | ", n, ix / 100, (ix < 0 ? -ix : ix) % 100,
                   iy / 100, (iy < 0 ? -iy : iy) % 100, wp_ok ? "CO " : "KHONG");
        print_ms(tms); xil_printf("   | %s   | %s    | ", dec(r.grant), dec(A_EXP_GRANT[n])); print_ms(r.ms);
        xil_printf("%s\r\n", ok ? "" : "  <-- LECH");
    }

    /* ---------------- [B] kich ban TSM */
    xil_printf("\r\n[B] Kich ban TSM tu nuScenes (quy dao + vat can that)\r\n");
    xil_printf(" #  | ca       | loai                 | TSM   | mong doi | buoc/vat can\r\n");
    for (int n = 0; n < N_B; n++) {
        put_tsm_inputs((const void *)(BANK_B_TRAJ + n * 0x800u), (const void *)(BANK_B_TSMWM + n * 0x2000u));
        if (tsm_run(&r)) { xil_printf("%2d | TSM HET GIO\r\n", n); continue; }
        int ok = (r.grant == B_EXP_GRANT[n]) && r.fault == 0;
        okB += ok;
        tsm_min = fmin(tsm_min, r.ms); tsm_max = fmax(tsm_max, r.ms);
        xil_printf("%2d | %s | %s | %s | %s    | ", n, B_NAME[n], B_KIND[n], dec(r.grant), dec(B_EXP_GRANT[n]));
        if (!r.grant) xil_printf("t=%d.%d s, slot %d", r.step / 10, r.step % 10, r.obs);
        xil_printf("%s\r\n", ok ? "" : "  <-- LECH");
    }

    /* ---------------- [C] tiem loi */
    xil_printf("\r\n[C] Tiem loi (C1/C2: TSM phai VETO + co bit loi; C3: VETO khong loi)\r\n");
    {
        /* C1: CRC sai - lat 1 bit cua ca B0 */
        memcpy(traj, (const void *)BANK_B_TRAJ, TRAJ_BYTES); traj[100] ^= 0x01;
        put_tsm_inputs(traj, (const void *)BANK_B_TSMWM);
        nC++; if (!tsm_run(&r)) { int ok = !r.grant && (r.fault & 0x08); okC += ok;   /* bit 3 = trajectory_crc_fail */
            xil_printf("C1 CRC sai           : %s fault=0x%02x  sau ", dec(r.grant), r.fault); print_ms(r.ms);
            xil_printf(" ms  %s\r\n", ok ? "DAT" : "SAI"); }
        /* C2: NaN trong quy dao (CRC tinh lai cho dung) */
        memcpy(traj, (const void *)BANK_B_TRAJ, TRAJ_BYTES);
        { uint32_t nan = 0x7FC00000u; memcpy(traj + 7 * 4 * 10, &nan, 4);
          uint32_t c = crc32_ieee(traj, 1400); memcpy(traj + 1400, &c, 4); }
        put_tsm_inputs(traj, (const void *)BANK_B_TSMWM);
        nC++; if (!tsm_run(&r)) { int ok = !r.grant; okC += ok;
            xil_printf("C2 NaN trong quy dao : %s fault=0x%02x  %s\r\n", dec(r.grant), r.fault, ok ? "DAT" : "SAI"); }
        /* C3: xe dung ngay truoc mui (cach truc sau 5 m) tren quy dao an toan dau tien cua [A] */
        {
            float wp[8]; double tms;
            memcpy((void *)WM_A_ADDR, (const void *)BANK_TRAJ_WM, TRAJ_WM_BYTES);
            Xil_DCacheFlushRange(WM_A_ADDR, TRAJ_WM_BYTES);
            if (!traj_run(wp, &tms)) {
                static uint8_t wm[TSM_WM_BYTES];
                memset(wm, 0, sizeof wm);
                uint32_t w[16] = {0};
                w[0] = 5 * 256; w[1] = 0; w[6] = (uint32_t)(4.5 * 256); w[7] = (uint32_t)(1.9 * 256);
                w[9] = (0u << 16) | 256u; w[10] = (100u << 24) | 0u;
                memcpy(wm, w, 64);
                build_traj(wp, traj);
                put_tsm_inputs(traj, wm);
                nC++; if (!tsm_run(&r)) { int ok = !r.grant && r.fault == 0; okC += ok;
                    xil_printf("C3 xe can phia truoc : %s buoc %d slot %d  %s\r\n", dec(r.grant), r.step, r.obs, ok ? "DAT" : "SAI"); }
            }
        }
    }

    /* ---------------- tong ket */
    xil_printf("\r\n=== TONG KET ===\r\n");
    xil_printf("[A] waypoint Traj khop mo phong (<=1 mm) : %d/%d (lech lon nhat %d um)\r\n",
               okWp, N_A, (int)(wp_dev_max * 1e6 + 0.5));
    xil_printf("[A] quyet dinh TSM khop mo phong         : %d/%d\r\n", okA, N_A);
    xil_printf("[B] quyet dinh TSM khop mo phong         : %d/%d\r\n", okB, N_B);
    xil_printf("[C] tiem loi dung phan ung               : %d/%d\r\n", okC, nC);
    xil_printf("Do tre TSM (tu start toi complete)       : "); print_ms(tsm_min); xil_printf(" .. "); print_ms(tsm_max);
    xil_printf(" ms (thiet ke 8,00 ms)\r\nDo tre Traj trung binh                   : "); print_ms(traj_sum / (N_A ? N_A : 1));
    xil_printf(" ms\r\n%s\r\n", (okA == N_A && okWp == N_A && okB == N_B && okC == nC) ? "==== DEMO: DAT ====" : "==== DEMO: CO LECH ====");
    return 0;
}
