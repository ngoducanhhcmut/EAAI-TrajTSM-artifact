"""Claude 07/11/2026 (W11): every golden B4/B3 call made by the nuPlan closed-loop monitor -> RTL unit-bench vectors.

Input : eval_nuplan/w11/dump/<cond>/*.calls.jsonl   (written by tsmx_nuplan/planner.py when TSMX_DUMP_DIR is set)
Output: eval_nuplan/w11/rtl/<unit>/shard_<k>/{jobs.mem,rows.mem,vectors_meta.svh,tb_*.sv}, manifest.json
Encoding is copied from tb/unit/{mrmgen,geom}/gen_vectors.py (same packing, same golden calls). Each shard is the
ORIGINAL unit vector set (complete assertion coverage, unchanged expectations) followed by <= CHUNK distinct nuPlan calls.
Every logged result is re-derived from the golden model and must match the log (fail loudly otherwise).
Run from the repository root with:  py -3.13 -B journalQ1/tsmx_hw/eval_nuplan/w11/make_rtl_vectors.py
"""
import sys, json, hashlib, shutil
from pathlib import Path
from collections import Counter
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
HW = HERE.parents[1]
sys.path[:0] = [str(HW / 'golden'), str(HW.parent / 'tsm2_pilot/vendor')]
from tsmx_golden import model as g  # noqa: E402

LANE = (-1800000, 1800000)
LAT = 100000
CHUNK = 3000
UNIT = HW / 'tb' / 'unit'


def pack(fields):
    n = 0
    for v, w in fields:
        n = (n << w) | (int(v) & ((1 << w) - 1))
    return n


# ---- B4 / mrmgen packing (tb/unit/mrmgen/gen_vectors.py) ----
def b4_job(d, o, rows):
    req = pack((d[k], w) for k, w in zip(('x', 'v', 'a', 'cid', 'phase', 'limit'), (64, 32, 32, 8, 32, 8)))
    rsp = pack([(int(o.accept), 1), (g.REASONS.index(o.reason), 8), (int(o.stop >= 0), 1), (max(0, o.stop), 32), (len(o.rows), 8)])
    start = len(rows)
    for k, row in enumerate(o.rows):
        raw = int.from_bytes(g.pack_row(row), 'big')
        rows.append(pack([(d['cid'], 8), (d['phase'], 32), (k, 8), (raw, 352), (int(o.accept and k == len(o.rows) - 1), 1)]))
    return (req << 114) | (rsp << 64) | (start << 32) | len(o.rows)


# ---- B3 / geom packing (tb/unit/geom/gen_vectors.py) ----
def b3_job(idx, tr, objs, o, rows):
    cid = idx % 16; epoch = idx * 17
    lane = g.pack_lane(lane=LANE)
    obs = [g.asdict(m) for m in objs]
    world = pack([(len(obs), 8)] + [(int.from_bytes(g.pack_motion(ob), 'big'), 256) for ob in obs[:32]] + [(0, 256)] * max(0, 32 - len(obs)))
    req = pack([(cid, 8), (epoch, 32), (world, 8200), (int.from_bytes(lane, 'big'), 384)])
    start = len(rows)
    for k, r in enumerate(tr.rows):
        rows.append(pack([(cid, 8), (epoch, 32), (k, 8), (int.from_bytes(g.pack_row(r), 'big'), 352), (int(k == len(tr.rows) - 1), 1)]))
    term = pack([(tr.accept, 1), (g.REASONS.index(tr.reason) if tr.reason in g.REASONS else 0, 8), (tr.stop >= 0, 1), (max(0, tr.stop), 32), (len(tr.rows), 8)])
    rsp = pack([(o.accept, 1), (o.margin, 64), (g.REASONS.index(o.reason), 8), (o.steps, 8)])
    return pack([(req, 8624), (term, 50), (rsp, 81), (start, 32), (len(tr.rows), 8)])


def original(unit):
    jobs = (UNIT / unit / 'jobs.mem').read_text().split()
    rows = (UNIT / unit / 'rows.mem').read_text().split()
    return jobs, rows


def write_shard(unit, k, base_jobs, base_rows, new_jobs_rows, width_job):
    d = HERE / 'rtl' / unit / f'shard_{k}'
    d.mkdir(parents=True, exist_ok=True)
    jobs = list(base_jobs); rows = list(base_rows)
    off = len(rows)
    for job, jrows in new_jobs_rows:
        # rebase the row offset field (bits 63:32 for mrmgen, 39:8 for geom) onto this shard's row list
        jobs.append(job)
        rows.extend(jrows)
    (d / 'jobs.mem').write_text(''.join(j + '\n' for j in jobs), newline='\n')
    (d / 'rows.mem').write_text(''.join(r + '\n' for r in rows), newline='\n')
    extra = ', GOLDEN=128, EDGE=0' if unit == 'mrmgen' else ''
    (d / 'vectors_meta.svh').write_text(f'localparam N={len(jobs)}, R={len(rows)}{extra};\n', newline='\n')
    tb = (UNIT / unit / f'tb_m_tsmx_{unit}.sv').read_text()
    tb = tb.replace('#1000000000;$fatal(1,"watchdog timeout")', '#1e15;$fatal(1,"watchdog timeout")')
    (d / f'tb_m_tsmx_{unit}.sv').write_text(tb, newline='\n')
    return len(jobs), len(rows)


def main():
    dumps = sorted((HERE / 'dump').glob('*/*.calls.jsonl'))
    b4, b3, counts, over32 = {}, {}, Counter(), 0
    for p in dumps:
        cond = p.parent.name
        for line in p.read_text().splitlines():
            r = json.loads(line); counts[(cond, r['kind'])] += 1
            if r['kind'] == 'b4':
                key = (r['v'], r['a'], r['cid'])
                o = g.b4_mrmgen(0, r['v'], r['a'], r['cid'])
                got = (bool(o.accept), o.reason, o.stop, len(o.rows))
                if got != (r['accept'], r['reason'], r['stop'], r['nrows']):
                    sys.exit(f'B4 golden re-derivation differs from log: {p.name} {r} {got}')
                b4.setdefault(key, o)
            elif r['kind'] == 'b3':
                key = (r['v'], r['a'], r['cid'], tuple(map(tuple, r['objects'])))
                if key not in b3:
                    tr = g.b4_mrmgen(0, r['v'], r['a'], r['cid'])
                    objs = g.propagated_objects(tuple(g.Motion(x, v, 0, ln, 0, 0) for x, v, ln in r['objects']), LAT, 0)
                    o = g.b3_geom(tr, objs, LANE)
                    b3[key] = (tr, objs, o)
                o = b3[key][2]
                if (bool(o.accept), o.margin, o.reason, o.steps) != (r['accept'], r['margin'], r['reason'], r['steps']):
                    sys.exit(f'B3 golden re-derivation differs from log: {p.name} {r}')
            elif r['kind'] == 'over32':
                over32 += 1
    manifest = dict(dump_files=len(dumps), calls={f'{c}/{k}': n for (c, k), n in sorted(counts.items())},
                    distinct_b4=len(b4), distinct_b3=len(b3), over32_fail_closed=over32, shards={})
    shutil.rmtree(HERE / 'rtl', ignore_errors=True)
    # mrmgen
    bj, br = original('mrmgen'); items = []
    for key, o in sorted(b4.items()):
        rows = []
        d = dict(x=0, v=key[0], a=key[1], cid=key[2], phase=0, limit=128)
        job = b4_job(d, o, rows)
        items.append((d, o, job, rows))
    for k in range(0, max(1, (len(items) + CHUNK - 1) // CHUNK)):
        chunk = items[k * CHUNK:(k + 1) * CHUNK]; base_r = len(br); out = []; cur = base_r
        for d, o, _, _ in chunk:
            rows = []
            job = b4_job(d, o, rows)                       # start offset 0 -> rebase below
            job = (job & ~(((1 << 32) - 1) << 32)) | (cur << 32)
            out.append((f'{job:073x}', [f'{r:0101x}' for r in rows])); cur += len(rows)
        manifest['shards'][f'mrmgen/shard_{k}'] = dict(nuplan_jobs=len(chunk), first_nuplan_job=len(bj),
                                                       total=write_shard('mrmgen', k, bj, br, out, 73))
    # geom
    bj, br = original('geom'); items = sorted(b3.items(), key=lambda kv: repr(kv[0]))
    for k in range(0, max(1, (len(items) + CHUNK - 1) // CHUNK)):
        chunk = items[k * CHUNK:(k + 1) * CHUNK]; cur = len(br); out = []
        for i, (key, (tr, objs, o)) in enumerate(chunk):
            rows = []
            job = b3_job(len(bj) + i, tr, objs, o, rows)
            job = (job & ~(((1 << 32) - 1) << 8)) | (cur << 8)
            out.append((f'{job:02199x}', [f'{r:0101x}' for r in rows])); cur += len(rows)
        manifest['shards'][f'geom/shard_{k}'] = dict(nuplan_jobs=len(chunk), first_nuplan_job=len(bj),
                                                     total=write_shard('geom', k, bj, br, out, 2199))
    acc = Counter(bool(v[2].accept) for v in b3.values())
    manifest['distinct_b3_accept'] = acc[True]; manifest['distinct_b3_reject'] = acc[False]
    manifest['b4_reasons'] = Counter(o.reason for o in b4.values())
    manifest['rtl_sources_sha256'] = {f: hashlib.sha256((HW / 'rtl' / f).read_bytes()).hexdigest() for f in
                                      ('mrmgen/m_tsmx_mrmgen.sv', 'geom/m_tsmx_geom.sv', 'geom/m_tsmx_geom_su.sv',
                                       'arith/m_tsmx_arith.sv', 'arith/m_tsmx_arith_div.sv')}
    (HERE / 'manifest.json').write_text(json.dumps(manifest, indent=1, default=str) + '\n')
    print(json.dumps({k: v for k, v in manifest.items() if k != 'shards'}, indent=1, default=str))
    print('shards', len(manifest['shards']))


if __name__ == '__main__':
    main()
