"""Post hoc hold-only counterfactual with O2 candidate relevance fixed."""
import sys
sys.dont_write_bytecode=True
import json
import math
import pickle
from collections import defaultdict
import numpy as np
import run_w7b as b

def main():
    paths=sorted(b.OUT.glob('plans_*.jsonl'))
    rows={}
    todo=defaultdict(list)
    for path in paths:
        with path.open(encoding='utf-8') as f:
            rows[path]=list(map(json.loads,f))
        for r in rows[path]:
            if r['old']=='SAFE' and r['o2']['label']=='UNSAFE':
                if any(p['entering_objects'] for p in r['o2']['profiles']):
                    todo[r['scene']].append(r)
                else:
                    r['stop_only_aligned_relevance']=r['stop_only']
    corrected=0
    checked=0
    if todo:
        from data.nuscenes_lite import load_nuscenes
        root=json.loads((b.HERE/'results/manifest.json').read_text())['dataset']
        nusc=load_nuscenes('v1.0-trainval',root)
        with (b.HERE/'annotation_categories.pkl').open('rb') as f:
            cats=pickle.load(f)
        source={}
        tokens={r['token'] for lst in todo.values() for r in lst}
        with (b.HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
            for r in map(json.loads,f):
                if r['token'] in tokens:
                    source[r['token']]=r
        scenes={s['name']:s for s in nusc.scene}
        for name,lst in todo.items():
            b.roots.clear()
            samples,pp,tt,aa,tracks=b.scene_tracks(nusc,scenes[name],cats)
            indices={s['token']:i for i,s in enumerate(samples)}
            for r in lst:
                original=source[r['token']]
                i=indices[r['token']]
                axis=np.array([math.cos(aa[i]),math.sin(aa[i])])
                objects=b.projected(tracks,pp[i],axis,np.array([-axis[1],axis[0]]),tt[i],{o['token']:o for o in original['objects']})
                counter=b.oracle2(original['plans'][r['plan']]['state_si'],objects,float(tt[-1]-tt[i]),False,True)
                assert counter['label'] in ('SAFE','UNSAFE')
                r['stop_only_aligned_relevance']=counter['label']
                checked+=1
                corrected+=r['stop_only']!=counter['label']
    for path,lst in rows.items():
        tmp=path.with_suffix('.hold.tmp')
        with tmp.open('w',encoding='utf-8') as f:
            for r in lst:
                f.write(json.dumps(r,allow_nan=False)+'\n')
        tmp.replace(path)
    b.dump(b.OUT/'hold_validation.json',dict(status='PASS',entrant_cases_rechecked=checked,
        labels_changed_by_fixing_relevance=corrected,
        method='Remove hold while keeping each candidate full-horizon O2 relevance set fixed; no-entrant cases reuse stop-only result.'))
    print('Hold relevance audit:',checked,'entrant cases;',corrected,'changed labels',flush=True)

if __name__=='__main__':
    main()
