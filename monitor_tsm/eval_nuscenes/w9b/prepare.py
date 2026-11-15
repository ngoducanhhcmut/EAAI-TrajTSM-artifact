"""Read-only source extraction; all cache writes stay beside this script."""
import sys, os, json, pickle, shutil, time
from pathlib import Path
sys.dont_write_bytecode=True
from packetizer import HERE,HW
sys.path.insert(0,str(HW/'eval_nuscenes'))
import run_w7 as w7
import numpy as np

def main():
    start=time.time()
    free=shutil.disk_usage('C:/').free
    assert free>=10*2**30,free
    base=HW.parents[1]
    data=base/'eval/data/nuscenes/v1.0-trainval'
    ds=np.load(base/'sw/eval_trainval/out/dataset.npz')
    pred=np.load(base/'sw/eval_trainval/out/pred_hw_new.npy')
    scenes=set(ds['scene'].tolist())
    samples=json.loads((data/'sample.json').read_text())
    scene_table=json.loads((data/'scene.json').read_text())
    st={r['token']:r['name'] for r in scene_table}
    selected={r['token']:r for r in samples if st[r['scene_token']] in scenes}
    print('select',len(scenes),len(selected),'free GiB',free/2**30,flush=True)
    sweeps=[]
    for r in w7.stream_array(data/'sample_data.json'):
        if r['sample_token'] in selected and 'LIDAR_TOP' in r['filename']:
            sweeps.append(r)
    wanted={r['ego_pose_token'] for r in sweeps}
    poses={r['token']:r for r in w7.stream_array(data/'ego_pose.json') if r['token'] in wanted}
    per_scene={s:[] for s in scenes}
    keyposes={}
    for r in sweeps:
        sc=st[selected[r['sample_token']]['scene_token']]
        per_scene[sc].append(poses[r['ego_pose_token']])
        if r['is_key_frame']:keyposes[r['sample_token']]=poses[r['ego_pose_token']]
    frames=[]
    with (HW/'eval_nuscenes/results/frames.jsonl').open(encoding='utf8') as f:
        for line in f:
            r=json.loads(line)
            if r['scene'] in scenes:frames.append(r)
    # All 0103 annotations support W7 objects_at even when its ODD filter failed.
    board_tokens={k for k,s in selected.items() if st[s['scene_token']]=='scene-0103'}
    cats=pickle.loads((HW/'eval_nuscenes/annotation_categories.pkl').read_bytes())
    anns={}
    for r in w7.stream_array(data/'sample_annotation.json'):
        if r['sample_token'] in board_tokens:
            r['category_name']=cats[r['token']];anns[r['token']]=r
    plans={str(t):pred[i] for i,t in enumerate(ds['token']) if np.isfinite(pred[i]).all()}
    cache=dict(scenes=sorted(scenes),samples=selected,scene_names=st,keyposes=keyposes,
               sweeps=per_scene,frames=frames,plans=plans,board_anns=anns,
               free_bytes_start=free,prepare_seconds=time.time()-start)
    with (HERE/'inputs.pkl').open('wb') as f:pickle.dump(cache,f,protocol=4)
    print('prepared',len(frames),len(plans),'seconds',time.time()-start,flush=True)
if __name__=='__main__':main()
