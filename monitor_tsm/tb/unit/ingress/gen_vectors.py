"""B1 semantic-name conversion patterned after convert_R1_vectors.py.

Independent golden oracle, deterministic random/boundary and ordered rejection cases.
Run from any directory. All artifacts remain here; golden imports suppress bytecode.
"""
from pathlib import Path
import sys, json, random, hashlib, zlib, copy
from dataclasses import asdict, replace
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sys.path[:0]=[str(ROOT/'tsmx_hw/golden'),str(ROOT/'tsm2_pilot/vendor')]
from tsmx_golden import model as g

def pack(fields):
    word=0
    for v,w in fields: word=(word<<w)|(int(v)&((1<<w)-1))
    return word

def ego(d):return g.Ego(**d)
def plan(d):return g.Plan(**{**d,'snapshot':ego(d['snapshot'])})
def pkt(d):return None if d is None else g.Packet(plan(d['plan']),d['crc'],tuple(d['snapshot_ids']),d['schema'])
def state(d):return g.Ingress(**{**d,'signature':tuple(d['signature'])})
def unpad(data,bits):return int.from_bytes(data,'big')>>((-bits)%8)
def ing(s):return unpad(g.pack_ingress(s),332)

def fields_ego(d):return [(d[k],w) for k,w in zip(('t','x','v','a','lx','lv'),(32,64,32,32,64,32))]
def request(i):
    """Parser contract: typed/range guards precede wire narrowing (spec9.2).

    Out-of-wire values cannot wrap into the valid domain. Each maps to an
    out-of-domain representative; numeric-invalid types/s64 values use parse_ok.
    Malformed ID tuples map to incoherent IDs; no expected reason is consulted.
    """
    i=copy.deepcopy(i); p=i['pkt']; parse=1
    groups=[i['ego']]
    if p:groups.append(p['plan']['snapshot'])
    for d in groups:
        for k,v in list(d.items()):
            if type(v) is not int or not -(1<<63)<v<(1<<63):parse=0;d[k]=0;continue
            if k=='t' and not 0<=v<=g.MASK: parse=0
            if k in ('v','lv','a') and not -(1<<31)<=v<(1<<31):d[k]=0x7fffffff
    if p:
        d=p['plan']
        for k in ('seq','generated','apply','x','v','a','tail','compute','count','schema'):
            v=d[k]
            if type(v) is not int or not -(1<<63)<v<(1<<63):parse=0;d[k]=0
        for k in ('seq','generated','apply'):
            if not 0<=d[k]<=g.MASK:parse=0
        for k in ('v','a'):
            if not -(1<<31)<=d[k]<(1<<31):d[k]=0x7fffffff
        for k,valid,representative in [('tail',0<=d['tail']<16,255),('count',2<=d['count']<=32,255),('compute',0<=d['compute']<=10000,0xffffffff),('schema',d['schema']==1,0)]:
            if not valid:d[k]=representative
        if p['schema']!=1:p['schema']=0
        ids=p['snapshot_ids']
        if len(ids)!=3 or any(type(v) is not int or not 0<=v<=g.MASK for v in ids):p['snapshot_ids']=[0,1,0]
        pf=([(d['seq'],32),(pack(fields_ego(d['snapshot'])),256)]+
            [(d[k],w) for k,w in zip(('generated','apply','x','v','a','tail','compute','count','schema'),(32,32,64,32,32,8,32,8,32))])
        local=zlib.crc32(g.pack_packet_body(plan(i['pkt']['plan']),i['pkt']['snapshot_ids'],i['pkt']['schema']))
        pw=pack([(1,1),(pack(pf),560),(p['crc'],32)]+[(v,32) for v in p['snapshot_ids']]+[(p['schema'],32)])
    else:pw=local=0
    return pack([(ing(state(i.get('state',asdict(g.Ingress())))),332),(i['now'],32),
                 (pack(fields_ego(i['ego'])),256),(pw,721),(local,32),(parse,1)])

def fixture_rows():
    meta=json.loads((ROOT/'tsmx_hw/vectors/b1.json').read_text())
    raw=(ROOT/'tsmx_hw/vectors/b1.hex').read_bytes()
    assert hashlib.sha256(raw).hexdigest()==meta['sha256']
    rows=[json.loads(x) for x in (ROOT/'tsmx_hw/vectors/b1.ports.jsonl').read_text().splitlines()]
    assert len(rows)==meta['n']
    fields={f['name']:f for f in meta['fields']}
    for row,word in zip(rows,map(lambda x:int(x,16),raw.splitlines())):
        o=row['output']
        for key,val in [('accept',int(o['reason']=='ok')),('reason_crc32',zlib.crc32(o['reason'].encode())),('output_digest',int(g.digest(o['state']),16))]:
            f=fields[key];assert (word>>f['lsb'])&((1<<f['bits'])-1)==val,(row['index'],key)
    return rows

def base(now=1000000):
    e=g.Ego(now,0,1000000,0,30000000,0)
    p=g.Plan(42,e,now,(now+100000)&g.MASK,100000,1000000,0)
    return dict(state=asdict(g.Ingress()),now=now,ego=asdict(e),pkt=asdict(g.packet(p)))

def reseal(i):
    if i['pkt']:
        p=i['pkt'];p['crc']=zlib.crc32(g.pack_packet_body(plan(p['plan']),p['snapshot_ids'],p['schema']))

def main():
    rows=[]; names=[];counts={};sources={}
    def add(i,name,expected=None):
        s,why=g.b1_ingress(state(i.get('state',asdict(g.Ingress()))),i['now'],ego(i['ego']),pkt(i['pkt']))
        result=json.loads(json.dumps(dict(state=asdict(s),reason=why)))
        if expected:
            for k,v in expected.items():assert result[k]==v,(name,k,result[k],v)
        req=request(i);rsp=(ing(s)<<8)|g.REASONS.index(why)
        rows.append((req<<340)|rsp);names.append(name);counts[why]=counts.get(why,0)+1
    for r in fixture_rows():add(r['input'],f"golden_{r['index']}",r['output'])
    golden=len(rows);diagnostics=0
    for r in map(json.loads,(ROOT/'tsmx_hw/vectors/edges.ports.jsonl').read_text().splitlines()):
        if r['block']!='b1':continue
        if 'bytes_hex' in r['input']:
            assert zlib.crc32(bytes.fromhex(r['input']['bytes_hex']))==r['output']['crc'];diagnostics+=1;continue
        add(r['input'],r['name'],r['output'])
    edges=len(rows)-golden
    # Every ordered reason, exact boundary, wrap, numeric and schema envelope.
    for group in ('ego','snapshot','plan'):
        fields={'x':[-(1<<63),-(1<<63)+1,-10000000001,-10000000000,10000000000,10000000001,(1<<63)-1],
                'v':[-(1<<31),-1,0,10000000,10000001,(1<<31)-1],
                'a':[-(1<<31),-8000001,-8000000,-1,0,1,1999999,2000000,2000001,(1<<31)-1]}
        if group!='plan':fields.update(lx=fields['x'],lv=fields['v'])
        else:fields.update(tail=[-1,0,15,16,255,256],count=[-1,0,1,2,32,33,255,256],compute=[-1,0,10000,10001,(1<<31)-1],schema=[0,1,2,g.MASK])
        for k,values in fields.items():
            for val in values:
                i=base();d=i['ego'] if group=='ego' else i['pkt']['plan']['snapshot'] if group=='snapshot' else i['pkt']['plan'];d[k]=val
                reseal(i);add(i,f'{group}_{k}_{val}')
    for now in (0,1,0x7fffffff,0x80000000,0xffffffff,1000000):
        for age in (-300001,-150001,-1,0,1,150000,150001,299999,300000,300001,0x7fffffff,0x80000000):
            for target in ('ego','snapshot','generated','last_time','last_sample','seq'):
                i=base(now);p=i['pkt']['plan'];v=(now-age)&g.MASK
                if target=='ego':i['ego']['t']=v
                elif target=='snapshot':p['snapshot']['t']=v
                elif target=='generated':p['generated']=v
                elif target=='last_time':i['state']['last_time']=v
                elif target=='last_sample':i['state']['last_sample']=v;i['pkt']=None
                else:i['state']['seq']=(42-age)&g.MASK
                reseal(i);add(i,f'serial_{now}_{age}_{target}')
    for age in (299999,300000,300001,0xffffffff,0x80000000):
        for move in (-200001,-200000,-199999,0,199999,200000,200001):
            i=base();p=i['pkt']['plan'];i['state'].update(signature=[p[k] for k in ('x','v','a','tail')],freeze_since=(i['now']-age)&g.MASK,freeze_x=-move)
            add(i,f'freeze_{age}_{move}')
    # Walk persistent proposals to check signature epoch and last_sample across calls.
    s=g.Ingress()
    for n in range(12):
        i=base(1000000+n*100000);i['state']=asdict(s);i['pkt']['plan']['seq']=n
        i['ego']['x']=n*100001;reseal(i);add(i,f'history_{n}')
        s,why=g.b1_ingress(s,i['now'],ego(i['ego']),pkt(i['pkt']))
    rng=random.Random(0xB10008)
    for n in range(2400):
        i=base(rng.randrange(1<<32));p=i['pkt']['plan'];e=i['ego']
        for d in (e,p['snapshot']):
            d.update(x=rng.randint(-10000000000,10000000000),lx=rng.randint(-10000000000,10000000000),v=rng.randrange(10000001),lv=rng.randrange(10000001),a=-rng.randrange(8000001))
        p.update(seq=rng.randrange(1<<32),x=rng.randint(-10000000000,10000000000),v=rng.randrange(10000001),a=-rng.randrange(8000001),tail=rng.randrange(16),count=rng.randint(2,32),compute=rng.randrange(10001))
        tag=n%18
        if tag==0:i['state']['last_time']=(i['now']+1)&g.MASK;i['pkt']=None
        elif tag==1:i['pkt']=None
        elif tag==2:i['pkt']=None;i['state']['last_sample']=(i['now']-300000)&g.MASK
        elif tag==3:e['x']=g.NAN
        elif tag==4:e['v']=10000001
        elif tag==5:p['snapshot']['a']=1
        elif tag==6:p['schema']=2
        elif tag==7:p['count']=rng.choice([0,1,33,255,256])
        elif tag==8:p['compute']=10001
        elif tag==9:i['pkt']['snapshot_ids']=[0,1,0]
        elif tag==10:i['state']['seq']=p['seq']
        elif tag==11:e['t']=(i['now']-150001)&g.MASK
        elif tag==12:p['snapshot']['t']=(i['now']+1)&g.MASK
        elif tag==13:p['generated']=(i['now']+1)&g.MASK
        elif tag==14:i['state'].update(signature=[p[k] for k in ('x','v','a','tail')],freeze_since=(i['now']-300000)&g.MASK,freeze_x=e['x']-200001)
        reseal(i)
        if tag==15:i['pkt']['crc']^=1
        add(i,f'random_{n}')
    assert set(counts)==set(g.REASONS[:14]),counts
    for name in ('b1.hex','b1.json','b1.ports.jsonl','edges.ports.jsonl'):
        sources[name]=hashlib.sha256((ROOT/'tsmx_hw/vectors'/name).read_bytes()).hexdigest()
    (HERE/'vectors.mem').write_text(''.join(f'{r:0429x}\n' for r in rows))
    (HERE/'vectors_meta.svh').write_text(f'localparam integer N={len(rows)}, GOLDEN={golden}, EDGES={edges}, EXTRA={len(rows)-golden-edges};\n')
    (HERE/'vectors.json').write_text(json.dumps(dict(total=len(rows),golden=golden,edges=edges,extra=len(rows)-golden-edges,diagnostic_crc=diagnostics,reasons=counts,seed=0xB10008,sources=sources,names=names),indent=2)+'\n')
    print('VECTORS',len(rows),'golden',golden,'edges',edges,'extra',len(rows)-golden-edges,counts)

if __name__=='__main__':main()

