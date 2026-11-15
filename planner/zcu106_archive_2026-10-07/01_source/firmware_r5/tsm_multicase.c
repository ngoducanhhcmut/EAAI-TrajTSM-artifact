/* =============================================================================
 * tsm_multicase.c - firmware R5: chay TSM tren nhieu ca nuScenes lien tiep, in bang ket qua.
 *
 * Bitstream: deliverables/tsm_only_ocm (chi TSM, bo dem quy dao/world model o OCM 0xFFFE_0000/0xFFFE_1000;
 * DDR phia PS cua board lab khong dung duoc). Khong cham DDR o bat ky dau.
 *   - 15 ca bank B (6 va cham that, 6 quy dao phan cung an toan, 3 quy dao nguoi lai) + 2 ca tiem loi
 *     (C1: lat 1 bit -> CRC sai; C2: NaN trong quy dao, CRC tinh lai).
 *   - Ky vong (quyet dinh, fault, buoc, vat can) lay tu mo phong he thong RTL (multicase_data.h).
 *   - Chay N_ROUND vong lien tiep, khong reset giua cac ca (nhu su dung that).
 *   - Do tre: bo dem he thong IOU_SCNTRS (0xFF26_0000, ~100 MHz, tan so doc tu thanh ghi), tu luc ghi
 *     start toi luc thay bit complete; sai so do polling ~1 us.
 * ============================================================================= */
#include <stdint.h>
#include <string.h>
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "multicase_data.h"

#define GPIO0_BASE    0xA0010000u
#define GPIO1_BASE    0xA0020000u
#define TSM_TRAJ_BUF  0xFFFE0000u
#define TSM_WM_BUF    0xFFFE1000u
#define UART0_BASE    0xFF000000u
#define SCNT_BASE     0xFF260000u   /* IOU_SCNTRS: +0 control, +8 lower, +C upper, +20 base frequency */
#define N_ROUND       3

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

static uint32_t scnt_freq;
static uint64_t scnt(void) {
    uint32_t hi, lo, hi2;
    do { hi = Xil_In32(SCNT_BASE + 0x0Cu); lo = Xil_In32(SCNT_BASE + 0x08u); hi2 = Xil_In32(SCNT_BASE + 0x0Cu); }
    while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}
static uint32_t ticks_to_us(uint64_t t) { return (uint32_t)((t * 1000000ull) / scnt_freq); }
static void wait_us(uint32_t us) { uint64_t t0 = scnt(); while (ticks_to_us(scnt() - t0) < us) { } }

static uint32_t crc32_ieee(const volatile uint8_t *d, uint32_t n) {
    uint32_t c = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < n; ++i) { c ^= d[i]; for (int b = 0; b < 8; ++b) c = (c >> 1) ^ ((c & 1u) ? 0xEDB88320u : 0u); }
    return c ^ 0xFFFFFFFFu;
}

/* nap ca vao bo dem OCM; mod 0 = nguyen ban, 1 = lat bit byte 100 (CRC sai), 2 = NaN o byte 280 + CRC tinh lai */
static void load_case(int k, int mod) {
    volatile uint32_t *tr = (volatile uint32_t *)TSM_TRAJ_BUF, *wm = (volatile uint32_t *)TSM_WM_BUF;
    for (int i = 0; i < 351; ++i) tr[i] = CASE_TR[k][i];
    for (int i = 0; i < 1600; ++i) wm[i] = 0u;
    for (int i = 0; i < CASE_NREC[k] * 16; ++i) wm[i] = CASE_WM[k][i];
    if (mod == 1) { volatile uint8_t *b = (volatile uint8_t *)TSM_TRAJ_BUF; b[100] ^= 0x01u; }
    if (mod == 2) { tr[70] = 0x7FC00000u; tr[350] = crc32_ieee((const volatile uint8_t *)TSM_TRAJ_BUF, 1400u); }
    __asm__ volatile("dsb sy" ::: "memory");
}

typedef struct { uint32_t pre, st, det, us; int timeout; } res_t;
static void run_tsm(res_t *r) {
    r->pre = Xil_In32(GPIO1_BASE);
    Xil_Out32(GPIO0_BASE, 1u); Xil_Out32(GPIO0_BASE, 0u);
    uint64_t t0 = scnt(), t1;
    r->timeout = 0;
    while (((t1 = scnt()), (Xil_In32(GPIO1_BASE) & 0x2u)) == 0u)
        if (ticks_to_us(t1 - t0) > 100000u) { r->timeout = 1; break; }
    t1 = scnt();
    r->us = ticks_to_us(t1 - t0);
    r->st = Xil_In32(GPIO1_BASE); r->det = Xil_In32(GPIO1_BASE + 8u);
    Xil_Out32(GPIO0_BASE + 8u, 1u); Xil_Out32(GPIO0_BASE + 8u, 0u);   /* xoa ngat nhu firmware demo */
}

static void print_ms(uint32_t us) { xil_printf("%d.%03d", us / 1000u, us % 1000u); }

int main(void) {
    Xil_DCacheDisable();
    uart0_init();
    if (!(Xil_In32(SCNT_BASE) & 1u)) Xil_Out32(SCNT_BASE, 1u);
    scnt_freq = Xil_In32(SCNT_BASE + 0x20u);
    if (scnt_freq == 0u) scnt_freq = 100000000u;
    xil_printf("\r\n=== TSM TREN FPGA (ZCU106, bitstream chi-TSM, bo dem OCM): %d ca x %d vong ===\r\n",
               N_CASE + 2, N_ROUND);
    xil_printf("Bo dem thoi gian: IOU_SCNTRS %d Hz\r\n", scnt_freq);

    int total = 0, ok_all = 0;
    uint32_t lat_min = 0xFFFFFFFFu, lat_max = 0u, lat_f_min = 0xFFFFFFFFu, lat_f_max = 0u;
    for (int rd = 1; rd <= N_ROUND; ++rd) {
        int ok_round = 0;
        xil_printf("\r\n--- Vong %d ---\r\n", rd);
        xil_printf(" #  | ca     | loai                | TSM   | mong doi | fault (mong doi) | buoc/vat can (mong doi) | do tre ms | \r\n");
        for (int c = 0; c < N_CASE + 2; ++c) {
            int k = (c < N_CASE) ? c : 0, mod = (c < N_CASE) ? 0 : (c - N_CASE + 1);
            uint16_t eg = (c < N_CASE) ? CASE_EXP[c][0] : 0, ef = (c < N_CASE) ? CASE_EXP[c][1] : (mod == 1 ? 0x08 : 0x02);
            uint16_t es = (c < N_CASE) ? CASE_EXP[c][2] : 4, eo = (c < N_CASE) ? CASE_EXP[c][3] : 0;
            const char *nm = (c < N_CASE) ? CASE_NAME[c] : (mod == 1 ? "C1 CRC" : "C2 NaN");
            const char *kd = (c < N_CASE) ? CASE_KIND[c] : (mod == 1 ? "tiem loi: CRC sai" : "tiem loi: NaN");
            load_case(k, mod);
            res_t r; run_tsm(&r);
            int g = r.st & 1u, f = (r.st >> 8) & 0x7Fu, s = r.det & 0xFFFFu, o = r.det >> 16;
            int ok = !r.timeout && r.pre == 0u && ((r.st >> 1) & 1u) && g == eg && f == ef && s == es && o == eo;
            ok_round += ok; total++; ok_all += ok;
            if (f == 0) { if (r.us < lat_min) lat_min = r.us; if (r.us > lat_max) lat_max = r.us; }
            else { if (r.us < lat_f_min) lat_f_min = r.us; if (r.us > lat_f_max) lat_f_max = r.us; }
            xil_printf("%2d  | %-6s | %-19s | %s | %s    | 0x%02x (0x%02x)      | %2d/%d (%2d/%d)             | ",
                       c, nm, kd, g ? "GRANT" : "VETO ", eg ? "GRANT" : "VETO ", f, ef, s, o, es, eo);
            print_ms(r.us);
            xil_printf("    | %s%s%s\r\n", ok ? "DAT" : "SAI", r.timeout ? " (HET GIO)" : "",
                       r.pre ? " (GPIO1 truoc start != 0)" : "");
            wait_us(2000u);
        }
        xil_printf("Vong %d: %d/%d ca dung\r\n", rd, ok_round, N_CASE + 2);
    }
    xil_printf("\r\n=== TONG KET ===\r\n");
    xil_printf("Dung (quyet dinh + fault + buoc + vat can khop mo phong RTL): %d/%d\r\n", ok_all, total);
    xil_printf("Do tre TSM, duong binh thuong (fault=0): "); print_ms(lat_min); xil_printf(" .. "); print_ms(lat_max);
    xil_printf(" ms (thiet ke: 1.500.000 chu ky @ 187,5 MHz = 8,000 ms)\r\n");
    if (lat_f_max) { xil_printf("Do tre TSM, ca co loi                  : "); print_ms(lat_f_min); xil_printf(" .. ");
                     print_ms(lat_f_max); xil_printf(" ms\r\n"); }
    xil_printf("%s\r\n", ok_all == total ? "==== TSM TREN FPGA: DAT ====" : "==== TSM TREN FPGA: CO SAI ====");
    return 0;
}
