"""Claude 04/11/2026: drop DIRECT-mode-only health-injection vectors for the board (PARA_DIRECT=0) path.
In PARA_DIRECT=1 the health monitor is fed from the request payload (reg_req[33823:0]) so vectors can
inject a health fault; in PARA_DIRECT=0 (board) it checks the real internal parity/BIST state, so those
jobs (golden reason 40/41 with request healthy-flag req[33858]=1) cannot be reproduced. The job and the
rest of its reset segment (state-dependent) are removed; the next segment starts at a reset job.
usage: python filter_health_inject.py <in.mem> <out.mem> [first_n]
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_board_vectors import fields
src, dst = sys.argv[1], sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else None
lines = [l for l in Path(src).read_text().split() if l][:n]
keep, drop, skipping = [], [], False
for j, l in enumerate(lines):
    f = fields(l)
    if f['reset']: skipping = False
    if not skipping and ((f['rsp'] >> 29) & 0xff) in (40, 41) and (f['req'] >> 33858) & 1:
        skipping = True
    (drop if skipping else keep).append((j, l))
assert keep and fields(keep[0][1])['reset'] == 1
Path(dst).write_text('\n'.join(l for _, l in keep) + '\n')
print(f'{src}: {len(lines)} jobs -> kept {len(keep)}, dropped {len(drop)}: {[j for j, _ in drop]}')
