"""TSM-X / TSMX project / v0.1. Independent JSON/6.1 CSR bus reference.

No CSR golden function exists. Import the golden model's mode constants and convert
system fixtures by semantic field name, never by deriving behavior from design RTL.
"""
import sys,json,re,random,hashlib,zlib
from pathlib import Path
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.path.insert(0,str(ROOT/'golden'))
from tsmx_golden import model as g
REASONS=('ok clock_reset freeze_no_sample timeout numeric range_schema overflow deadline snapshot crc '
         'sequence ego_freshness freshness freeze range phase_alignment horizon trajectory lane_range '
         'object_overflow lane object_range object_speed_bound time separation binding replay '
         'context_binding lease_bound expiry_at_executor ack_timeout committed pending late_apply '
         'expiry no_pending splice ftti_budget geometry capability health reset no_backup ego_live bridge').split()
REGS=json.loads((ROOT/'spec/tsmx_csr.json').read_text())['registers']
def field_mask(f):
    b=list(map(int,re.findall(r'\d+',f['bits'])));return ((1<<(b[0]-b[-1]+1))-1)<<b[-1]
DEFAULT={int(r['offset'],0):sum(int(f['reset'],0)<<int(re.findall(r'\d+',f['bits'])[-1]) for f in r['fields']) for r in REGS}
RW={int(r['offset'],0):sum(field_mask(f) for f in r['fields'] if f['type']=='rw') for r in REGS}
INPUTS=[('rst',1),('awaddr',16),('awprot',3),('awvalid',1),('wdata',32),('wstrb',4),('wvalid',1),('bready',1),('araddr',16),('arprot',3),('arvalid',1),('rready',1),('sts_valid',1),('sts_data',115),('deposit',1)]
OUTPUTS=[('awready',1),('wready',1),('bvalid',1),('bresp',2),('arready',1),('rvalid',1),('rresp',2),('rdata',32),('config_data',4),('irq',1)]
class Reference:
    def __init__(self):self.reset()
    def reset(self):
        self.words=DEFAULT.copy();self.aw=None;self.w=None;self.b=None;self.r=None
        self.en=0;self.valid=0;self.wait=0;self.soft=0;self.start=0
    def outputs(self,rst):
        return dict(awready=int(rst and self.aw is None and self.b is None),wready=int(rst and self.w is None and self.b is None),
          bvalid=int(rst and self.b is not None),bresp=self.b if rst and self.b is not None else 0,
          arready=int(rst and self.r is None),rvalid=int(rst and self.r is not None),
          rresp=self.r[1] if rst and self.r else 0,rdata=self.r[0] if rst and self.r else 0,
          config_data=(self.valid<<3)|(self.en<<2)|(self.soft<<1)|self.start,irq=int(bool(self.words[8]&self.words[12])))
    def read(self,addr):
        if addr not in self.words:return 0,2
        if addr==0:return self.en,0
        if addr==76:return self.valid,0
        return self.words[addr],0
    def edge(self,i):
        if not i['rst']:self.reset();return self.outputs(0)
        if i['deposit']:
            for a in (16,20,24,28,32):self.words[a]=0xfffffffe
        pre=self.outputs(1);oldwords=self.words.copy();oldvalid=self.valid
        active=self.en or (oldwords[4]&1) or (i['sts_valid'] and (i['sts_data']>>76)&1)
        wr=self.aw is not None and self.w is not None and self.b is None
        addr=self.aw;word,strobe=self.w if self.w else (0,0)
        rd=self.read(i['araddr']) if pre['arready'] and i['arvalid'] else None
        self.soft=self.start=0
        if pre['bvalid'] and i['bready']:self.b=None
        if pre['rvalid'] and i['rready']:self.r=None
        if pre['awready'] and i['awvalid']:self.aw=i['awaddr']
        if pre['wready'] and i['wvalid']:self.w=(i['wdata'],i['wstrb'])
        if rd is not None:self.r=rd
        def sat(a):self.words[a]=min(self.words[a]+1,0xffffffff)
        irqset=0
        if i['sts_valid']:
            u=i['sts_data'];healthy=(u>>73)&1;mode=(u>>103)&7
            reason=(u>>106)&255;commit=(u>>78)&255;irqset=u&255
            status=((u>>76)&1)|(healthy<<1)|((not healthy or mode==3 or ((u>>86)&1))<<2)|(mode<<3)
            status|=((u>>75)&1)<<6|((u>>74)&1)<<7|((u>>72)&1)<<8|((u>>87)&3)<<16
            self.words[4]=status;self.words[36]=(u>>8)&0xffffffff
            if oldwords[4]&2 and not healthy:sat(32)
            if irqset&128:
                self.words[40]=reason;self.words[44]=(u>>40)&0xffffffff
                if not (u>>114)&1:sat(16)
                if reason==9:sat(20)
                if reason in (1,2,11,12,13):sat(24)
                if commit not in (0,31,32,35):sat(28)
            if self.wait and (u>>72)&1 and healthy:self.valid=1;self.wait=0
        bad=False
        if wr:
            self.aw=self.w=None;self.b=0
            byte_mask=sum(255<<(8*k) for k in range(4) if strobe&(1<<k))
            if addr==0:
                if strobe&1:
                    en=word&1;soft=(word>>1)&1;start=(word>>2)&1
                    bad=bool((start and (active or soft or en)) or (soft and (active or en)) or (en and (active or not oldvalid)))
                    if not bad:
                        self.en=en;self.soft=soft;self.start=start
                        if soft or start:self.valid=0;self.wait=start;self.words[4]&=~256
            elif addr==8:
                if strobe&1:self.words[8]=word&255
            elif addr==12:
                if strobe&1:self.words[12]&=~word&255
            elif addr in RW and RW[addr]:
                if byte_mask&RW[addr]:
                    attempted=(oldwords[addr]&~byte_mask)|(word&byte_mask&RW[addr])
                    bad=bool(active or attempted!=DEFAULT[addr]);self.valid=0;self.wait=0
            else:bad=True
            self.b=2 if bad else 0
        bad=bad or (rd is not None and rd[1]!=0)
        if bad:self.valid=0;self.wait=0;irqset|=32
        self.words[12]|=irqset
        return self.outputs(1)

def update(**kw):
    widths=[('accept',1),('reason',8),('mode',3),('candidate',8),('label',8),('brake',1),('commit',8),('heartbeat',1),('busy',1),('pending',1),('backup',1),('healthy',1),('bist_done',1),('cycles',32),('lost',32),('irq_set',8)]
    v=0
    for n,w in widths:v=(v<<w)|(kw.get(n,0)&((1<<w)-1))
    return v

def main():
    rng=random.Random(0x54345352);ref=Reference();rows=[];tags={};rand_updates=False
    inp={n:0 for n,w in INPUTS};inp['rst']=1
    def tick(tag='bus',**changes):
        inp.update(changes)
        if rand_updates and 'sts_valid' not in changes:
            inp['sts_valid']=int(rng.random()<.32)
            inp['sts_data']=update(accept=rng.randrange(2),reason=rng.randrange(45),mode=rng.randrange(6),candidate=rng.randrange(16),label=rng.choice((0,1,2)),brake=rng.randrange(2),commit=rng.randrange(45),heartbeat=rng.randrange(2),busy=rng.randrange(2),pending=rng.randrange(2),backup=rng.randrange(2),healthy=rng.randrange(2),bist_done=rng.randrange(2),cycles=rng.getrandbits(32),lost=rng.getrandbits(32),irq_set=rng.getrandbits(8))
        out=ref.edge(inp);packed=0
        for n,w in INPUTS+OUTPUTS:packed=(packed<<w)|((inp if (n,w) in INPUTS else out)[n]&((1<<w)-1))
        rows.append(packed);tags[tag]=tags.get(tag,0)+1
        inp['deposit']=0
        return out
    def idle(n=1,**kw):
        for _ in range(n):tick(**kw)
    def reset():
        tick('reset',rst=0,awvalid=0,wvalid=0,arvalid=0,bready=0,rready=0,sts_valid=0)
        tick('reset',rst=0);tick('release',rst=1)
    def transact(addr=None,data=0,strobe=15,read=None,tag='directed',collision=None):
        awdelay=rng.randrange(6);wdelay=rng.randrange(6);ardelay=rng.randrange(4)
        adone=addr is None;wdone=addr is None;rdone=read is None;bdone=addr is None;done=read is None
        for k in range(80):
            before=ref.outputs(1)
            changes=dict(awaddr=addr or 0,wdata=data,wstrb=strobe,araddr=read or 0,
                         awprot=rng.randrange(8) if adone else inp['awprot'],arprot=rng.randrange(8) if rdone else inp['arprot'],
                         awvalid=int(not adone and k>=awdelay),wvalid=int(not wdone and k>=wdelay),arvalid=int(not rdone and k>=ardelay),
                         bready=int(k>9),rready=int(k>8))
            if collision is not None:
                changes.update(sts_valid=int(ref.aw is not None and ref.w is not None and ref.b is None),sts_data=collision)
            if changes['awvalid'] and before['awready']:adone=True
            if changes['wvalid'] and before['wready']:wdone=True
            if changes['arvalid'] and before['arready']:rdone=True
            if before['bvalid'] and changes['bready']:bdone=True
            if before['rvalid'] and changes['rready']:done=True
            tick(tag,**changes)
            if bdone and done:break
        else:raise RuntimeError('reference bus timeout')
        tick(tag,awvalid=0,wvalid=0,arvalid=0,bready=0,rready=0,sts_valid=0)
    reset()
    # Every JSON register: reset read, write access (all/zero/individual strobes), post-write read.
    for r in REGS:transact(read=int(r['offset'],0),tag='reset_registers')
    for r in REGS:
        a=int(r['offset'],0)
        for st in (0,1,2,4,8,15):
            transact(a,0xffffffff,st,read=a,tag='access_registers')
            transact(read=a,tag='access_readback')
        transact(a,DEFAULT[a],15,tag='restore_registers')
    reset()
    # Present the next request while the previous response occupies each slot.
    tick('master_stalls',awvalid=1,awaddr=8,wvalid=1,wdata=255,wstrb=15,arvalid=1,araddr=4,bready=0,rready=0)
    adone=wdone=rdone=False
    for k in range(20):
        pre=ref.outputs(1)
        av=int(not adone);wv=int(not wdone);rv=int(not rdone)
        if av and pre['awready']:adone=True
        if wv and pre['wready']:wdone=True
        if rv and pre['arready']:rdone=True
        tick('master_stalls',awvalid=av,awaddr=12,wvalid=wv,wdata=0,wstrb=15,arvalid=rv,araddr=12,bready=int(k>6),rready=int(k>6))
    tick('master_stalls',awvalid=0,wvalid=0,arvalid=0,bready=0,rready=0)
    reset()
    # Fault cases, each byte misalignment and full address decode (no truncation alias).
    for a in (1,2,3,0xd0,0xfffc,0x1000,0x1004,0xffff):
        transact(a,0xffffffff,15,read=a,tag='address_errors')
    # BIST authorization, stale done, active protection, disable while busy.
    idle(sts_valid=1,sts_data=update(healthy=1,bist_done=1))
    transact(0,1,tag='enable_without_bist')
    transact(0,4,tag='bist_start');idle(sts_valid=0)
    transact(read=76,tag='bist_wait')
    idle(sts_valid=1,sts_data=update(healthy=1,bist_done=1));idle(sts_valid=0)
    transact(0,1,tag='enable_valid')
    for a in (48,52,56,60,64):transact(a,DEFAULT[a],tag='active_config')
    idle(sts_valid=1,sts_data=update(healthy=1,busy=1));idle(sts_valid=0)
    transact(0,0,tag='busy_disable');transact(0,4,tag='busy_bist')
    idle(sts_valid=1,sts_data=update(healthy=1));idle(sts_valid=0)
    transact(0,2,tag='soft_reset');transact(0,7,tag='conflicting_commands')
    # W1C all bits, zero strobe, hardware set concurrent with clear, active IRQ mask.
    idle(sts_valid=1,sts_data=update(irq_set=255));idle(sts_valid=0)
    transact(8,255,tag='irq_mask')
    transact(12,255,0,tag='w1c_zero_strobe')
    transact(12,255,15,tag='w1c_set_wins',collision=update(irq_set=255))
    transact(read=12,tag='w1c_readback');transact(12,255,tag='w1c_clear')
    # Full input field min/max, including numeric limits, invalid mode and reserved enums.
    widths=[('accept',1),('reason',8),('mode',3),('candidate',8),('label',8),('brake',1),('commit',8),('heartbeat',1),('busy',1),('pending',1),('backup',1),('healthy',1),('bist_done',1),('cycles',32),('lost',32),('irq_set',8)]
    for field,w in widths:
        for value in (0,(1<<w)-1):
            idle(sts_valid=1,sts_data=update(**{field:value},**({} if field=='irq_set' else {'irq_set':128})))
            idle(sts_valid=0)
            for a in (4,16,20,24,28,32,36,40,44):transact(read=a,tag='field_boundaries')
    # Counter saturation: near max deposit, actual status updates and bus readback.
    tick('saturation_setup',deposit=1,sts_valid=1,sts_data=update(healthy=1))
    for reason in (9,11,9,11):
        idle(sts_valid=1,sts_data=update(reason=reason,commit=25,healthy=0,irq_set=128));idle(sts_valid=1,sts_data=update(healthy=1))
    idle(sts_valid=0)
    for a in (16,20,24,28,32):transact(read=a,tag='saturation_readback')
    # Fixture conversion checks raw metadata hash and semantic hex fields before packing.
    meta=json.loads((ROOT/'vectors/system.json').read_text())
    raw=(ROOT/'vectors/system.hex').read_bytes()
    assert hashlib.sha256(raw).hexdigest()==meta['sha256']
    hexrows=raw.decode().splitlines();semantic=(ROOT/'vectors/system.ports.jsonl').read_text().splitlines()
    assert len(hexrows)==len(semantic)==meta['n']
    for line,h in zip(semantic,hexrows):
        j=json.loads(line);o=j['output']['outputs'];s=j['output']['state'];word=int(h,16)
        decoded={f['name']:(word>>f['lsb'])&((1<<f['bits'])-1) for f in meta['fields']}
        assert decoded['accept']==int(o['accept'])
        assert decoded['selected']==o['candidate']
        assert decoded['mode']==g.MODES.index(o['mode'])
        assert decoded['reason_crc32']==zlib.crc32(o['reason'].encode())
        u=update(accept=int(o['accept']),reason=REASONS.index(o['reason']),mode=g.MODES.index(o['mode']),candidate=o['candidate'],label=2 if o['label']=='MITIGATION' else 1,brake=int(o['independent_brake']),commit=REASONS.index(o['commit']),heartbeat=int(o['heartbeat']),pending=int(bool(s['pending'])),backup=int(bool(s['backup'])),healthy=int(not s['fault_latched']),cycles=100+j['index'],lost=s['events_lost'],irq_set=128)
        tick('system_golden',sts_valid=1,sts_data=u);tick('system_golden',sts_valid=0)
        for a in (4,16,20,24,28,32,36,40,44):transact(read=a,tag='system_readback')
    # 2400 seeded random bus operations plus randomized concurrent status snapshots.
    rand_updates=True
    for k in range(2400):
        if k%149==0:reset()
        a=rng.choice(list(DEFAULT)+[1,2,3,0xd0,0xfffc,0x1000]);data=rng.getrandbits(32)
        if k%4==0:data=DEFAULT.get(a,0)
        transact(a if k%3 else None,data,rng.randrange(16),read=rng.choice(list(DEFAULT)+[0xffff]),tag='random')
    rand_updates=False
    # Reset with AW-only, W-only, and stalled B/R responses in flight.
    for phase in ('aw','w','both','read'):
        reset()
        tick('reset_abort',awaddr=8,wdata=255,wstrb=15,araddr=4,awvalid=int(phase in ('aw','both')),wvalid=int(phase in ('w','both')),arvalid=int(phase=='read'),sts_valid=0)
        tick('reset_abort',awvalid=0,wvalid=0,arvalid=0)
        reset()
    for a in DEFAULT:transact(read=a,tag='final_reset_map')
    width=sum(w for _,w in INPUTS+OUTPUTS)
    (HERE/'vectors.mem').write_text(''.join(f'{r:0{(width+3)//4}x}\n' for r in rows))
    (HERE/'vectors_meta.svh').write_text(f'localparam integer N = {len(rows)};\nlocalparam integer VW = {width};\n')
    report=dict(seed='0x54345352',cycles=len(rows),random_operations=2400,system_golden=meta['n'],registers=len(REGS),tags=tags,fields=INPUTS+OUTPUTS,fixture_sha256=meta['sha256'])
    (HERE/'vectors_summary.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('fields','tags')}))
if __name__=='__main__':main()
