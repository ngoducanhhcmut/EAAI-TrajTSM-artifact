"""Claude 07/11/2026 (W11): the dump-enabled rerun must reproduce the W8 per-step logs exactly (same decisions).
Compares logs/w11{a,b}/<cond>/<token>_<cond>.jsonl with the W8 run of the same condition (mainA/mainB/mainC).
Only scenarios whose rerun log is complete (same number of lines as W8, or the rerun condition finished) are judged."""
import sys
from pathlib import Path
L = Path(__file__).resolve().parents[1] / 'logs'
same = diff = partial = 0; diffs = []
for new in sorted(list(L.glob('w11a/*/*.jsonl')) + list(L.glob('w11b/*/*.jsonl'))):
    cond = new.parent.name
    old = [p for p in L.glob(f'main*/{cond}/{new.name}')]
    if len(old) != 1:
        print('no unique W8 log for', new); diffs.append(str(new)); continue
    a, b = old[0].read_text().splitlines(), new.read_text().splitlines()
    if len(b) < len(a):
        partial += 1; continue
    if a == b:
        same += 1
    else:
        diff += 1
        k = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), min(len(a), len(b)))
        diffs.append(f'{cond}/{new.name} first difference at line {k}')
print(f'identical {same}, different {diff}, incomplete {partial}')
for d in diffs[:20]:
    print(' ', d)
sys.exit(1 if diff or diffs else 0)
