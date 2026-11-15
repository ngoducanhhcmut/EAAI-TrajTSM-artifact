/* Claude 09/11/2026: host-side bit-exactness test of tsm_fw_packet.c against the 35 E2E bench packets.
 * The input packet's x/v/a and CRC are first scrambled, so the result must be fully recomputed.
 * Also checks that the frame-7 mutant word changes the packet. Exit 0 only if 35/35 match and mutant differs. */
#include <stdio.h>
#include <string.h>
#include "tsm_fw_packet.h"

static int hexval(char c) { return c <= '9' ? c - '0' : (c | 32) - 'a' + 10; }
/* 181 hex digits = 724 bits, packet occupies [720:0] */
static void parse_packet(const char *h, tsm_packet_t *p) {
    uint8_t bits[91]; /* 724 bits -> 90.5 bytes; left-pad one nibble to 728 bits = 91 bytes */
    char buf[183]; buf[0] = '0'; memcpy(buf + 1, h, 181); buf[182] = 0;
    for (int i = 0; i < 91; i++) bits[i] = (uint8_t)(hexval(buf[2 * i]) << 4 | hexval(buf[2 * i + 1]));
    /* 728-bit big-endian: bit b at byte 90 - b/8. valid=bit720, plan=[719:160], crc=[159:128], ids=[127:0] */
    p->valid = (bits[90 - 720 / 8] >> (720 % 8)) & 1;
    memcpy(p->plan, &bits[90 - 719 / 8], 70);
    p->crc = (uint32_t)bits[90 - 159 / 8] << 24 | (uint32_t)bits[91 - 159 / 8] << 16 |
             (uint32_t)bits[92 - 159 / 8] << 8 | bits[93 - 159 / 8];
    memcpy(p->ids, &bits[90 - 127 / 8], 16);
}
static int same(const tsm_packet_t *a, const tsm_packet_t *b) {
    return a->valid == b->valid && a->crc == b->crc && !memcmp(a->plan, b->plan, 70) && !memcmp(a->ids, b->ids, 16);
}
int main(int argc, char **argv) {
    FILE *f = fopen(argc > 1 ? argv[1] : "fw_cases.txt", "r");
    char line[1024]; int n = 0, ok = 0, mframe = -1, mut_changed = 0; unsigned mword = 0;
    tsm_packet_t saved[64]; uint32_t savedwp[64][8];
    if (!f) { perror("fw_cases"); return 2; }
    while (fgets(line, sizeof line, f)) {
        if (!strncmp(line, "MUTANT", 6)) { sscanf(line + 6, "%d %x", &mframe, &mword); continue; }
        int fr, job; uint32_t wp[8]; char hex[200];
        if (sscanf(line, "%d %d %x %x %x %x %x %x %x %x %190s", &fr, &job, &wp[0], &wp[1], &wp[2], &wp[3],
                   &wp[4], &wp[5], &wp[6], &wp[7], hex) != 11) continue;
        tsm_packet_t ref, fw;
        parse_packet(hex, &ref);
        if (tsm_packet_crc(&ref) != ref.crc) { printf("frame %d: reference CRC inconsistent\n", fr); }
        fw = ref;                                   /* firmware receives the template (seq/snapshot/epochs/ids) */
        memset(fw.plan + 70 - 26, 0xA5, 16);        /* scramble plan[207:80] = x,v,a */
        fw.crc ^= 0xdeadbeefu; fw.valid = 0;
        if (tsm_fw_encode(&fw, wp)) { printf("frame %d: non-finite waypoint\n", fr); continue; }
        n++;
        if (same(&fw, &ref)) ok++; else printf("PACKET_MISMATCH frame=%d job=%d\n", fr, job);
        saved[fr] = ref; memcpy(savedwp[fr], wp, sizeof wp);
    }
    if (mframe >= 0 && mframe < n) {
        tsm_packet_t m = saved[mframe]; uint32_t wp[8]; memcpy(wp, savedwp[mframe], sizeof wp);
        wp[0] = mword;
        if (!tsm_fw_encode(&m, wp) && !same(&m, &saved[mframe])) mut_changed = 1;
    }
    printf("FW_PACKETS %d/%d bit-exact; mutant frame %d word0=%08x packet %s\n", ok, n, mframe, mword,
           mut_changed ? "CHANGED" : "UNCHANGED");
    return (n == 35 && ok == 35 && mut_changed) ? 0 : 1;
}
