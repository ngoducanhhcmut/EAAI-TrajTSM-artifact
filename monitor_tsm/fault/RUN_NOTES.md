# Execution notes (separate from the frozen sampling design)

The pilot uses the integration bench's PARA_DIRECT=1 semantic request path.
This is a material limit on interpreting duplicate-path coverage: the engine
compares the main candidate-zero result with its duplicate at
`rtl/top/m_tsmx_engine.sv:900`, but immediate disagreement containment is guarded
by `PARA_DIRECT==0` at `rtl/top/m_tsmx_engine.sv:901`. Direct-mode health requests
also come from the fixture, whereas physical mode builds them from owned parity
and lane-good state (`rtl/top/m_tsmx_engine.sv:709`). Thus these runs cannot prove
the physical-mode parity/duplicate containment rate. They measure the specified
integration configuration; P=2 is candidate parallelism plus a separate
single-candidate duplicate sweep, not two complete lockstep engines.

The classifier intentionally follows the documented conservative certification
proxy: it requires the whole accepted command to equal the golden command.
Consequently an SDC-UNSAFE observation requires case inspection to distinguish
a changed certificate/plan from a change confined to noncertificate command
metadata. No alternative certificate is silently assumed golden-certified.

Fallback-state observations in the log are diagnostic internal observations.
An equal compared record remains MASKED even if that internal path changed.
The campaign does not prove a safety requirement from an internal assertion or
from the testbench watchdog. Only an observed hardware deadline flag supports
DETECTED-by-timeout; wall-limit exhaustion remains UNRESOLVED.

`progress*.sv`/logs and `timing_probe.log` are development timing diagnostics,
not campaign outcomes. Only `results.jsonl` contributes to the pilot metrics.
The first deposit_probe run was deliberately stopped during simulator startup;
the retained deposit_probe.log/json record the later completed readback check.
