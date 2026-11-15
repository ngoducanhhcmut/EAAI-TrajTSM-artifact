"""Check every serialized request/decision against retained golden audit rows.

This checks artifact integrity and scene continuity, not another golden run or
RTL agreement. The golden run itself creates retained-state outputs from reset.
"""
import sys, json, hashlib, itertools
sys.dont_write_bytecode=True
import packetizer_v2 as pk
from collections import Counter
HERE=pk.HERE

def main():
    manifest=json.loads((HERE/'rtl_manifest.json').read_text())
    counts=Counter(); sequences=set();jobs=0
    with (HERE/'replay.jsonl').open(encoding='utf8') as audit:
        for shard in manifest['shards']:
            expected=[(seq,j) for seq in shard['sequences'] for j in seq['jobs']]
            n=0
            with (HERE/shard['file']).open(encoding='ascii') as mem:
                for line,(seq,meta) in itertools.zip_longest(mem,expected):
                    assert line is not None and seq is not None
                    raw=audit.readline();assert raw
                    row=json.loads(raw);d=pk.enc.inputs(row['input'])
                    assert row['scene']==seq['scene'] and row['source']==seq['source']
                    assert row['response']==meta['response'] and row['now']==meta['now'] and row['kind']==meta['kind']
                    assert len(line.strip())==12010
                    bits=int(line,16)
                    assert bool((bits>>48036)&1)==row['reset']
                    assert (bits>>3363)&((1<<44673)-1)==pk.enc.request(d)
                    assert (bits>>3325)&((1<<38)-1)==pk.enc.record(pk.g.pack_top_rsp(row['response']),38)
                    key=row['scene'],row['source']
                    if key not in sequences:
                        assert row['reset'];sequences.add(key);last=-1
                    else:assert not row['reset']
                    assert row['now']>=last;last=row['now']
                    counts[(row['source'],row['kind'],row['response']['reason'])]+=1
                    n+=1;jobs+=1
            assert n==shard['job_count']
            assert hashlib.sha256((HERE/shard['file']).read_bytes()).hexdigest()==shard['sha256']
        assert not audit.readline()
    assert jobs==manifest['total_jobs']
    result=dict(passed=True,jobs=jobs,nonempty_scene_source_sequences=len(sequences),all_request_bits_and_responses_match_audit=True,resets_only_at_scene_source_start=True,continuous_monotonic_times=True,scope='artifact integrity; no independent golden or RTL execution',counts={'/'.join(k):v for k,v in counts.items()})
    (HERE/'artifact_checks.json').write_text(json.dumps(result,indent=2))
    print(json.dumps(result),flush=True)

if __name__=='__main__':main()
