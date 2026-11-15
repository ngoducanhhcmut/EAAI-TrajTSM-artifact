"""G1c old(pre-G1c)/new V1 shadow and V3 closed-loop decision-row smoke.

Runs 10/5 independent ICs, each across all 11 faults, one rotating schedule
and alternating F2/F3 follower parameters. This is a smoke, not a G1 rerun.
Run each revision in a fresh interpreter; no locked output is opened for writing.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT/'golden'), str(ROOT.parent/'tsm2_pilot/src'),
                str(ROOT.parent/'tsm2_pilot/vendor'), str(ROOT/'verify')]


def run(revision, stage):
    if revision == 'old':
        spec = importlib.util.spec_from_file_location(
            'tsmx_golden.model', Path(__file__).with_name('model_before_g1c.py'))
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        import tsmx_golden
        tsmx_golden.model = module
    import bridge
    g = bridge.g
    rows = []
    current = {}
    original = bridge.GoldenExecutor.decide

    def decide(self, now, ego, *args, **kwargs):
        decision = original(self, now, ego, *args, **kwargs)
        # The adapter returns accept/mode. Evaluate the pure golden selector
        # at every decision epoch, including accepted nominal decisions, so
        # candidate/label columns have the tsmx_cycle meaning on every row.
        candidate, label = g.select(bridge.ego_int(ego), bridge.LEAD)
        rows.append(dict(**current, now=bridge.q(now), accept=decision.accept,
                         mode=decision.mode, candidate=candidate, label=label))
        return decision

    bridge.GoldenExecutor.decide = decide
    bridge.install('shadow' if stage == 'v1' else 'golden')
    scenarios = bridge.ref.make_scenarios(962812, 10 if stage == 'v1' else 5, 'g1c')
    for i, scenario in enumerate(scenarios):
        model = ('F2', .8, 4) if i % 2 == 0 else ('F3', 1.15, 5)
        schedule = bridge.ref.SCHEDULES[i % len(bridge.ref.SCHEDULES)]
        for fault in bridge.ref.FAULTS:
            current = dict(ic=scenario['id'], fault=fault, schedule=schedule,
                           follower=list(model))
            bridge.ref.run(scenario, model, fault, schedule, 'executor', trace=True)
        print(stage, revision, 'IC', i+1, 'rows', len(rows), flush=True)
    target = Path(__file__).with_name(f'{stage}_{revision}_rows.json')
    target.write_text(json.dumps(rows, separators=(',', ':'))+'\n', encoding='utf-8')
    print(target.name, len(rows), hashlib.sha256(target.read_bytes()).hexdigest(), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('revision', choices=['old', 'new'])
    parser.add_argument('stage', choices=['v1', 'v3'])
    args = parser.parse_args()
    run(args.revision, args.stage)
