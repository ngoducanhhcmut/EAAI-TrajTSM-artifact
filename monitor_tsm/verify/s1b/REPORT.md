# S1b amendment evidence

Packed big-endian record encoding replaces JSON in the decision path. Each
outer record has zero padding at its LSB end to a whole byte; nested records
use exact bit widths. CRC-32 IEEE and SHA-256 are unchanged. Snapshot binds
Ego, trajectory binds Plan, context binds ordered World/lane/frame/units, and
seal binds Certificate without present/seal. See spec sections 5.5.2 and 9.2.

Model SHA-256:

- Old: `d8766763d3de1fafca263924e96e44ff987522aa7198acf4700a6d22fec47fbd`
- New: `a216ccae9d7b54837138c7f50a4e7bd3306ea879f8f2614dad19b147be7624dc`

| Check | Result |
|---|---|
| Existing unit suite | 148/148 pass |
| Independent struct/CRC/SHA/padding checks | 26/26 pass |
| Directed edges | 117/117 pass |
| V2 | 200000 inputs; 50000 each B2/B3/B4/B7; zero counterexamples |
| V1 old/new shadow | 10 IC, 110 rollouts, 13886 decision rows, zero mismatches |
| V3 old/new closed loop | 5 IC, 55 rollouts, 6761 decision rows, zero mismatches |
| CSR | PASS, zero errors, 52 registers |
| Structure | Zero errors against existing recovered 22-section baseline |

Identity compares accept/mode/candidate/label at every decision epoch, plus
scenario/fault/schedule/follower/time alignment. The adapter supplies accept/mode;
the pure golden selector supplies candidate/label even when a nominal packet is
accepted, matching the unconditional selector meaning in tsmx_cycle. Each IC
is exercised across all 11 fault types; one schedule rotates by IC and followers
alternate F2(.8,4) / F3(1.15,5). These are smoke subsets, not the full G1 matrix.
Old/new row-file hashes match exactly; see summary.json. V2 retains the original
million-input gate logic, so its stored gate is INCONCLUSIVE at this requested
200000-input amendment sample. Its counterexample count is zero.

Architecture: P=8/G=8, private lane arithmetic, paired B4-to-B3 row streaming,
35 row slots/lane, and in-order early-out only within a sweep. Both complete
16-candidate sweeps are charged; no early-out discount is used.

| Allocation | Cycles |
|---|---:|
| Two full sweeps, including batch fill/drain | 797696 |
| B1 / CRC | 16384 |
| B2 | 12288 |
| Nominal proxy | 166656 |
| Bridge | 3072 |
| Object propagation | 20480 |
| Reaction | 12288 |
| Reachable backup replay | 24320 |
| B7 twice / B8 / recorder | 162 |
| B9 hashes/checks/reseal | 32768 |
| Dedicated B13 | 65536 |
| Transport/CSR/arbitration reserve | 16384 |
| Total | 1168034 |

Total is 6.229515 ms at187.5MHz, below8ms by331966 cycles and below10ms
by706966 cycles (37.705% of A7). These are architecture budgets requiring RTL
scheduling and synthesis confirmation, not measured WCET. Motion widths are
s96 integer-time, s128 rational geometry, s160 capped ramp; B4 vn needs s112.
Each B4 context owns16 multipliers/two160-bit dividers. Each B3 lane owns8
multipliers, one pipelined128-bit divider and one96-bit update divider. BIST and
helpers have dedicated arithmetic. SHA retains256-bit digests. Exact equations,
per-term bounds, resource costs and deferred streaming validation are in spec.

P/G have no fields in the existing CSR map, so JSON/workbook/register resets
remain unchanged. The original VLSIT template remains absent; the structure tool
was rerun against the existing recovered baseline. Original-template equivalence
and physical timing remain open items in section20.

The affected b1/b9/system fixtures and edges are regenerated. Legacy versions
are under ../../vectors/legacy_json/. Other blocks retain their trace-only JSON
diagnostic output hashes through digest_json_legacy; no JSON function is called
by the hardware decision path. A codec test replaces both JSON helpers with a
function that raises, then runs an accepted complete supervisor transaction.
No RTL or unit-testbench files were edited.

Reproduction from the workspace, using Python3.13 and
PYTHONPATH=`tsmx_hw/golden;tsm2_pilot/vendor`:

```powershell
py -3.13 -B tsmx_hw/verify/s1b/codec_checks.py
py -3.13 -B tsmx_hw/verify/s1b/identity_smoke.py old v1
py -3.13 -B tsmx_hw/verify/s1b/identity_smoke.py new v1
py -3.13 -B tsmx_hw/verify/s1b/identity_smoke.py old v3
py -3.13 -B tsmx_hw/verify/s1b/identity_smoke.py new v3
py -3.13 -B -c "import sys;sys.path.insert(0,'tsmx_hw/verify');import unit;from pathlib import Path;unit.run(Path('tsmx_hw/verify/s1b'))"
py -3.13 -B -c "import sys;sys.path.insert(0,'tsmx_hw/verify');import soundness;from pathlib import Path;soundness.run(Path('tsmx_hw/verify/s1b'),n=200000)"
```

During initial tool discovery, expand.py and edge_cases.py executed when passed
--help. They were rerun with the saved old model to restore legacy outputs before
archiving. Subsequent edge/expansion verification redirected verify writes to
s1b/ and restored unaffected vector files byte-for-byte. G1 locked stages were
not rerun; all amendment statistics/identity outputs are in this directory.
