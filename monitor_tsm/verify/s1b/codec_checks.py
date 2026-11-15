"""Independent struct-based byte checks for the S1b wire codec."""
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'golden'))
from tsmx_golden import model as g


def run():
    results = {}

    def check(name, condition):
        results[name] = bool(condition)

    ego = g.Ego(0x12345678, -1, 4000000, -2000000, 40000000, 0)
    plan = g.Plan(7, ego, ego.t, ego.t+100000, 399000, ego.v, ego.a)
    ego_bytes = struct.pack('>Iqiiqi', ego.t, ego.x, ego.v, ego.a, ego.lx, ego.lv)
    plan_bytes = (struct.pack('>I', plan.seq)+ego_bytes+
                  struct.pack('>IIqiiBIBI', plan.generated, plan.apply, plan.x,
                              plan.v, plan.a, plan.tail, plan.compute, plan.count, plan.schema))
    check('ego_independent_struct', g.pack_ego(ego) == ego_bytes)
    check('plan_independent_struct', g.pack_plan(plan) == plan_bytes)
    body = plan_bytes+struct.pack('>IIII', 9, 9, 9, 1)
    check('packet_body_struct', g.pack_packet_body(plan, (9,9,9)) == body)
    check('packet_crc', g.packet(plan, (9,9,9)).crc == zlib.crc32(body))
    check('IEEE_known_answer', zlib.crc32(b'123456789') == 0xcbf43926)
    check('snapshot_sha', g.certify(plan, ego.t+500000).snapshot == hashlib.sha256(ego_bytes).hexdigest())
    check('trajectory_sha_binds_plan', g.certify(plan, ego.t+500000).trajectory == hashlib.sha256(plan_bytes).hexdigest())
    world = g.pack_world((g.Motion(-123, 1),))
    check('world_zero_slots', world[33:] == bytes(31*32))
    check('world_fixed_length', len(world) == 1025)
    context = world+struct.pack('>qqII', -1800000, 1800000, 1, 1)
    check('context_struct', g.pack_context((g.Motion(-123,1),)) == context)
    check('context_hash', g.context_digest((g.Motion(-123,1),)) == hashlib.sha256(context).hexdigest())
    cert = g.certify(plan, ego.t+500000)
    seal_body = (bytes.fromhex(cert.snapshot)+bytes.fromhex(cert.trajectory)+
                 struct.pack('>IIIIII', cert.t_a, cert.t_e, 1, 1, 1, 1)+bytes.fromhex(cert.context))
    check('seal_body_struct', g.pack_certificate(cert, False) == seal_body)
    check('seal_sha', cert.seal == hashlib.sha256(seal_body).hexdigest())
    records = [(g.pack_packet(g.packet(plan)),721), (g.pack_certificate(cert),1217),
               (g.pack_ingress(g.Ingress()),332), (g.pack_geom(g.GeomResult(True,0,'ok',128)),81),
               (g.pack_trajectory(g.b4_mrmgen(0,g.S,0,0)),45458),
               (g.pack_event((1,'ok')),1056)]
    for data, bits in records:
        check(f'record_{bits}_length', len(data) == (bits+7)//8)
        check(f'record_{bits}_LSB_padding', int.from_bytes(data,'big') & ((1<<((-bits)%8))-1) == 0)
    # JSON helpers must never be reached by certificate/integrity decisions.
    def forbidden(*args, **kwargs):
        raise AssertionError('legacy JSON called in decision path')
    g.canonical_json_legacy = g.digest_json_legacy = forbidden
    e = g.Ego(1000000,0,6*g.S,0,40*g.S,0)
    p = g.Plan(1,e,e.t,e.t+g.DT,600000,e.v,0)
    _, decision = g.tsmx_cycle(g.Supervisor(), dict(now=e.t,ego=e,pkt=g.packet(p),cert=g.certify(p,e.t+500000)))
    check('composition_without_JSON', decision['accept'])
    summary = dict(passed=all(results.values()), n=len(results), checks=results)
    Path(__file__).with_name('codec_checks.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('CODEC', summary['passed'], summary['n'])
    assert summary['passed']


if __name__ == '__main__':
    run()
