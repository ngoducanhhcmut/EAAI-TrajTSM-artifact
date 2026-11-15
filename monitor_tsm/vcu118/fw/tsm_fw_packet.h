/* Claude 09/11/2026 - VCU118 firmware core: planner waypoints -> TSM-X 721-bit packet (E2 encoding).
 * Port of tb_e2e_traj_tsm.sv::firmware_packet (W10b3), itself equal to packetizer_v2.encode_state(...,'E2').
 * Endianness-independent: all packet fields are handled as big-endian byte arrays (MSB first). */
#ifndef TSM_FW_PACKET_H
#define TSM_FW_PACKET_H
#include <stdint.h>

#define TSM_PLAN_BYTES   70   /* plan[559:0]                       */
#define TSM_IDS_BYTES    16   /* ids(3x32) + schema(32) = [127:0]   */

/* packet = {valid(1), plan(560), crc32(32), ids_schema(128)} = 721 bits.
 * In memory: valid flag separate, plan[70], crc (uint32), ids[16]. */
typedef struct {
    uint8_t  valid;
    uint8_t  plan[TSM_PLAN_BYTES];
    uint32_t crc;
    uint8_t  ids[TSM_IDS_BYTES];
} tsm_packet_t;

uint32_t tsm_crc32(const uint8_t *buf, unsigned n, uint32_t c);   /* zlib CRC-32 state update */
uint32_t tsm_packet_crc(const tsm_packet_t *p);                     /* CRC over {plan, ids} */
/* Rewrite x/v/a of the plan from the 8 planner waypoint words (binary32, CSR order) and the plan's
 * own measured snapshot, then reseal the CRC. Returns 0 on success, -1 on a non-finite waypoint. */
int tsm_fw_encode(tsm_packet_t *p, const uint32_t wp[8]);
#endif
