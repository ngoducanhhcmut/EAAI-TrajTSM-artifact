"""Claude 09/11/2026: extract the 35 firmware cases of the E2E bench (e2e_traj_tsm) into fw_cases.txt.
Per frame: 8 recorded planner waypoint words (recorded_wp.mem, what the bench's firmware consumes),
the reference 721-bit packet from vectors.mem (request[44384:43664]), and the mutant word for frame 7.
Expected firmware output = reference packet (bench: 0/35 mismatches)."""
from pathlib import Path
E = Path(__file__).resolve().parents[2] / 'e2e_traj_tsm'
VW = 48037
vec = [int(l, 16) for l in (E / 'vectors.mem').read_text().split()]
frm = [int(l, 16) for l in (E / 'frames.mem').read_text().split()]
wps = [int(l, 16) for l in (E / 'recorded_wp.mem').read_text().split()]
vc = (E / 'vector_count.svh').read_text()
mut_frame = int(vc.split('MUTANT_FRAME=')[1].split(';')[0])
mut_word = int(vc.split("32'h")[1].split(';')[0], 16)
out = []
for j, (v, f) in enumerate(zip(vec, frm)):
    if f == 0:
        continue
    fr = f - 1
    req = (v >> (VW - 1 - 44673)) & ((1 << 44673) - 1)
    pkt = (req >> 43664) & ((1 << 721) - 1)
    out.append(f'{fr} {j} ' + ' '.join(f'{w:08x}' for w in wps[8 * fr:8 * fr + 8]) + f' {pkt:0181x}')
assert len(out) == 35
(Path(__file__).parent / 'fw_cases.txt').write_text('\n'.join(out) + f'\nMUTANT {mut_frame} {mut_word:08x}\n')
print('cases', len(out), 'mutant frame', mut_frame, hex(mut_word))
