"""W9a RQ1 planner gate and resumable, bounded subprocess inference.

Never imports the executable verification tail which can update golden files.
"""
import sys
sys.dont_write_bytecode = True
import os
from pathlib import Path
OUT = Path(__file__).resolve().parent
HERE = OUT.parent
ROOT = HERE.parents[2]
for key in ('TEMP', 'TMP', 'MPLCONFIGDIR'):
    os.environ[key] = str(OUT)
for key in ('OMP_NUM_THREADS', 'MKL_NUM_THREADS', 'OPENBLAS_NUM_THREADS'):
    os.environ[key] = '1'

def guard(event, args):
    if event == 'open':
        path, mode, flags = args
        writing = (isinstance(mode, str) and any(c in mode for c in 'wax+')) or (flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC))
        if writing and not isinstance(path, int):
            if os.fsdecode(path).lower() in ('nul', '\\\\.\\nul'):
                return  # Windows null device has no filesystem contents.
            p = Path(os.fsdecode(path)).resolve()
            if p != OUT and OUT not in p.parents:
                raise PermissionError('W9a write outside output directory: ' + str(p))
    if event in ('os.rename', 'os.remove', 'os.mkdir', 'os.rmdir'):
        paths = args[:2] if event == 'os.rename' else args[:1]
        for path in paths:
            p = Path(os.fsdecode(path)).resolve()
            if p != OUT and OUT not in p.parents:
                raise PermissionError('W9a mutation outside output directory: ' + str(p))

sys.addaudithook(guard)
sys.path[:0] = [str(HERE), str(ROOT/'eval'), str(ROOT/'sw'), str(ROOT/'sw/hwspec'), str(ROOT/'sw/eval_trainval')]
import argparse
import json
import time
import shutil
import hashlib
import subprocess
import numpy as np

def dump(name, value):
    path = OUT/name
    tmp = path.with_suffix(path.suffix+'.tmp')
    tmp.write_text(json.dumps(value, indent=2, allow_nan=False), encoding='utf-8')
    os.replace(tmp, path)

def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(4 << 20), b''):
            h.update(b)
    return h.hexdigest()

def recover_records(path):
    """Flush-per-record shards may have an incomplete final line after a crash."""
    if not path.exists():
        return []
    data = path.read_bytes()
    end = data.rfind(b'\n') + 1
    records = [json.loads(line) for line in data[:end].splitlines()]
    if end != len(data):
        with path.open('r+b') as f:
            f.truncate(end)
    return records

def exact_integer_blas():
    """Protocol A2 proof: sum abs(products) <= 2048*128*8 < 2**24.

    Every integer product and every possible partial sum is exactly representable
    in binary32, including FMA/reordered reductions. No floating GRU op changes.
    """
    import hwspec_exact as hx
    original=hx.mm
    weights={}
    def fast(w,x):
        assert w.shape[-1]==x.shape[-1] and w.shape[-1]*128*8 < 2**24
        if id(w) not in weights:
            assert np.min(w)>=-8 and np.max(w)<=7
            weights[id(w)]=(w,w.astype(np.float32))
        assert np.min(x)>=-128 and np.max(x)<=127
        return (x.astype(np.float32)@weights[id(w)][1].T).astype(np.int32)
    rng=np.random.default_rng(20261104)
    for dim in (512,2048):
        w=rng.integers(-8,8,(512,dim),dtype=np.int8)
        x=rng.integers(-128,128,(64,dim),dtype=np.int8)
        assert np.array_equal(original(w,x),fast(w,x)), 'Exact integer BLAS check failed'
    hx.mm=fast

def prepare():
    from data.nuscenes_lite import load_nuscenes
    from data.nuscenes_loader import build_tokens_for_sample
    manifest = json.loads((HERE/'results/manifest.json').read_text())
    root = Path(manifest['dataset'])
    assert (root/'v1.0-trainval/_nuscenes_lite_v2.pkl').exists()
    nusc = load_nuscenes('v1.0-trainval', str(root))
    d = np.load(ROOT/'sw/eval_trainval/out/dataset.npz')
    assert len(d['keep']) == 5419 and d['keep'].all()
    tok = np.empty_like(d['tok']); pad = np.empty_like(d['pad'])
    for i, token in enumerate(d['token']):
        tok[i], pad[i] = build_tokens_for_sample(nusc, str(token), include_lane_tokens=True)
        if i % 500 == 0:
            print('rebuild validation inputs', i, flush=True)
    discrepancies = np.flatnonzero(np.any(tok != d['tok'], axis=(1,2)) | np.any(pad != d['pad'], axis=1))
    dump('input_check.json', dict(frames=len(tok), discrepancies=len(discrepancies), first_indices=discrepancies[:20].tolist(), max_abs_token_diff=float(np.max(np.abs(tok-d['tok'])))))
    np.savez(OUT/'gate_inputs.npz', tok=tok, pad=pad, token=d['token'])

def worker(stage, shard, workers):
    if stage in ('build_gate','build_full'):
        return input_worker(stage,shard,workers)
    import run_models as rm
    assert (ROOT/'sw/hwspec/_cache_params.pkl').exists(), 'Do not rebuild hardware parameter cache'
    rm._init('hw_new')
    exact_integer_blas()
    with np.load(OUT/(stage+'_inputs.npz')) as d:
        tokens, tok, pad = d['token'], d['tok'], d['pad']
    path = OUT/f'{stage}_{shard}.jsonl'
    done = set()
    if path.exists():
        done = {r['i'] for r in recover_records(path)}
    reference = np.load(ROOT/'sw/eval_trainval/out/pred_hw_new.npy') if stage == 'gate' else None
    validated = {}
    if stage == 'full':
        for s in range(workers):
            for line in (OUT/f'gate_{s}.jsonl').read_text().splitlines():
                r = json.loads(line)
                validated[r['token']] = np.asarray(r['wp'], np.float32)
    with path.open('a', encoding='utf-8', buffering=1) as f:
        for i in range(shard, len(tok), workers):
            if i in done:
                continue
            if str(tokens[i]) in validated:
                wp = validated[str(tokens[i])]
            else:
                _, wp = rm._run((i, tok[i], pad[i]))
            rec = dict(i=i, token=str(tokens[i]), wp=wp.tolist())
            if reference is not None:
                rec['max_abs_diff'] = float(np.max(np.abs(wp-reference[i])))
                rec['exact'] = bool(np.array_equal(wp, reference[i]))
            f.write(json.dumps(rec, allow_nan=False)+'\n')
            if i % (workers*25) == shard:
                print(stage, shard, i, rec.get('max_abs_diff'), flush=True)

def pool(stage, workers, script=None):
    children = []
    for shard in range(workers):
        log = (OUT/f'{stage}_{shard}.log').open('a', encoding='utf-8')
        p = subprocess.Popen([sys.executable, '-B', str(script or Path(__file__).resolve()), '--stage', stage, '--shard', str(shard), '--workers', str(workers)], stdout=log, stderr=subprocess.STDOUT, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        children.append((p, log))
    try:
        while any(p.poll() is None for p, _ in children):
            for p, _ in children:
                if p.poll() not in (None, 0):
                    raise RuntimeError('Worker failed; inspect shard logs')
            time.sleep(2)
        assert all(p.returncode == 0 for p, _ in children)
    finally:
        for p, log in children:
            if p.poll() is None:
                p.terminate()
                p.wait()
            log.close()

def prepare_full():
    from data.nuscenes_lite import load_nuscenes
    from data.nuscenes_loader import build_tokens_for_sample
    import run_w7 as w
    os.environ['TEMP'] = os.environ['TMP'] = str(OUT)
    root = Path(json.loads((HERE/'results/manifest.json').read_text())['dataset'])
    nusc = load_nuscenes('v1.0-trainval', str(root))
    expected = []
    for scene in sorted(nusc.scene, key=lambda s:(s['name'], s['token'])):
        samples = w.scene_data(nusc, scene)[0]
        expected.extend(s['token'] for s in samples[:-6])
    with (HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
        rows = [json.loads(l) for l in f]
    assert len(rows) == 29049
    assert expected == [r['token'] for r in rows], 'W7 order mismatch'
    tok = np.empty((len(rows),64,6),np.float32)
    pad = np.empty((len(rows),64),bool)
    gate = np.load(OUT/'gate_inputs.npz')
    gate_index = {str(t):i for i,t in enumerate(gate['token'])}
    for i,r in enumerate(rows):
        tok[i],pad[i] = build_tokens_for_sample(nusc,r['token'],include_lane_tokens=True)
        if r['token'] in gate_index:
            j = gate_index[r['token']]
            assert np.array_equal(tok[i],gate['tok'][j]) and np.array_equal(pad[i],gate['pad'][j])
        if i % 1000 == 0:
            print('build full',i,flush=True)
    np.savez(OUT/'full_inputs.npz',tok=tok,pad=pad,token=np.array(expected))
    dump('frame_check.json',dict(eligible=len(rows),order_exact=True,scenes=850,keyframes=34149,gate_reused_frames=sum(t in gate_index for t in expected)))

def input_worker(stage,shard,workers):
    assert shutil.disk_usage('C:/').free >= 10_000_000_000, 'C: free space below 10 GB'
    from data.nuscenes_lite import load_nuscenes
    from data.nuscenes_loader import build_tokens_for_sample
    root = Path(json.loads((HERE/'results/manifest.json').read_text())['dataset'])
    assert (root/'v1.0-trainval/_nuscenes_lite_v2.pkl').exists()
    nusc = load_nuscenes('v1.0-trainval',str(root))
    d = np.load(ROOT/'sw/eval_trainval/out/dataset.npz')
    gate_index = {str(t):i for i,t in enumerate(d['token'])}
    if stage == 'build_full':
        with np.load(OUT/'gate_inputs.npz') as checked:
            checked_tok,checked_pad=checked['tok'],checked['pad']
    if stage == 'build_gate':
        tokens = list(map(str,d['token']))
    else:
        with (HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
            tokens = [json.loads(l)['token'] for l in f]
        expected=[]
        for scene in sorted(nusc.scene,key=lambda s:(s['name'],s['token'])):
            chain=[]; token=scene['first_sample_token']
            while token:
                chain.append(token); token=nusc.get('sample',token)['next']
            expected.extend(chain[:-6])
        assert tokens == expected and len(tokens)==29049
    indices=list(range(shard,len(tokens),workers))
    for offset in range(0,len(indices),64):
        target=OUT/f'{stage}_{shard}_{offset}.npz'
        if target.exists():
            continue
        ids=indices[offset:offset+64]
        tok=np.empty((len(ids),64,6),np.float32); pad=np.empty((len(ids),64),bool)
        for k,i in enumerate(ids):
            if stage=='build_full' and tokens[i] in gate_index:
                j=gate_index[tokens[i]]
                tok[k],pad[k]=checked_tok[j],checked_pad[j]
            else:
                tok[k],pad[k]=build_tokens_for_sample(nusc,tokens[i],include_lane_tokens=True)
        temp=target.with_suffix('.tmp')
        with temp.open('wb') as f:
            np.savez(f,i=np.array(ids),tok=tok,pad=pad,token=np.array([tokens[i] for i in ids]))
        os.replace(temp,target)
        print(stage,shard,offset+len(ids),'/',len(indices),flush=True)

def parallel_inputs(stage,workers):
    pool('build_'+stage,workers)
    files=list(OUT.glob('build_'+stage+'_*.npz'))
    size=5419 if stage=='gate' else 29049
    tok=np.empty((size,64,6),np.float32); pad=np.empty((size,64),bool); tokens=np.empty(size,dtype='<U32'); seen=[]
    for path in files:
        with np.load(path) as d:
            ids=d['i']; tok[ids]=d['tok']; pad[ids]=d['pad']; tokens[ids]=d['token']; seen.extend(ids.tolist())
    assert sorted(seen)==list(range(size))
    assert shutil.disk_usage('C:/').free >= 10_000_000_000, 'C: free space below 10 GB'
    np.savez(OUT/(stage+'_inputs.npz'),tok=tok,pad=pad,token=tokens)
    if stage=='gate':
        d=np.load(ROOT/'sw/eval_trainval/out/dataset.npz')
        assert d['keep'].all() and np.array_equal(tokens,d['token'])
        bad=np.flatnonzero(np.any(tok!=d['tok'],axis=(1,2))|np.any(pad!=d['pad'],axis=1))
        dump('input_check.json',dict(frames=size,discrepancies=len(bad),first_indices=bad[:20].tolist(),max_abs_token_diff=float(np.max(np.abs(tok-d['tok'])))))
    else:
        dump('frame_check.json',dict(eligible=size,order_exact=True,scenes=850,keyframes=34149))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--workers', type=int, default=4)
    ap.add_argument('--shard', type=int)
    ap.add_argument('--stage', default='gate')
    a = ap.parse_args()
    assert 1 <= a.workers <= 4
    if a.shard is not None:
        return worker(a.stage, a.shard, a.workers)
    start = time.monotonic()
    free = shutil.disk_usage('C:/').free
    assert free >= 10_000_000_000, ('C: free space below 10 GB', free)
    import ctypes
    ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
    dump('status.json', dict(status='REUSING_W9A2_GATE', start_utc=__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(), free_bytes_before=free, workers=a.workers))
    try:
        # W9a3 supervisor: reuse complete W9a2 evidence; never rerun the gate.
        assert (OUT/'gate_inputs.npz').exists()
        verification = json.loads((OUT/'w9a2_gate_verification.json').read_text())
        assert verification['all_gate_indices_unique_complete']
        records = []
        for shard in range(a.workers):
            records.extend(json.loads(l) for l in (OUT/f'gate_{shard}.jsonl').read_text().splitlines())
        records.sort(key=lambda r:r['i'])
        assert [r['i'] for r in records] == list(range(5419))
        gate = json.loads((OUT/'gate.json').read_text())
        assert gate['frames'] == 5419 and gate['mismatches'] == [r for r in records if not r['exact']]
        gate.update(tolerance_m=1e-5, passed=bool(gate['max_abs_diff'] <= 1e-5), within_tolerance_frames=sum(r['max_abs_diff'] <= 1e-5 for r in records), reused_from='W9a2; no gate inference rerun')
        dump('gate.json', gate)
        if not gate['passed']:
            raise RuntimeError('RQ1 tolerance gate failed; full run prohibited')
        dump('status.json', dict(status='GATE_PASSED', runtime_seconds=time.monotonic()-start))
        if not (OUT/'full_inputs.npz').exists():
            dump('status.json', dict(status='BUILD_FULL_INPUTS', runtime_seconds=time.monotonic()-start))
            parallel_inputs('full',a.workers)
        dump('status.json', dict(status='FULL_PLANNER_RUNNING', runtime_seconds=time.monotonic()-start))
        pool('full', a.workers)
        dump('status.json', dict(status='DECISIONS_RUNNING', runtime_seconds=time.monotonic()-start))
        pool('replay', a.workers, OUT/'replay.py')
        import replay
        replay.finalize(time.monotonic()-start)
        dump('status.json', dict(status='COMPLETE', runtime_seconds=time.monotonic()-start))
    except Exception as e:
        dump('status.json', dict(status='STOPPED', error=repr(e), runtime_seconds=time.monotonic()-start))
        raise
    finally:
        ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)

if __name__ == '__main__':
    main()
