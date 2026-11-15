"""Supervisor runner: require an injected waypoint and a TSM-stage failure."""
import sys
sys.dont_write_bytecode=True
import argparse, subprocess, json
from pathlib import Path

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--tool',choices=['xsim','verilator'],default='xsim')
    a=ap.parse_args();here=Path(__file__).resolve().parent
    if a.tool=='xsim':cmd=['cmd','/c',str(here/'run_xsim.bat'),'mutant']
    else:cmd=['bash',str(here/'run_verilator.sh'),'+MUTANT_WAYPOINT']
    log=here/f'{a.tool}_mutant.log'
    with log.open('w') as out:
        r=subprocess.run(cmd,cwd=here,stdout=out,stderr=subprocess.STDOUT)
    text=log.read_text(errors='replace')
    # Do not count compilation errors, missing files, packet-only failure or a
    # failure before injection as mutant detection.
    manifest=json.loads((here/'manifest.json').read_text())
    mut=manifest['mutant'];frame=mut['frame']
    assert manifest['waypoint_source']=='recorded_final_35'
    assert frame==7 and mut['packet_changed'] and mut['golden_output_changed']
    tail=text.split(f'MUTANT_INJECTED frame={frame} word=0',1)
    assert len(tail)==2 and any(s in tail[1] for s in
        ('TSM_RESPONSE_MISMATCH','TSM_COMMAND_MISMATCH','TSM_EVENT_MISMATCH')),str(log)
    assert f'PACKET_BYTES_MISMATCH frame={frame} ' in tail[1],str(log)
    assert 'E2E_PASS' not in text
    print(f'MUTANT_DETECTED at TSM stage; simulator exit={r.returncode}; {log}')

if __name__=='__main__':main()
