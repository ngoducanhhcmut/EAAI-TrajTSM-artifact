# W4b result

Conditional ordinary-completion bound: **B=1,629,173 cycles**.
**16.29173 ms @100 MHz; 8.688923 ms @187.5 MHz.**
Target 1,875,000 met with 245,827 cycles spare; tightness **947,256/B=58.1434%**.
This is an analytic RTL state-count argument, not a formal certificate.

W4's 8,701,321-cycle reviewed sum mixed serial producer/consumer costs,
overcharged pipelined SU waits, added the parallel duplicate lane,
and charged 640 replay steps twice without the certificate/history invariant.
v2 uses a max-plus streaming recurrence, a cited SU dependency schedule,
and at most 19 replay steps. Late hash retries are unreachable after admission
under ordinary fault-free RTL; health, replay and both sweeps remain charged.
Detailed reachability, timestamp-wrap and service proofs: `WCET_v2.md`.

Dominant term: two full sweeps, **1,451,844 cycles**.
Every candidate still gets 93 endpoints, 32 actors and maximum event-split slack.
Measurements calibrate/validate; no measured latency defines an analytic constant.

Native Icarus calibration uses copied benches/counters and simulation-only
portability copies under `cal/`; original RTL, golden and tb sources are untouched.
Arithmetic: 145; SU: 22,741; generator/geometry: 24 jobs each. Actor II=20..48;
SU displacement/inflation maxima=22/23. Streaming candidate pair=73,511 cycles.
Generator ordinary row gap=760; sampled stop-search gap=4,598 cycles.
Calibration logs, manifests and per-job checks: `cal/results_v2.json`.

All **289 JOB/TIMING pairs** across all requested integration text files
and the board reg300 log satisfy B>=measured; maximum **947,256**.
Records include repeated runs; worst logs have a later coverage/budget failure.

Assumptions: P=G=2; reachable state/history from reset; no injected storage faults,
uninterrupted clock/reset, no concurrent CSR reset, command consumer ready.
With W_cmd executor stall cycles, completion<=B+W_cmd; without a stall bound,
external normal completion is **UNRESOLVED**. Host response consumption is separate.
Codec, health_lane, supervisor, recorder and arbiter now have numeric RTL bounds.
Arbitrary corrupted/preloaded history is outside the 19-step invariant;
the script prints a separate conservative diagnostic envelope for that case.

Reproduce: `py -3 tsmx_hw/wcet/wcet_model_v2.py --calibrate`, then `--pair`,
then run without options. No WSL; v1 files are retained.
