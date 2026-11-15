/* Claude 10/11/2026: host check of joint_fw.c packet extraction/splice on the real joint_data images:
 * for the 35 planner jobs, packet(req) re-encoded from the recorded RTL waypoints must equal the bench packet,
 * and splicing it back must leave all 5585 request bytes unchanged. Also a mutant waypoint must change bytes. */
#include <stdio.h>
#include <stdlib.h>
#define main fw_main
#include "joint_fw.c"
#undef main
static unsigned char *slurp(const char *p, long *n) { FILE *f = fopen(p, "rb"); fseek(f, 0, SEEK_END); *n = ftell(f); rewind(f);
  unsigned char *b = malloc(*n); fread(b, 1, *n, f); fclose(f); return b; }
int main(void) {
  long nr, nm, nw; unsigned char *req = slurp("joint_data/tsm_req.bin", &nr), *mt = slurp("joint_data/tsm_meta.bin", &nm), *wpb = slurp("joint_data/wp_golden.bin", &nw);
  int ok = 0, rt = 0, mut = 0, n = 0;
  for (int j = 0; j < 207; j++) {
    const meta_t *m = (const meta_t *)(mt + 32 * j); if (!m->fmap) continue; n++;
    int fr = (int)m->fmap - 1; const uint32_t *wp = (const uint32_t *)(wpb + 32 * fr);
    memcpy(reqbuf, req + 5600L * j, 5585);
    tsm_packet_t ref, fw; pkt_get(reqbuf, &ref); fw = ref;
    memset(fw.plan + 44, 0xA5, 16); fw.crc ^= 0x5a5a5a5au;
    if (!tsm_fw_encode(&fw, wp) && pkt_same(&fw, &ref)) ok++;
    pkt_put(reqbuf, &fw); if (!memcmp(reqbuf, req + 5600L * j, 5585)) rt++;
    if (fr == 7) { uint32_t w[8]; memcpy(w, wp, 32); w[0] = 0x45800000u; tsm_packet_t mm = ref; tsm_fw_encode(&mm, w);
      memcpy(reqbuf, req + 5600L * j, 5585); pkt_put(reqbuf, &mm); if (memcmp(reqbuf, req + 5600L * j, 5585)) mut = 1; }
  }
  printf("HOST_JOINT frames=%d packets_equal=%d splice_roundtrip=%d mutant_changes_request=%d\n", n, ok, rt, mut);
  return !(n == 35 && ok == 35 && rt == 35 && mut);
}
