"""Validate and package the completed replay, without dataset reload or writes elsewhere."""
import sys
sys.dont_write_bytecode = True
import run_w7c as a
import json
import time
from collections import Counter


def main():
    started = time.monotonic()
    r = json.loads((a.OUT/'results.json').read_text(encoding='utf-8'))
    with (a.OUT/'accepted.jsonl').open(encoding='utf-8') as f:
        rows = [json.loads(line) for line in f]
    assert len({(x['token'],x['plan'],x['variant']) for x in rows}) == len(rows)
    for x in rows:
        assert x['cid_g']%4!=3
        check=x['o2_selected']
        if x['o2_library_label']=='UNSAFE':
            assert check['label']=='UNSAFE'
        if x['old_oracle_label']=='UNSAFE':
            assert x['old_selected']['label']=='UNSAFE'
            assert x['old_selected_attribution'] is not None
        if check['label'] in ('SAFE','UNSAFE'):
            assert (check['margin_m']>=0)==(check['label']=='SAFE')
            assert check['culprit'] is not None or check['relevant_objects']==0
        if x['attribution'] is not None:
            c=x['attribution']
            if c['in_golden_input']:
                reconstructed=abs(c['gt_x_m']-c['ego_x_m'])-c['gt_half_length_m']-.5
                assert abs(reconstructed-check['margin_m'])<1e-8
                assert abs(c['gt_x_m']-c['golden_cv_x_m']-c['gt_minus_golden_cv_m'])<1e-8
        for field in ('cv_replay','original_plan_cv_replay'):
            if x[field]['margin_m'] is not None and x[field]['margin_m'] < -a.TOL:
                assert any((v['token'],v['plan'],v['variant'])==(x['token'],x['plan'],x['variant']) for v in r['cv_violations'])
    r['accepted_candidate_audits']=rows
    r['config']['empty_world_margin']='10000 m is the inherited oracle/golden sentinel for an empty object set, not a measured physical clearance.'
    r['distribution_units']='metres; empirical numpy percentiles; counts are variant/plan acceptances (same frame may occur in both variants).'
    for key,entry in r['classifications'].items():
        variant,plan=key.split('/')
        group=[x for x in rows if x['variant']==variant and x['plan']==plan]
        oldgroup=[dict(x,o2_selected=x['old_selected'],attribution=x['old_selected_attribution']) for x in group if x['old_oracle_label']=='UNSAFE']
        entry['old_false_accepts_using_old_selected']=a.summary(oldgroup,lambda x:True)
        entry['by_cause_and_period']={}
        for cause in ('a_not_in_input_A5','b_in_input_GT_deviates','c_footprint_lateral_convention','d_other_UNRESOLVED'):
            for hold in (False,True):
                subset=[x for x in group if x['attribution'] is not None and x['attribution']['cause']==cause and x['attribution']['during_hold']==hold]
                d=a.summary(subset,lambda x:True)
                d['abs_GT_minus_original_CV_m']=a.distribution([abs(x['attribution']['gt_minus_original_cv_m']) for x in subset if x['attribution'].get('gt_minus_original_cv_m') is not None])
                entry['by_cause_and_period'][cause+'/'+('hold' if hold else 'before_hold')]=d
    unresolved=r['original_float_profile_unresolved']
    assert all(x['state_si'][1]<0 and x['encoded_state_si'][1]==0 for x in unresolved)
    r['original_float_profile_explanation']='Every original-profile UNKNOWN has a negative original velocity rounded to zero in the accepted fixed-point state. Its original O2 minimum remains UNRESOLVED; exact encoded-state CV replay is included.'
    r['validation'].update(unique_accepted_records=True,library_UNSAFE_implies_selected_UNSAFE=True,
                           old_UNSAFE_implies_old_selected_UNSAFE=True,culprit_margin_reconstruction=True,
                           every_CV_negative_listed=True,all_original_UNKNOWN_due_to_negative_speed_rounding=True,
                           analytic_checks=json.loads((a.OUT/'analytic_checks.json').read_text()),
                           accepted_jsonl_sha256=a.w.sha(a.OUT/'accepted.jsonl'))
    r['sha256']['finalize_w7c.py']=a.w.sha(__file__)
    r['runtime_successful_replay_seconds']=r['runtime_wall_seconds']
    r['runtime_earlier_failed_attempt_seconds']='UNRESOLVED: not persistently timed; initial attempt stopped at a negative-float-speed/encoded-zero edge case.'
    r['runtime_final_validation_seconds']=time.monotonic()-started
    r['runtime_wall_seconds']=r['runtime_successful_replay_seconds']+r['runtime_final_validation_seconds']
    a.report(r)
    report=a.OUT/'W7C_REPORT.md'
    lines=report.read_text(encoding='utf-8').splitlines()
    lines=[line.replace(':278 (old oracle)',':270 (old oracle)') for line in lines]
    lines=[line+' Empty-object margins use the inherited 10000 m sentinel.' if line.startswith('CV:') else line for line in lines]
    inserted=[]
    for variant in ('V0','VA'):
        counts=Counter()
        for x in r['old_false_accepts']:
            if x['variant']==variant:
                c=x['old_selected_attribution']
                counts[c['cause']+'/'+('hold' if c['during_hold'] else 'before_hold')]+=1
        inserted.append('Old FA '+variant+' (old-selected minimiser): '+json.dumps(dict(counts),sort_keys=True)+'. O2-selected attribution is separately stored per case.')
    inserted.append(f"Original-float UNKNOWN cases: {len(unresolved)}; all have negative speed rounding to encoded zero. Their original O2 minima are UNRESOLVED; encoded CV results are explicit.")
    inserted.append('Audit code: run_w7c.py:55 (CV), :71 (selected O2), :80 (attribution), :128 (distributions); finalize_w7c.py:10 (independent record checks).')
    inserted.append('All audits: results.json:accepted_candidate_audits. Runtime sums completed-prefix elapsed + parallel-suffix wall + validation; restart gap/discarded work/serialization excluded. Failed-attempt duration UNRESOLVED.')
    lines[-1] += ' Then `python -B tsmx_hw/eval_nuscenes/w7c/finalize_w7c.py` for full packaging/validation.'
    lines[-1:-1]=inserted
    assert len(lines)<=40,len(lines)
    report.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    r['report_lines']=len(lines)
    r['sha256']['W7C_REPORT.md']=a.w.sha(report)
    a.dump(a.OUT/'results.json',r)
    print(json.dumps(dict(accepted=len(rows),cv_violations=len(r['cv_violations']),original_UNKNOWN=len(unresolved),report_lines=len(lines),runtime_s=r['runtime_wall_seconds'])))


if __name__=='__main__':
    main()
