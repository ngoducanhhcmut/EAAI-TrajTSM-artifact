# W4 result

**FAIL to certify normal decision completion in 10 ms.**
B_completion is UNRESOLVED from the permitted sources; no measured worst is used as a bound.
The reviewed compute envelopes sum to 8,701,321 cycles before missing services.
This conservative sum exceeding the budget does not prove an actual deadline miss.

B_response = **1,875,000 cycles**, analytically enforced by the engine deadline counter
(`rtl/top/m_tsmx_engine.sv:628`, `:1124`-`:1136`): 18.75 ms at 100 MHz,
10 ms at 187.5 MHz. It allows deadline rejection and does not guarantee normal completion,
command consumption, drain completion, or next-request acceptance.
Requested tightness 947,263/B_response = **50.520693%**; against B_completion: UNRESOLVED.

K_max=93 endpoints: 0.1 s prefix + 2 s ramp + 5.1 s brake + 2 s hold,
including t=0. Integer-grid comparison proves the bound; 3,696 golden evaluations confirm it.

Validation: `py -3.13 tsmx_hw/wcet/wcet_model.py --grid`.
All **14 available** JOB/TIMING pairs pass the response-bound check;
min/max slack: **927,744 / 1,658,868 cycles**.
Coverage: reg300=12 (jobs 288..299), apos=0, worst2=1, worst_apos=1.
No matching JOB/TIMING records in summary. Observed worst=947,256;
the prompt's 947,263 is not present in the permitted records.
The checker is a watchdog-bound sanity check, not validation of a complete compute model.

Assumptions: requested P=G=2 elaboration; uninterrupted clock/reset and legal FSM state.
Ordinary compute composition additionally assumes no concurrent CSR reset.
Normal completion requires finite bounds for codec ready/final response, health_lane,
supervisor, recorder, arbiter, and command-consumer readiness; these are UNRESOLVED,
not assigned guessed numbers. Response consumption additionally requires host readiness.
The conditional health-leaf envelope cannot establish the omitted health_lane latency.

A reviewer still needs the omitted module control paths and deployment parameter evidence,
external backpressure contracts, formal FSM/handshake liveness including drain/retry,
and formal confirmation of integer integration monotonicity used in the 93-row proof.
Tighten producer/consumer overlap, event splits and replay/search bounds to attempt
a useful compute certificate. Full regression logs are needed for the missing jobs.
All new artifacts are in this directory; no simulator or WSL was used.
