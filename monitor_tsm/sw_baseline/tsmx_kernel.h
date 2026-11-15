/* Claude 04/11/2026: C port of the TSM-X golden decision kernel (golden/tsmx_golden/model.py):
 * b4_mrmgen (continuous jerk-limited ramp, exact capped-ramp integrals), b3_geom (division-free
 * sound envelopes, G1c) and select_world. Bit-exact with the Python golden (Python floor/ceil
 * division semantics, 256-bit intermediates where the golden exceeds 64 bits).
 * Portable C99 (no __int128): the same source runs on Cortex-A53 (AArch64) and Cortex-R5F.
 */
#ifndef TSMX_KERNEL_H
#define TSMX_KERNEL_H
#include <stdint.h>

#define TS_S   1000000LL
#define TS_T   1000000LL
#define TS_DT  100000LL
#define TS_MAXROWS 130
#define TS_MAXOBJ  32

typedef struct { int64_t t, xl, xh, vl, vh, a, jerk; } ts_row;
typedef struct { int accept; int nrows; int64_t stop; int reason; ts_row rows[TS_MAXROWS]; } ts_traj;
typedef struct { int64_t x, v, a, length, event, after_a; } ts_obj;
typedef struct { int accept; int64_t margin; int reason; int steps; } ts_geom;
typedef struct { int64_t lane0, lane1, y, half_width, lateral_error, reserve; } ts_lane;

/* reasons (subset of golden strings, numbered for comparison) */
enum { R_OK = 0, R_RANGE, R_PHASE, R_HORIZON, R_TRAJ, R_LANE_RANGE, R_NUMERIC, R_OBJ_OVF,
       R_LANE, R_OBJ_RANGE, R_OBJ_SPEED, R_TIME, R_SEPARATION };

void ts_b4_mrmgen(int64_t x, int64_t v, int64_t a, int cid, int64_t phase, int limit, ts_traj *out);
void ts_b3_geom(const ts_traj *tr, const ts_obj *objs, int nobj, const ts_lane *ln, ts_geom *out);
int  ts_select_world(int64_t x, int64_t v, int64_t a, const ts_obj *objs, int nobj, const ts_lane *ln);
extern const ts_lane TS_LANE_DEFAULT;
#endif
