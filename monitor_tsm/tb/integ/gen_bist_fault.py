"""One physical BIST-resource fault, mapped to golden health=False containment.

The driven health input stays True. The separate TB corrupts the BIST stop result.
This is a fault-containment oracle, not an unmodified-healthy-input equivalence claim.
"""
import json
from gen_sequences import HERE,g,record,cat,request,command
e=g.Ego(0,0,1000000,0,50000000,0)
px,pv=g.advance(e.x,e.v,e.a,20000)
p=g.Plan(1,e,0,20000,px,pv,0)
oracle=dict(now=0,ego=e,pkt=g.packet(p),cert=g.certify(p,500000),health=False)
ns,o=g.tsmx_cycle(g.Supervisor(),oracle)
actual={**oracle,'health':True}
bits=cat([(1,1),(request(actual),44673),(record(g.pack_top_rsp(o),38),38),
 (command(ns,o,actual),1897),(record(g.pack_ingress(ns.ingress),332),332),
 (g.MODES.index(ns.mode),3),(ns.good,2),(ns.fault_latched,1),(bool(ns.pending),1),
 (bool(ns.backup),1),(ns.events_lost,32),(record(g.pack_event(ns.events[-1]),1056),1056)])
(HERE/'bist_fault.mem').write_text(f'{bits:012010x}\n')
(HERE/'bist_fault.json').write_text(json.dumps(dict(response=o,
 fault='dedicated BIST returned stop=0 instead of1100000; no protected source edit',
 oracle='tsmx_cycle with health=False; driven health=True plus internal BIST fault'),indent=2))
print('Generated BIST fault containment vector')
