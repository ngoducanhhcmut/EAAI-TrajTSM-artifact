"""Add causal annotation velocities and board annotation indices to inputs.pkl."""
import sys,pickle,time
import numpy as np
from packetizer import HERE,HW
sys.path.insert(0,str(HW/'eval_nuscenes'))
import run_w7 as w7
def main():
    start=time.time();c=pickle.loads((HERE/'inputs.pkl').read_bytes())
    data=HW.parents[1]/'eval/data/nuscenes/v1.0-trainval/sample_annotation.json'
    annotations={}
    for a in w7.stream_array(data):
        if a['sample_token'] in c['samples']:
            annotations[a['token']]={k:a[k] for k in ('translation','prev','sample_token')}
    velocities={};ages=[]
    for token,a in annotations.items():
        prev=annotations.get(a['prev']);v=None;age=None
        if prev:
            t=c['samples'][a['sample_token']]['timestamp'];tp=c['samples'][prev['sample_token']]['timestamp']
            if t>tp:
                age=t-tp
                v=(np.array(a['translation'][:2])-prev['translation'][:2])/(age*1e-6)
                ages.append(age)
        velocities[token]=(v,age)
    for s in c['samples'].values():s['anns']=[]
    for token,a in c['board_anns'].items():c['samples'][a['sample_token']]['anns'].append(token)
    c['causal_velocities']=velocities
    c['annotation_velocity_chain_us']=dict(min=min(ages),max=max(ages),mean=float(np.mean(ages)))
    c['augment_seconds']=time.time()-start
    with (HERE/'inputs.pkl').open('wb') as f:pickle.dump(c,f,protocol=4)
    print('augment',len(velocities),c['annotation_velocity_chain_us'],flush=True)
if __name__=='__main__':main()
