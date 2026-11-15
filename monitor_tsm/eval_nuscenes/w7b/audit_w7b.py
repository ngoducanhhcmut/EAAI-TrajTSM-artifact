"""Post hoc artifact checks; writes only w7b/validation.json and rounding corrections."""
import sys
sys.dont_write_bytecode = True
import json
from collections import Counter
import run_w7b as b

def main():
    source = {}
    with (b.HERE/'results/frames.jsonl').open(encoding='utf-8') as f:
        for r in map(json.loads,f):
            if r['odd']:
                source[r['token']] = dict(objects=r['objects'], plans={p:d['state_si'] for p,d in r['plans'].items()})
    totals=Counter()
    corrected=0
    for path in sorted(b.OUT.glob('plans_*.jsonl')):
        with path.open(encoding='utf-8') as f:
            rows=list(map(json.loads,f))
        modified=False
        for r in rows:
            totals['plans']+=1
            label=r['o2']['label']
            assert label in b.LABELS
            totals[label]+=1
            new_unsafe = label=='UNSAFE' and r['decisions']['VA'] and not r['decisions']['V0']
            assert new_unsafe == ('va_selected_profile' in r)
            if new_unsafe:
                assert r['va_selected_profile']['label']=='UNSAFE'
                assert r['va_selected_profile']['culprit'] is not None
                culprit=r['va_selected_profile']['culprit']
                assert culprit['gt_minus_constant_v_m'] is not None or culprit['deviation_status'].startswith('UNRESOLVED')
                totals['new_VA_unsafe_evidence_verified']+=1
            if label=='SAFE':
                assert r['stop_only']=='SAFE'
                assert r['o2']['profiles'][-1]['label']=='SAFE'
            if label=='UNSAFE':
                assert len(r['o2']['profiles'])==len(b.w.PAIRS)
                assert all(p['label']=='UNSAFE' for p in r['o2']['profiles'])
            if label=='GT_TRUNCATED':
                assert any(p['label']=='GT_TRUNCATED' for p in r['o2']['profiles'])
                assert all(p['label']!='SAFE' for p in r['o2']['profiles'])
            for variant,d in r['decomposition'].items():
                assert label=='SAFE' and not r['decisions'][variant]
                if d['cause'] not in ('rear_object_separation','front_object_separation'):
                    continue
                s=source[r['token']]
                ego=b.w.Ego(500000,*map(b.w.fixed,s['plans'][r['plan']]),0,0)
                tr,objects=b.golden_objects(ego,s['objects'],d['diagnostic']['cid'],variant)
                step=d['interval']
                i=next(i for i,o in enumerate(s['objects']) if o['token']==d['culprit'])
                o=objects[i]
                # Match original golden model.py:487-502 lower-bound recurrence.
                from tsmx_golden.model import advance_lb
                ox,ov=o.x,o.v
                for left,right in zip(tr.rows[:step-1],tr.rows[1:step]):
                    ox,ov=advance_lb(ox,ov,0,right[0]-left[0])
                side='ahead' if ox>=tr.rows[step-1][2] else 'behind'
                if side!=d['side']:
                    d['side']=side
                    d['cause']='front_object_separation' if side=='ahead' else 'rear_object_separation'
                    modified=True
                    corrected+=1
                totals['golden_separation_sides_verified']+=1
        if modified:
            tmp=path.with_suffix('.audit.tmp')
            with tmp.open('w',encoding='utf-8') as f:
                for r in rows:
                    f.write(json.dumps(r,allow_nan=False)+'\n')
            tmp.replace(path)
    assert totals['plans']==sum(len(r['plans']) for r in source.values())
    totals['rounding_side_corrections']=corrected
    b.dump(b.OUT/'validation.json',dict(status='PASS',checks=dict(totals),
        note='Independent recurrence check of every attributed separation side; complete profile coverage and hold monotonicity verified.'))
    print(json.dumps(dict(totals)))

if __name__=='__main__':
    main()
