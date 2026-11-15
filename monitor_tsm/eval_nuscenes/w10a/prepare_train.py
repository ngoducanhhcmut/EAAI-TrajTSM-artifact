"""Extract only first 150 official training scenes; never write source data."""
import sys, os, json, pickle, time, shutil
from pathlib import Path
sys.dont_write_bytecode=True
from packetizer_v2 import HERE, HW
sys.path.insert(0,str(HW/'eval_nuscenes'))
import run_w7 as w7
os.environ['TEMP']=os.environ['TMP']=str(HERE)
import numpy as np

def main():
    start=time.time(); free=shutil.disk_usage('C:/').free
    assert free>=10*2**30,free
    base=HW.parents[1]; root=base/'eval/data/nuscenes/v1.0-trainval'
    ds=np.load(base/'sw/eval_trainval/out/train_dataset.npz')
    pred=np.load(base/'sw/eval_trainval/out/train_pred_hw_new.npy')
    from nuscenes.utils.splits import create_splits_scenes
    scenes=sorted(create_splits_scenes()['train'])[:150]
    table=json.loads((root/'scene.json').read_text()); st={s['token']:s['name'] for s in table}
    samples={s['token']:s for s in json.loads((root/'sample.json').read_text()) if st[s['scene_token']] in scenes}
    sweeps=[s for s in w7.stream_array(root/'sample_data.json') if s['sample_token'] in samples and 'LIDAR_TOP' in s['filename']]
    wanted={s['ego_pose_token'] for s in sweeps}
    poses={s['token']:s for s in w7.stream_array(root/'ego_pose.json') if s['token'] in wanted}
    per={s:[] for s in scenes}; keys={}; sd={}
    for s in sweeps:
        per[st[samples[s['sample_token']]['scene_token']]].append(poses[s['ego_pose_token']])
        if s['is_key_frame']:
            keys[s['sample_token']]=poses[s['ego_pose_token']];sd[s['token']]=s
            samples[s['sample_token']]['data']={'LIDAR_TOP':s['token']}
    cats=pickle.loads((HW/'eval_nuscenes/annotation_categories.pkl').read_bytes())
    anns={}
    for a in w7.stream_array(root/'sample_annotation.json'):
        if a['sample_token'] in samples:
            a['category_name']=cats[a['token']];anns[a['token']]=a
    for s in samples.values():s['anns']=[]
    for k,a in anns.items():samples[a['sample_token']]['anns'].append(k)
    tables={'sample':samples,'sample_annotation':anns,'sample_data':sd,'ego_pose':poses}
    class Nusc:
        def get(self,t,k):return tables[t][k]
    nusc=Nusc(); plans={str(t):pred[i] for i,t in enumerate(ds['token']) if ds['scene'][i] in scenes and ds['keep'][i] and np.isfinite(pred[i]).all()}
    frames=[]
    for sc in table:
        if sc['name'] not in scenes:continue
        data=w7.scene_data(nusc,sc); ss,pp,tt,aa,vv,ac=data
        for i in range(len(ss)-6):
            s=ss[i]; r=dict(scene=sc['name'],token=s['token'],timestamp=s['timestamp'],odd=False)
            frames.append(r)
            if i==0 or s['token'] not in plans:continue
            axis=np.array([np.cos(aa[i]),np.sin(aa[i])]); side=np.array([-axis[1],axis[0]])
            v,a=float(vv[i]@axis),float(ac[i]@axis)
            lat=float(np.max(np.abs((pp[i:i+7]-pp[i])@side)))
            heading=float(np.max(np.abs(np.arctan2(np.sin(aa[i:i+7]-aa[i]),np.cos(aa[i:i+7]-aa[i]))))*180/np.pi)
            if not (0<=v<=10 and -8<=a<=2 and lat<=1 and heading<=10):continue
            objects,errors=w7.objects_at(nusc,s,pp[i],axis,side)
            r.update(odd=True,objects=objects,adapter_errors=errors)
    velocities={}; ages=[]
    for k,a in anns.items():
        prev=anns.get(a['prev']);vector=age=None
        if prev:
            age=samples[a['sample_token']]['timestamp']-samples[prev['sample_token']]['timestamp']
            if age>0:vector=(np.array(a['translation'][:2])-prev['translation'][:2])/(age*1e-6);ages.append(age)
        velocities[k]=(vector,age)
    cache=dict(scenes=scenes,samples=samples,scene_names=st,keyposes=keys,sweeps=per,frames=frames,plans=plans,causal_velocities=velocities)
    with (HERE/'train_inputs.pkl').open('wb') as f:pickle.dump(cache,f,protocol=4)
    info=dict(scenes=scenes,eligible_frames=len(frames),available_prediction_tokens=len(plans),odd_prediction_tokens=sum(r['odd'] for r in frames),seconds=time.time()-start,free_bytes_start=free)
    (HERE/'training_extraction.json').write_text(json.dumps(info,indent=2))
    print(json.dumps(info),flush=True)
if __name__=='__main__':main()
