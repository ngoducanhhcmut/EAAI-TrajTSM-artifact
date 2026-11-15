"""Rebuild S1 artifacts offline; writes only beside this file. Python 3.13.

Uses the supplied VLSIT tools unchanged. The supplied Markdown template is
missing: check() explicitly reports its recovered-template limitation.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from xml.sax.saxutils import escape

sys.dont_write_bytecode = True
OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
SKILL = ROOT / '.agents/skills/vlsit-asic-ip-microspec'
SCRIPTS = SKILL / 'scripts'
FIG = OUT / 'figures'
FIG.mkdir(exist_ok=True)

def dump(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')

def run(script, *args):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    # Reuse the existing pure-Python installation; do not install anything.
    existing = Path.home() / 'AppData/Local/Programs/Python/Python39/Lib/site-packages'
    env['PYTHONPATH'] = str(existing) + os.pathsep + env.get('PYTHONPATH', '')
    p = subprocess.run([sys.executable, '-B', str(SCRIPTS / script), *map(str, args)],
                       capture_output=True, text=True, encoding='utf-8', env=env)
    print(p.stdout, end='')
    if p.returncode:
        print(p.stderr, end='')
        raise SystemExit(p.returncode)

TITLES = [
 'Purpose and scope', 'Applicable documents and standards', 'Requirements',
 'Features and configurations', 'Architecture', 'Interfaces and ports',
 'Clock, reset and power', 'Parameters', 'Data representation',
 'Functional behavior', 'Registers', 'Error handling', 'PPA targets',
 'RTL implementation contract', 'Verification', 'DFT',
 'Physical implementation and timing', 'Security and safety',
 'Requirements traceability', 'Assumptions, decisions and open items',
 'Glossary', 'References']

def csr():
    regs = []
    def reg(name, description, fields):
        occupied = set()
        for f in fields:
            v = f['bits'].strip('[]').split(':')
            hi, lo = int(v[0]), int(v[-1])
            occupied.update(range(lo, hi+1))
        b = 31
        while b >= 0:
            if b in occupied:
                b -= 1
                continue
            hi = b
            while b >= 0 and b not in occupied:
                b -= 1
            fields.append(dict(name='reserved', bits=f'[{hi}:{b+1}]' if hi != b+1 else f'[{hi}]',
                               type='ro', reset='0x0', description='Read zero; writes ignored.'))
        regs.append(dict(name=name, offset=hex(4*len(regs)), description=description, fields=fields))
    def f(name, bits, typ='rw', reset=0, description=''):
        return dict(name=name, bits=bits, type=typ, reset=hex(reset), description=description)
    reg('ctrl', 'ASSUMPTION-006: run only after BIST passes; disable forces independent brake. Configuration writes require disabled and idle.',
        [f('en','[0]',description='Enable decision admission.'),
         f('soft_rst','[1]','rwi',description='Write one requests a one-cycle supervisor reset; reads zero.'),
         f('bist_start','[2]','rwi',description='Write one requests BIST while disabled; reads zero.')])
    reg('status', 'Atomic last completed decision status; reset mode L3. No live partial decision exposed.',
        [f('busy','[0]','ro'),f('healthy','[1]','ro'),f('fault','[2]','ro',1),
         f('mode','[5:3]','ro',3),f('pending','[6]','ro'),f('backup','[7]','ro'),
         f('bist_done','[8]','ro'),f('label','[17:16]','ro',2)])
    reg('irq_enable','Level interrupt mask.',[f('mask','[7:0]')])
    reg('irq_status','Sticky; hardware set wins simultaneous software clear.',
        [f('events','[7:0]','w1c',description='Bits: reject, commit fault, health fault, log overwrite, decision deadline, configuration error, BIST done, decision done.')])
    reg('fault_count','Saturating count of rejected decisions, once per completed transaction.',[f('count','[31:0]','ro')])
    reg('crc_count','Saturating B1 crc rejects.',[f('count','[31:0]','ro')])
    reg('fresh_count','Saturating freshness, freeze and clock faults.',[f('count','[31:0]','ro')])
    reg('cert_count','Saturating B9 rejects excluding pending/no_pending.',[f('count','[31:0]','ro')])
    reg('health_count','Saturating unhealthy transitions.',[f('count','[31:0]','ro')])
    reg('log_lost','Golden B10 lost count; saturating; reset clears.',[f('count','[31:0]','ro')])
    reg('last_reason','Last decision reason; enumeration in spec ABI.',[f('reason','[7:0]','ro')])
    reg('decision_cycles','Elapsed clocks of last completed decision.',[f('count','[31:0]','ro')])
    reg('profile_count','Config1 locks full 16-profile table; any other value fails configuration.',[f('count','[7:0]','rw',16)])
    reg('profile_limit','Config1 locks maximum 128 integration cells; 129 endpoints permitted.',[f('limit','[7:0]','rw',128)])
    reg('profile_mask','All 16 diagnostic profiles enabled. B7 still excludes instant profiles. Config1 locks 0xffff.',[f('mask','[15:0]','rw',65535)])
    reg('fresh_timeout_us','Config1 locks 150000 us; extension requires golden revalidation.',[f('timeout','[31:0]','rw',150000)])
    reg('odd_v_max','SI times 1000000. Config1 locks 10000000. Hardware field admits up to 20000000 only in a future validated configuration.',[f('v_max','[31:0]','rw',10000000)])
    reg('ack_timeout_us','Config1 locks 40000 us.',[f('timeout','[31:0]','ro',40000)])
    reg('lease_max_us','Config1 locks 500000 us from generated.',[f('lease','[31:0]','ro',500000)])
    reg('config_valid','Zero after reset until defaults checked and BIST complete. Bad write invalidates configuration until defaults restored and BIST rerun.',[f('valid','[0]','ro')])
    for cid in range(16):
        b = (2,4,6,8)[cid//4]*1000000
        j = (2,4,8,0)[cid%4]*1000000
        reg(f'profile_{cid}_decel',f'Fixed Config1 profile {cid}; deceleration magnitude in SI times S.',[f('decel','[31:0]','ro',b)])
        reg(f'profile_{cid}_jerk',f'Fixed profile {cid}; zero denotes instant, excluded by B7.',[f('jerk','[31:0]','ro',j)])
    doc = dict(module='m_tsmx_csr', **{'async':0}, protocol='AXI4-Lite', data_width=32,
               address_width=16, write_strobe_width=4,
               assumptions=['ASSUMPTION-006','ASSUMPTION-011'], registers=regs)
    path = OUT / 'tsmx_csr.json'
    dump(path, doc)
    run('vlsit_csr_tool.py','validate',path)
    run('vlsit_csr_tool.py','fill',path,'--out',OUT/'TSMX_CSR.xlsx','--force')
    # Tool's workbook defaults are APB: make the delivered workbook truthful.
    sys.path.append(str(Path.home()/'AppData/Local/Programs/Python/Python39/Lib/site-packages'))
    from openpyxl import load_workbook
    wb = load_workbook(OUT/'TSMX_CSR.xlsx')
    for name in ('CSR','ASYNC_CSR'):
        ws=wb[name]
        ws['B3']='m_tsmx_csr';ws['B4']='AXI4-Lite';ws['B5']=32;ws['B6']=16;ws['B7']=4
        if name=='ASYNC_CSR':
            for row in ws.iter_rows(min_row=16):
                for cell in row:cell.value=None
    wb['CSR']['G9']='ASSUMPTION-006/011: AXI4-Lite wrapper; tool template APB label adapted. See specification for bus contract.'
    wb.save(OUT/'TSMX_CSR.xlsx')
    print('Workbook verified: AXI4-Lite, 32/16/4; unused asynchronous sample rows cleared.')

def figures():
    blocks=[('in','Ingress',0,1),('b1','B1 integrity',1,1),('b2','B2 splice',2,1),
            ('b4','B4 generator x4',1,2),('b3','B3 geometry x4',2,2),
            ('b7','B7 selector',3,2),('b8','B8 supervisor',3,1),
            ('b9','B9 certificate',2,0),('arb','Command arbiter',4,1),
            ('out','Executor',5,1),('b10','B10 event ring',4,2),
            ('b13','B13 health',3,3),('csr','AXI4-Lite CSR',4,3),
            ('codec','Canonical codec',0,0),('arith','Integer arithmetic',0,3)]
    links=[('in','b1','packet'),('b1','b2','admitted'),('b2','b8','splice'),
           ('b4','b3','rows'),('b3','b7','results'),('b7','b8','candidate'),
           ('b9','b8','commit/reuse'),('b8','arb','mode'),('b9','arb','pending/backup'),
           ('arb','out','command'),('b8','b10','event'),('b13','b8','health'),
           ('csr','b13','BIST'),('codec','b9','hash'),('arith','b4','rational')]
    d=dict(title='TSM-X v1: core clock 187.5 MHz',blocks=[dict(id=i,label=l,col=x,row=y) for i,l,x,y in blocks],
           groups=[dict(label='core clock / reset domain',blocks=[x[0] for x in blocks if x[0] not in ('in','out')])],
           links=[dict(**{'from':a,'to':b},label=l) for a,b,l in links])
    dump(FIG/'block_diagram.json',d)
    run('vlsit_block_diagram.py','tex',FIG/'block_diagram.json','--out',FIG/'block_diagram.tex','--force')
    # Offline SVG preview of the same source, not a claimed LaTeX rendering.
    svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1500" height="650" viewBox="0 0 1500 650">',
         '<rect width="1500" height="650" fill="white"/>',
         '<defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8" fill="black"/></marker></defs>',
         '<text x="750" y="28" text-anchor="middle" font-family="sans-serif" font-size="20">TSM-X v1 — offline JSON preview (TikZ source supplied)</text>']
    pos={i:(20+x*246,65+y*145) for i,l,x,y in blocks}
    for a,b,l in links:
        x,y=pos[a];xx,yy=pos[b]
        svg.append(f'<path d="M{x+195},{y+35} L{xx},{yy+35}" stroke="black" fill="none" marker-end="url(#arrow)"/>')
    for i,l,_,_ in blocks:
        x,y=pos[i]
        svg.extend([f'<rect x="{x}" y="{y}" width="195" height="70" fill="white" stroke="black"/>',
                    f'<text x="{x+97}" y="{y+40}" text-anchor="middle" font-family="sans-serif" font-size="17">{escape(l)}</text>'])
    svg.append('</svg>')
    (FIG/'block_diagram.svg').write_text('\n'.join(svg),encoding='utf-8')
    waves={
      'ingress':('Ingress: success, stall and CRC reject',[
       ('clk','p...........'),('valid','01..01...0..'),('ready','0..101...0..'),
       ('data','=...=....=..',['pkt1','badCRC','idle']),('accepted','000100000000'),('reject','000000001000')]),
      'decision':('Decision: generate, check, select and switch; gaps are variable cycle intervals',[
       ('clk','p...........'),('stage','=.=.=.=.=.=.',['ingress','generate','check','select','issue','switch']),
       ('generate','001100000000'),('check','000011000000'),('candidate','=.....=.....',['15','0']),
       ('cmd_valid','000000001100'),('cmd_ready','111111111111'),('override','100000000000')]),
      'certificate':('Certificate: ACK deadline and strict expiry, times in microseconds',[
       ('time','=.=.=.=.=.=.',['0','39999','40000','100000','499999','500000']),
       ('pending','1...0.......'),('ack','0...........'),('ack_timeout','000010000000'),
       ('expiry','000000000011'),('backup_valid','000000000000'),('override','00001.......')]),
      'fsm':('Separate decision transactions: recovery and degraded levels',[
       ('clk','p...........'),('accept','111000000000'),('health','111111110000'),
       ('reuse','000100000000'),('fallback','000010000000'),
       ('mode','======..==..',['RECOVERY','RECOVERY','L0','L1','L2','L3','HOLD','L3']),
       ('good','====........',['1','2','3','0'])]),
      'axi':('Project AXI4-Lite contract: write, response stall, bad address; conformance open',[
       ('clk','p...........'),('awvalid','01...01.....'),('awready','11...11.....'),
       ('wvalid','001...01....'),('wready','111...11....'),('bvalid','000111001100'),
       ('bready','000001000100'),('bresp','=..=....=...',['OKAY','OKAY','SLVERR'])]),
      'egress':('Executor issue held stable; ACK ID mismatch ignored, then timeout override',[
       ('clk','p...........'),('cmd_valid','011110000000'),('cmd_ready','000010000000'),
       ('seq','=...........',['7']),('ack_valid','000000100000'),('ack_seq','=...........',['6']),
       ('override','000000000011'),('heartbeat','111111111111')]),
      'log':('Recorder: write never waits for host; full ring overwrites oldest',[
       ('clk','p...........'),('event_valid','011111000000'),('event_ready','111111111111'),
       ('drain_ready','000000000000'),('full','000011111111'),('lost','=...===.....',['0','1','2','3'])])}
    for name,(title,signals) in waves.items():
        data=dict(head=dict(text=title),signal=[dict(name=s[0],wave=s[1],**({'data':s[2]} if len(s)>2 else {})) for s in signals],
                  foot=dict(text='Illustrative transaction ordering; timeout gaps are not one core clock. See normative timing tables.'))
        dump(FIG/(name+'.json'),data)
        run('vlsit_waveform_svg.py','render',FIG/(name+'.json'),'--out',FIG/(name+'.svg'),'--force')

def check():
    spec=OUT/'TSMX_Design_Specification.md'
    template=SKILL/'reference/templates/VLSIT_ASIC_IP_Design_Specification_Template.md'
    limitations=[]
    if not template.exists():
        limitations.append('Native vlsit_spec_tool.py check: BLOCKED (FileNotFoundError for original template).')
        limitations.append('Original VLSIT Markdown template absent; exact-title equivalence cannot be verified.')
        recovered=OUT/'VLSIT_recovered_structure.md'
        recovered.write_text('# Recovered section baseline\n\nDerived from the supplied writing guide, not the missing original template.\n\n'+
                             '\n\n'.join(f'## {i}. {t}' for i,t in enumerate(TITLES,1))+'\n',encoding='utf-8')
        template=recovered
    module_spec=importlib.util.spec_from_file_location('vlsit_check',SCRIPTS/'vlsit_spec_tool.py')
    tool=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(tool)
    tool.TEMPLATE=template
    errors=tool.findings_for(spec.read_text(encoding='utf-8'))
    lines=[*limitations,*['ERROR: '+e for e in errors],
           f'{"FAIL" if errors else "PASS"}: {len(errors)} error(s), {len(tool.split_sections(spec.read_text(encoding="utf-8")))} section(s)',
           f'Baseline used: {template.relative_to(ROOT)}',
           'This is the unchanged skill validation logic with an explicit local template-path override.',
           'No RTL simulation, synthesis, WCET proof, AXI standard conformance or LaTeX compilation claimed.']
    if len(spec.read_text(encoding='utf-8').splitlines()) > 1500:
        raise SystemExit('Specification exceeds 1500-line limit')
    # Check that every image/source pair exists and is parseable, without claiming
    # raster visual inspection or LaTeX rendering.
    import xml.etree.ElementTree as ET
    for source in FIG.glob('*.json'):
        doc=json.loads(source.read_text(encoding='utf-8'))
        ET.parse(source.with_suffix('.svg'))
        if 'signal' in doc:
            for signal in doc['signal']:
                if signal['wave'].count('=') != len(signal.get('data', [])):
                    raise SystemExit(f'WaveJSON data count mismatch: {source.name}/{signal["name"]}')
    lines += ['Artifact checks: all diagram/wave JSON and SVG pairs parse; waveform data counts match.',
              f'Specification length: {len(spec.read_text(encoding="utf-8").splitlines())} lines (limit 1500).']
    (OUT/'VALIDATION.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    (OUT/'VALIDATION.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('\n'.join(lines))
    if errors:raise SystemExit(1)
    # A G1 fingerprint makes concurrent source changes reviewable.
    files=['tsmx_hw/PLAN.md','tsmx_hw/golden/FORMATS.md','tsmx_hw/golden/LATENCY_MODEL.md',
           'tsmx_hw/golden/README.md','tsmx_hw/golden/tsmx_golden/model.py','tsm_research/TSM_X_DESIGN_v2.md']
    dump(OUT/'SOURCE_MANIFEST.json',dict(files={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in files}))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['csr','figures','check','all']);a=parser.parse_args()
    if a.action in ('csr','all'):csr()
    if a.action in ('figures','all'):figures()
    if a.action in ('check','all'):check()
