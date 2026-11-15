"""Bound each invocation by the existing 3151-vector binary capacity.

Every batch contains complete H/T scene pairs. The eight canonical shard files
remain complete; batching never cuts a retained-state sequence.
"""
import json, hashlib
from pathlib import Path
HERE=Path(__file__).resolve().parent

def main():
    manifest=json.loads((HERE/'rtl_manifest.json').read_text())
    folder=HERE/'rtl_batches';folder.mkdir(exist_ok=True)
    result=[]
    for shard in manifest['shards']:
        sequences=shard['sequences'];groups=[];group=[];count=0
        for scene in shard['scenes']:
            pair=[s for s in sequences if s['scene']==scene]
            size=sum(s['job_count'] for s in pair)
            assert size<=3151,('scene exceeds binary capacity',scene,size)
            if count+size>3151:groups.append((group,count));group=[];count=0
            group.extend(pair);count+=size
        if group:groups.append((group,count))
        offset=0
        with (HERE/shard['file']).open('rb') as src:
            for b,(seqs,count) in enumerate(groups):
                path=folder/f"shard_{shard['shard']}_batch_{b}.mem"
                with path.open('wb') as out:
                    for _ in range(count):
                        line=src.readline();assert len(line.strip())==12010;out.write(line)
                result.append(dict(shard=shard['shard'],batch=b,start_job=offset,job_count=count,file=path.relative_to(HERE).as_posix(),scenes=list(dict.fromkeys(s['scene'] for s in seqs)),sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
                offset+=count
            assert not src.read(1)
        assert offset==shard['job_count']
    (HERE/'rtl_batches.json').write_text(json.dumps(dict(binary_capacity=3151,batches=result),indent=2))
    (HERE/'rtl_batches.tsv').write_text(''.join(f"{b['shard']}\t{b['batch']}\t{b['start_job']}\t{b['job_count']}\t{b['file']}\n" for b in result))

if __name__=='__main__':main()
