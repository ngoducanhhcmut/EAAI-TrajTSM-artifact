/* Minimal R5 app: run only real-data TSM scenario B0 (NuScenes H0261).
 * This deliberately bypasses the VLA weight-loader gate; it demonstrates the
 * independently tested TSM PL block using one precomputed trajectory/WM pair.
 */
#include <stdint.h>
#include <string.h>
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xtime_l.h"
#include "xparameters.h"
#include "onecase_data.h"

#define PLAN_BASE       0xA0000000u
#define GPIO0_BASE      0xA0010000u
#define GPIO1_BASE      0xA0020000u
#ifdef TSM_OCM   /* bitstream hw_tsm_only/build_tsm_ocm.tcl: bo dem TSM o OCM (DDR board lab khong dung duoc) */
#define TSM_TRAJ_BUF    0xFFFE0000u
#define TSM_WM_BUF      0xFFFE1000u
#else
#define TSM_TRAJ_BUF    0x70300000u
#define TSM_WM_BUF      0x70400000u
#endif
#define TRAJ_BYTES      1404u
#define WM_BYTES        6400u
#define UART0_BASE      0xFF000000u

/* Use direct polled UART I/O so the console works when XSDB bypasses FSBL. */
void outbyte(char c) {
    while (Xil_In32(UART0_BASE + 0x2Cu) & 0x10u) { } /* TX FIFO full */
    Xil_Out32(UART0_BASE + 0x30u, (uint8_t)c);
}

static void uart0_init(void) {
    Xil_Out32(UART0_BASE + 0x00u, 0x28u); /* disable RX/TX */
    Xil_Out32(UART0_BASE + 0x00u, 0x03u); /* reset RX/TX FIFOs */
    Xil_Out32(UART0_BASE + 0x04u, 0x20u); /* 8-N-1, normal mode */
    Xil_Out32(UART0_BASE + 0x18u, 0x33u); /* ZCU106 PS init: 115200 baud */
    Xil_Out32(UART0_BASE + 0x34u, 0x10u);
    Xil_Out32(UART0_BASE + 0x00u, 0x14u); /* enable RX/TX */
}

static void copy_words(uint32_t dst_addr, uint32_t src_addr, uint32_t words,
                       const char *tag) {
    volatile uint32_t *dst = (volatile uint32_t *)dst_addr;
    const volatile uint32_t *src = (const volatile uint32_t *)src_addr;
    for (uint32_t i = 0; i < words; ++i) {
        if ((i & 63u) == 0u)
            xil_printf("%s chunk %u start @ 0x%08x\r\n", tag, i / 64u,
                       dst_addr + i * 4u);
        dst[i] = src[i];
        if ((i & 7u) == 7u || i + 1u == words)
            xil_printf("%s %u/%u words\r\n", tag, i + 1u, words);
    }
}

static uint32_t crc32_ieee(const volatile uint8_t *data, uint32_t bytes) {
    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < bytes; ++i) {
        crc ^= data[i];
        for (unsigned bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ ((crc & 1u) ? 0xEDB88320u : 0u);
    }
    return crc ^ 0xFFFFFFFFu;
}

static int verify_ddr_copy(uint32_t ddr_addr, const uint32_t *source,
                           uint32_t words, const char *tag) {
    const volatile uint32_t *ddr = (const volatile uint32_t *)ddr_addr;
    for (uint32_t i = 0; i < words; ++i) {
        if (ddr[i] != source[i]) {
            xil_printf("DDR VERIFY FAIL %s word %u exp=0x%08x got=0x%08x\r\n",
                       tag, i, source[i], ddr[i]);
            return 0;
        }
    }
    xil_printf("DDR VERIFY OK %s (%u words)\r\n", tag, words);
    return 1;
}

int main(void) {
    XTime start, now;
    Xil_DCacheDisable(); /* PL reads these buffers too; write DDR uncached. */
    uart0_init();
    xil_printf("UART BOOT\r\n");
    xil_printf("\r\n=== TSM ONE-CASE DEMO: nuScenes H0261 ===\r\n");
#ifndef TSM_ONLY   /* bitstream chi-TSM (hw_tsm_only) khong co thanh ghi VLA-Traj o 0xA000_0000 */
    Xil_Out32(PLAN_BASE + 0x034u, 1u);
    Xil_Out32(PLAN_BASE + 0x008u, 0u);
#endif
    xil_printf("Loading one precomputed trajectory and world model...\r\n");
    uint32_t probe = ONECASE_TRAJ[0];
    xil_printf("OCM data ready: 0x%08x\r\n", probe);
    xil_printf("Probing TSM trajectory DDR at 0x%08x...\r\n", TSM_TRAJ_BUF);
    Xil_Out32(TSM_TRAJ_BUF, probe);
    xil_printf("TSM trajectory DDR write OK\r\n");
    copy_words(TSM_TRAJ_BUF, (uint32_t)ONECASE_TRAJ, TRAJ_BYTES / 4u, "trajectory");
    xil_printf("Trajectory copy OK\r\n");
    copy_words(TSM_WM_BUF, (uint32_t)ONECASE_WM, WM_BYTES / 4u, "world model");
    xil_printf("World-model copy OK\r\n");
    /* Drain R5 stores before the PL is allowed to read the shared DDR. */
    __asm__ volatile("dsb sy" ::: "memory");
    uint32_t src_crc = crc32_ieee((const volatile uint8_t *)ONECASE_TRAJ, 1400u);
    uint32_t ddr_crc = crc32_ieee((const volatile uint8_t *)TSM_TRAJ_BUF, 1400u);
    uint32_t src_crc_word = ONECASE_TRAJ[350];
    uint32_t ddr_crc_word = ((const volatile uint32_t *)TSM_TRAJ_BUF)[350];
    xil_printf("CRC source calc/stored: 0x%08x / 0x%08x\r\n", src_crc, src_crc_word);
    xil_printf("CRC DDR    calc/stored: 0x%08x / 0x%08x\r\n", ddr_crc, ddr_crc_word);
    if (src_crc != src_crc_word || ddr_crc != ddr_crc_word ||
        !verify_ddr_copy(TSM_TRAJ_BUF, ONECASE_TRAJ, TRAJ_BYTES / 4u, "trajectory") ||
        !verify_ddr_copy(TSM_WM_BUF, ONECASE_WM, WM_BYTES / 4u, "world model")) {
        xil_printf("FAIL: DDR payload verification failed; TSM not started\r\n");
        return 2;
    }
    __asm__ volatile("dsb sy" ::: "memory");
    /* Fault state before start: fault bits here can only come from an earlier run. */
    xil_printf("GPIO1 before start=0x%08x\r\n", Xil_In32(GPIO1_BASE));
    Xil_Out32(GPIO0_BASE, 1u);
    Xil_Out32(GPIO0_BASE, 0u);
    XTime_GetTime(&start);
    uint32_t loops = 0;
    while ((Xil_In32(GPIO1_BASE) & 0x2u) == 0u) {
        XTime_GetTime(&now);
        if (++loops > 50000000u || (now - start) > (COUNTS_PER_SECOND / 2u)) {
            xil_printf("FAIL: TSM timeout, GPIO1=0x%08x\r\n", Xil_In32(GPIO1_BASE));
            return 1;
        }
    }
    XTime_GetTime(&now);
    uint32_t status = Xil_In32(GPIO1_BASE);
    uint32_t detail = Xil_In32(GPIO1_BASE + 8u);
    xil_printf("Scenario: real nuScenes H0261 collision case\r\n");
    xil_printf("Decision: %s (expected VETO)\r\n", (status & 1u) ? "GRANT" : "VETO");
    xil_printf("Fault=0x%02x, step=%u, obstacle=%u\r\n",
               (status >> 8) & 0x7fu, detail & 0xffffu, detail >> 16);
    xil_printf("TSM latency: %u us\r\n",
               (unsigned)(((now - start) * 1000000u) / COUNTS_PER_SECOND));
    xil_printf("GPIO1 raw=0x%08x done=%u fault_valid=%u\r\n",
               status, (status >> 1) & 1u, (status >> 15) & 1u);
    Xil_Out32(GPIO0_BASE + 8u, 1u);
    Xil_Out32(GPIO0_BASE + 8u, 0u);
    xil_printf("=== ONE-CASE DEMO COMPLETE ===\r\n");
    return 0;
}
