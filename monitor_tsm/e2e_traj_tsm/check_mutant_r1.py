"""Claude 07/11/2026: the detection criteria of run_mutant.py, applied to an existing verilator_mutant.log."""
import json, sys
from pathlib import Path
here = Path(__file__).resolve().parent
text = (here / 'verilator_mutant.log').read_text(errors='replace')
manifest = json.loads((here / 'manifest.json').read_text())
mut = manifest['mutant']; frame = mut['frame']
assert manifest['waypoint_source'] == 'recorded_final_35'
assert frame == 7 and mut['packet_changed'] and mut['golden_output_changed']
tail = text.split(f'MUTANT_INJECTED frame={frame} word=0', 1)
assert len(tail) == 2, 'mutant not injected'
assert any(s in tail[1] for s in ('TSM_RESPONSE_MISMATCH', 'TSM_COMMAND_MISMATCH', 'TSM_EVENT_MISMATCH')), 'no TSM-stage mismatch'
assert f'PACKET_BYTES_MISMATCH frame={frame} ' in tail[1], 'no packet mismatch'
assert 'E2E_PASS' not in text
print('MUTANT_DETECTED at TSM stage;', [l for l in tail[1].splitlines() if 'MISMATCH' in l][:4])
