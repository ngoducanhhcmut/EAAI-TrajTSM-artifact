"""Claude 10/11/2026: fill the board-dependent \\pending items of manuscript_v5 from a checked VCU118 joint run.
   python fill_paper_board.py board_logs/results_joint.json [--power power.json] [--apply]
Without --apply it only prints the replacements (dry run). It refuses to fill anything unless the checker verdict
is PASS. power.json (optional, written by hand from the board power readout):
   {"source": "VCU118 system controller", "rail": "VCCINT", "idle_w": 0.0, "decision_w": 0.0}
After --apply: rebuild with the usual order (tectonic main -> bridge -> supplementary -> bridge -> main)."""
import sys, json, pathlib, re

HERE = pathlib.Path(__file__).resolve().parent
MS = HERE.parents[1] / 'manuscript_v5'
args = sys.argv[1:]
apply = '--apply' in args
res = json.loads(pathlib.Path(args[0]).read_text())
power = json.loads(pathlib.Path(args[args.index('--power') + 1]).read_text()) if '--power' in args else None
if res.get('verdict') != 'PASS':
    sys.exit(f"checker verdict is {res.get('verdict')} ({res.get('errors')}): write the text by hand, nothing filled")

p1, t2, p3 = res['pass1'], res['pass2_timing'], res['pass3']
rt, s2 = res['pass2_vs_pass1'], res['pass2']
f = lambda d, k='mean', n=1: f"{d[k]:.{n}f}"
# planner time from PASS1 (planner alone, exact); in PASS2 completion is detected by polling between monitor jobs
plan = res['pass1_timing']['planner_ms']
pack, fifo, dec, r2c, e2e = (t2[k] for k in ('packet_us', 'fifo_us', 'decide_ms', 'rsp_to_cmd_us', 'e2e_frame_ms'))
age = p3['age_at_brake_us'] if p3 else None

R = []  # (file, old, new)
R.append(('sections/03_architecture.tex', r'\pending{interface latency}',
          f"Observed on one VCU118 board: packet formation {f(pack, n=0)}~$\\mu$s, request transfer {f(fifo, n=0)}~$\\mu$s (means); not bounded"))
joint = (f"On a VCU118 (XCVU9P) carrying the planner at 150~MHz and the monitor at 100~MHz, with the firmware on a MicroBlaze "
         f"core, a replay of the {p1['jobs']}-job end-to-end sequence reproduces all {p1['wp_exact']} planner frames bit for bit, "
         f"forms {p1['packets']}/35 packets identically to the bench and returns the reference response for "
         f"{p1['responses']}/{p1['jobs']} jobs and the reference command frame for {p1['commands']}/{p1['jobs']}. "
         f"Replayed in real time, with the time input advanced every microsecond, the planner computing the next frame "
         f"while the firmware serves the monitor and an executor model that holds the acknowledgement from command "
         f"receipt, {rt['rsp_equal']}/{rt['jobs']} responses and {rt['cmd_type_equal']}/{rt['jobs']} command types again "
         f"equal the reference and {s2['nominal_cmds']} nominal commands are issued. A planner frame takes "
         f"{f(plan, n=2)}~ms; packet formation takes {f(pack, n=0)}~$\\mu$s, request transfer {f(fifo, n=0)}~$\\mu$s, "
         f"decision {f(dec, n=2)}~ms and response-to-command delivery {f(r2c, n=0)}~$\\mu$s on average; from planner "
         f"start to the received command a frame takes {f(e2e, n=2)}~ms on average (maximum {f(e2e, 'max', 2)}~ms, "
         f"planner completion detected by polling). The planner's register read path returned data three reads late "
         f"behind the board interconnect; the firmware reads each planner register repeatedly, which does not change "
         f"the computed values.")
if age is not None:
    joint += f" With the acknowledgement withheld, the brake output rose when the command age reached {age:,}~$\\mu$s."
R.append(('sections/07d_rq4.tex',
          r'The joint planner--firmware--TSM--executor board run is \pending{packet formation, response/command agreement, expiry, acknowledgement and end-to-end timing}. Component-level simulation is not that joint experiment.',
          joint))
if power:
    R.append(('sections/07d_rq4.tex', r'\pending{measured rail power and energy per decision, if collected}.',
              f"The {power['rail']} rail drew {power['idle_w']:.2f}~W idle and {power['decision_w']:.2f}~W during decisions "
              f"({power['source']})."))
else:
    R.append(('sections/07d_rq4.tex', r'\pending{measured rail power and energy per decision, if collected}.',
              'Rail power was not measured.'))
if age is not None:
    R.append(('supplementary.tex', r'transport and actual delivery \pending{board measurement}.',
              f"on the VCU118 board the brake rose at a command age of {age:,}~$\\mu$s with the acknowledgement withheld; "
              f"physical transport to an executor is a vehicle-integration obligation."))

R.append(('main.tex', r'Joint board operation remains open.',
          f"Run jointly on one VCU118 board, planner and monitor reproduce all {p1['wp_exact']} planner frames bit for bit "
          f"and {p1['responses']} of {p1['jobs']} reference responses."))

bad = 0
for fn, old, new in R:
    p = MS / fn
    s = p.read_text(encoding='utf-8')
    n = s.count(old)
    print(f'--- {fn}: {n} match\n  OLD: {old}\n  NEW: {new}\n')
    if n != 1:
        bad += 1
        continue
    if apply:
        p.write_text(s.replace(old, new), encoding='utf-8', newline='\n')
left = sum(len(re.findall(r'\\pending\{', (MS / x).read_text(encoding='utf-8')))
           for x in ['supplementary.tex'] + [f'sections/{y.name}' for y in (MS / 'sections').glob('*.tex')])
print(('APPLIED' if apply else 'DRY RUN'), 'replacements with problems:', bad, '| \\pending left:', left)
