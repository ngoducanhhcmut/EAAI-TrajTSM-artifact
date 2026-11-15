"""Claude 04/11/2026: judge a ZCU106 board log (board/results/<tag>_*.log) against the golden vectors.
Checks per job: TOP_RSP (38 b), recorder event (1056 b), command-frame count and the 238-byte command,
CSR reason/status/lost, and CSR cycles == board-equivalent simulation (cycle-exact).
usage: python check_board.py <tag> <board_log>
"""
import json, re, sys
from pathlib import Path
HW = Path(__file__).resolve().parents[1]

def main():
    tag, log = sys.argv[1], Path(sys.argv[2])
    exp = {e['job']: e for e in json.loads((HW / 'board' / 'vectors' / f'{tag}.json').read_text())['jobs']}
    pat = re.compile(r'JOB (\d+) rsp=([0-9a-f]+) stat=([0-9a-f]+) cycles=(\d+) csr_cycles=(\d+) reason=(\d+) '
                     r'status=([0-9a-f]+) lost=([0-9a-f]+) frames=(\d+) event=([0-9a-f]+) cmd=(\S*)')
    jobs = bad = 0; cyc = []; fails = []
    for m in pat.finditer(log.read_text(errors='replace')):
        j = int(m[1]); e = exp[j]; jobs += 1; errs = []
        if int(m[2], 16) != int(e['rsp'], 16): errs.append(f"rsp {m[2]} != {e['rsp']}")
        if int(m[10], 16) != int(e['event'], 16): errs.append('event')
        if int(m[9]) != e['cmd_frames']: errs.append(f"frames {m[9]} != {e['cmd_frames']}")
        if e['cmd_frames']:
            last = m[11].split(';')[-1] if m[11] else ''
            nbytes, _, words = last.partition(':')
            if nbytes != '246' or [int(x, 16) for x in words.split(',')] != [int(x, 16) for x in e['cmd_words']]:
                errs.append('command')
        if int(m[6]) != e['reason']: errs.append('reason')
        if int(m[7], 16) != int(e['status'], 16): errs.append(f"status {m[7]} != {e['status']}")
        if int(m[8], 16) != int(e['lost'], 16): errs.append('lost')
        if int(m[5]) != e['sim_csr_cycles']: errs.append(f"cycles {m[5]} != sim {e['sim_csr_cycles']}")
        cyc.append(int(m[5]))
        if errs: bad += 1; fails.append((j, errs))
    for j, errs in fails[:20]: print('FAIL job', j, ', '.join(errs))
    done = 'BOARD_DONE' in log.read_text(errors='replace')
    print(f"{'PASS' if jobs and not bad and done else 'FAIL'} board tag={tag} jobs={jobs} mismatches={bad} complete={done}"
          + (f" max_cycles={max(cyc)} ({max(cyc)/100e3:.3f} ms @100 MHz)" if cyc else ''))
    return 0 if jobs and not bad and done else 1

if __name__ == '__main__':
    sys.exit(main())
