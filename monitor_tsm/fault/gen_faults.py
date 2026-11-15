"""Registered stratified bit population; no simulator or golden imports."""
import json, random, re, hashlib
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SEED = 20261105

def dump(name, value):
    (HERE/name).write_text(json.dumps(value, indent=2)+'\n')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def instances():
    e='dut.u_tsmx_engine'
    out=[('engine','top/m_tsmx_engine',e),
         ('cert','cert/m_tsmx_cert',e+'.u_b9'),
         ('selection','sel/m_tsmx_sel',e+'.u_b7'),
         ('ingress','ingress/m_tsmx_ingress',e+'.u_b1'),
         ('supervisor','supervisor/m_tsmx_supervisor',e+'.u_b8'),
         ('codec','codec/m_tsmx_codec_core',e+'.u_tsmx_hash.u_codec.u_codec_core'),
         ('health','health/m_tsmx_health',e+'.u_health.u_tsmx_health'),
         ('health','health/m_tsmx_health_bist',e+'.u_health.u_tsmx_health_bist')]
    mrms=[]; geoms=[]
    for sw,lanes in [(0,2),(1,1)]:
        s=e+f'.u_tsmx_sweep_{sw}'
        out.append(('sweep','top/m_tsmx_sweep',s))
        for lane in range(lanes):
            mrms.append(s+f'.gen_mrm[{lane}].u_tsmx_mrmgen')
            geoms.append(s+f'.gen_geom[{lane}].u_tsmx_geom')
    b=e+'.u_health.u_tsmx_health_bist'
    mrms.append(b+'.u_tsmx_mrmgen'); geoms.append(b+'.u_tsmx_geom')
    out += [('mrmgen','mrmgen/m_tsmx_mrmgen',p) for p in mrms]
    out += [('geom','geom/m_tsmx_geom',p) for p in geoms]
    out += [('geom_su','geom/m_tsmx_geom_su',p+f'.gen_su[{i}].u_geom_su') for p in geoms for i in range(4)]
    arith=[p+'.u_tsmx_arith' for p in mrms]
    arith += [e+'.u_tsmx_math.u_arith',e+'.u_b1.u_tsmx_arith',e+'.u_b9.u_arith']
    out += [('arith','arith/m_tsmx_arith',p) for p in arith]
    return out

def registers(file):
    s=file.read_text()
    # Strip comments while preserving line locations.
    s=re.sub(r'/\*.*?\*/',lambda m:'\n'*m[0].count('\n'),s,flags=re.S)
    s=re.sub(r'//[^\n]*','',s)
    enums={m[2]:int(m[1])+1 for m in re.finditer(r'typedef\s+enum\s+logic\s*\[(\d+):0\].*?}\s*(\w+)\s*;',s,re.S)}
    const={'PARA_MAX_OBJ':32,'LPARA_NT':13}
    out=[]
    pattern=r'\b(logic|'+ '|'.join(enums)+r')\s*(\[[^\]]+\])?\s*([^;]+);'
    for m in re.finditer(pattern,s):
        typ,width,decl=m.groups()
        if typ=='logic':
            if width:
                expr=width[1:-1].split(':')[0]
                for k,v in const.items(): expr=expr.replace(k,str(v))
                if not re.fullmatch(r'[\d\s+*()-]+',expr):
                    if 'reg_' in decl: raise ValueError((file,expr,decl))
                    continue
                n=eval(expr,{'__builtins__':{}})+1
            else: n=1
        else: n=enums[typ]
        for item in decl.split(','):
            name=item.strip()
            if not re.fullmatch(r'reg_\w+',name): continue # explicitly exclude unpacked RAM
            if not re.search(r'\b'+name+r'(?:\[[^;]*?\])?\s*<=',s): continue
            out.append(dict(reg=name,width=n,scalar=typ=='logic' and not width,line=s[:m.start()].count('\n')+1))
    return out

def main():
    inventory=[]
    for unit,src,path in instances():
        file=ROOT/'rtl'/(src+'.sv')
        for r in registers(file):
            inventory.append(dict(unit=unit,path=path+'.'+r['reg'],source='rtl/'+src+'.sv',**r))
    units=sorted({r['unit'] for r in inventory})
    dump('inventory.json',dict(seed=SEED,registers=inventory,population={u:sum(r['width'] for r in inventory if r['unit']==u) for u in units}))
    jobs=[]
    for fn in ['reg300_board.mem','apos.mem']:
        file=ROOT/'tb/integ'/fn; rows=file.read_text().splitlines()
        for accept in [1,0]:
            for row,s in enumerate(rows):
                x=int(s,16); rsp=(x>>3325)&((1<<38)-1)
                if x>>48036==1 and rsp>>37==accept:
                    name=f'job{len(jobs)}.mem'; (HERE/name).write_text(s+'\n')
                    jobs.append(dict(id=len(jobs),file=name,source='tb/integ/'+fn,row=row,accept=accept,source_sha256=sha(file)))
                    break
            else: raise ValueError('No reset-start job '+fn)
    dump('workload.json',jobs)
    rng=random.Random(SEED); faults=[]
    for i in range(1440):
        unit=units[i%len(units)]; regs=[r for r in inventory if r['unit']==unit]
        bit=rng.randrange(sum(r['width'] for r in regs))
        for r in regs:
            if bit<r['width']: break
            bit-=r['width']
        faults.append(dict(id=i,unit=unit,path=r['path'],bit=bit,scalar=r['scalar'],source=r['source'],line=r['line'],job=rng.randrange(len(jobs)),cycle_seed=rng.getrandbits(32)))
    dump('faults.json',faults)
    print(json.dumps(dict(population={u:sum(r['width'] for r in inventory if r['unit']==u) for u in units},jobs=jobs),indent=2))

if __name__=='__main__': main()
