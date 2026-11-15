/* =============================================================================
 * traj_demo.c - firmware R5 du phong: CHI chay VLA-Traj tren PL, khong dung TSM.
 *
 * Dung voi bitstream deliverables/v2d_traj_only_fallback (build 05/10 23:03). TSM trong
 * bitstream do con loi doc AXI + watchdog (da sua trong RTL 06/10, chua build), nen firmware
 * nay KHONG cham vao axi_gpio_0/axi_gpio_1. Phan VLA-Traj khong thay doi giua hai ban.
 *
 * 35 khung nuScenes scene-0103 lien tiep (dung thu tu mo phong E2E RTL): nap world model vao
 * WM_A, chay suy luan, doc 4 waypoint, so voi waypoint mo phong RTL (demo_golden.h, lech <= 1 mm).
 * Du lieu: trong so tai 0x0000_0000.., ngan demo 0x6000_0000 (scripts/board_run_traj_zcu106.tcl).
 * ============================================================================= */
#include <stdint.h>
#include <string.h>
#include <math.h>
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "demo_golden.h"

#define PLAN_BASE        0xA0000000u
#define WM_A_ADDR        0x00640000u
#define BANK             0x60000000u
#define BANK_TRAJ_WM     (BANK + 0x000000u)   /* n * 0x10000 */
#define TRAJ_WM_BYTES    0x10000u

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
static void print_ms(double v) { int i = (int)(v * 100.0 + 0.5); xil_printf("%d.%02d", i / 100, i % 100); }
static void print_m(float v) {
    int i = (int)(v * 100.0f + (v < 0 ? -0.5f : 0.5f));
    xil_printf("%s%d.%02d", i < 0 ? "-" : "", (i < 0 ? -i : i) / 100, (i < 0 ? -i : i) % 100);
}

static int traj_run(float wp[8], double *ms) {
    Xil_Out32(CSR(0x000), 0x1);                         /* START */
    double t0 = now_ms();
    for (uint32_t it = 0; !(Xil_In32(CSR(0x004)) & ST_DONE); it++)
        if (now_ms() - t0 > 500.0 || it > 200000000u) return -1;
    *ms = now_ms() - t0;
    Xil_Out32(CSR(0x000), 0x100);                       /* xoa IRQ */
    for (int k = 0; k < 8; k++) { uint32_t u = Xil_In32(CSR(0x010 + 4 * k)); memcpy(&wp[k], &u, 4); }
    return 0;
}

int main(void) {
    int okWp = 0, nRun = 0;
    uart0_init();
    scnt_init();
    double traj_sum = 0.0, dev_max = 0.0;

    { double a = now_ms(); for (volatile int k = 0; k < 2000000; k++) {} double b = now_ms();
      if (b <= a) xil_printf("CANH BAO: bo dem thoi gian khong chay - cot ms se bang 0.\r\n"); }
    xil_printf("\r\n=== VLA-Traj tren FPGA (ZCU106, PL) - suy luan 35 khung nuScenes ===\r\n");
    uint32_t st = Xil_In32(CSR(0x004));
    xil_printf("STATUS Traj = 0x%08x (nap trong so %s)\r\n", st, ((st & ST_BOOT_OK) == ST_BOOT_OK) ? "OK" : "CHUA XONG");
    if ((st & ST_BOOT_OK) != ST_BOOT_OK) {
        xil_printf("LOI: VLA-Traj chua nap xong trong so. Kiem tra thu tu nap DDR truoc khi nha reset PL.\r\n");
        return 1;
    }
    Xil_Out32(CSR(0x034), 0x1); Xil_Out32(CSR(0x008), 0x0);

    xil_printf("%s\r\n", SCENE_A);
    xil_printf(" #  | WP4 FPGA (x, y) m  | WP4 mo phong (x, y) m | lech max (um) | khop | Traj ms\r\n");
    for (int n = 0; n < N_A; n++) {
        float wp[8]; double tms;
        memcpy((void *)WM_A_ADDR, (const void *)(BANK_TRAJ_WM + n * TRAJ_WM_BYTES), TRAJ_WM_BYTES);
        Xil_DCacheFlushRange(WM_A_ADDR, TRAJ_WM_BYTES);
        if (traj_run(wp, &tms)) { xil_printf("%2d | Traj HET GIO\r\n", n); continue; }
        nRun++;
        double dmax = 0.0; float e[8];
        for (int k = 0; k < 8; k++) { memcpy(&e[k], &A_WP_BITS[n][k], 4); dmax = fmax(dmax, fabs((double)wp[k] - e[k])); }
        int ok = dmax <= 1e-3;
        okWp += ok; dev_max = fmax(dev_max, dmax); traj_sum += tms;
        xil_printf("%2d | (", n); print_m(wp[6]); xil_printf(", "); print_m(wp[7]);
        xil_printf(")     | ("); print_m(e[6]); xil_printf(", "); print_m(e[7]);
        xil_printf(")       | %8d      | %s  | ", (int)(dmax * 1e6 + 0.5), ok ? "CO   " : "KHONG"); print_ms(tms);
        xil_printf("%s\r\n", ok ? "" : "  <-- LECH");
    }
    xil_printf("\r\n=== TONG KET ===\r\n");
    xil_printf("Waypoint FPGA khop mo phong RTL (<=1 mm) : %d/%d (lech lon nhat %d um)\r\n",
               okWp, N_A, (int)(dev_max * 1e6 + 0.5));
    xil_printf("Do tre VLA-Traj trung binh              : "); print_ms(nRun ? traj_sum / nRun : 0.0);
    xil_printf(" ms\r\n%s\r\n", (okWp == N_A) ? "==== VLA-Traj tren FPGA: DAT ====" : "==== VLA-Traj tren FPGA: CO LECH ====");
    return 0;
}
