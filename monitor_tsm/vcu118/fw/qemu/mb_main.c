/* Claude 09/11/2026: run the firmware core on an emulated MicroBlaze (QEMU petalogix-ml605, little endian,
 * soft-float binary64 as on the VCU118 MicroBlaze) against the 35 bench packets; prints via the 16550 UART. */
#include <string.h>
#include "../tsm_fw_packet.h"
#include "cases_data.h"
#define UART_THR (*(volatile unsigned *)0x83e01000u)
#define UART_LSR (*(volatile unsigned *)0x83e01014u)
static void putch(char c) { while (!(UART_LSR & 0x20u)) {} UART_THR = (unsigned char)c; }
static void puts_(const char *s) { while (*s) putch(*s++); }
static void putdec(unsigned v) { char b[12]; int i = 0; do { b[i++] = (char)('0' + v % 10); v /= 10; } while (v); while (i) putch(b[--i]); }
static int hexval(char c) { return c <= '9' ? c - '0' : (c | 32) - 'a' + 10; }
static void parse_packet(const char *h, tsm_packet_t *p) {
    unsigned char bits[91]; char buf[183]; buf[0] = '0'; memcpy(buf + 1, h, 181);
    for (int i = 0; i < 91; i++) bits[i] = (unsigned char)(hexval(buf[2 * i]) << 4 | hexval(buf[2 * i + 1]));
    p->valid = (bits[0] >> 0) & 1;
    memcpy(p->plan, &bits[1], 70);
    p->crc = (unsigned)bits[71] << 24 | (unsigned)bits[72] << 16 | (unsigned)bits[73] << 8 | bits[74];
    memcpy(p->ids, &bits[75], 16);
}
static int same(const tsm_packet_t *a, const tsm_packet_t *b) {
    return a->valid == b->valid && a->crc == b->crc && !memcmp(a->plan, b->plan, 70) && !memcmp(a->ids, b->ids, 16);
}
int main(void) {
    unsigned ok = 0; int mut = 0;
    for (unsigned i = 0; i < NCASES; i++) {
        tsm_packet_t ref, fw; parse_packet(PKT[i], &ref); fw = ref;
        memset(fw.plan + 44, 0xA5, 16); fw.crc ^= 0xdeadbeefu; fw.valid = 0;
        if (!tsm_fw_encode(&fw, WP[i]) && same(&fw, &ref)) ok++;
        else { puts_("PACKET_MISMATCH frame="); putdec(i); putch('\n'); }
        if ((int)i == MUT_FRAME) { uint32_t w[8]; memcpy(w, WP[i], sizeof w); w[0] = MUT_WORD;
            tsm_packet_t m = ref; if (!tsm_fw_encode(&m, w) && !same(&m, &ref)) mut = 1; }
    }
    puts_("MB_FW_PACKETS "); putdec(ok); putch('/'); putdec(NCASES); puts_(mut ? " mutant CHANGED\n" : " mutant UNCHANGED\n");
    puts_("MB_DONE\n");
    for (;;) {}
}
