# R4 decisions
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

- D01: User delegation supersedes skill R-005/R-006, confirmation gates and R-026 waits.
  Only CSR-owned paths are written. No existing CSR implementation was present.
- D02: Gap scan G-001..006 are template-heading mismatches (purpose, compliance,
  clock/reset domains, hierarchy, synthesis assumptions). Scoped sections 5.3,
  5.5.12, 6.1, 7 and 14 supply the behavioral contract; no blocking gap remains.
- D03: SPEC-ISSUE: 5.3's generic request/response ports do not apply to this bus
  leaf: only the explicit AXI and status/config ports of 5.5.12 are implemented.
  Preserve its `axi` prefix despite VLSIT PRT-01 recommending `axil` (NAM-02).
  Fixed legal parameters ADDR_W=16, DATA_W=32; unsupported overrides excluded.
- D04: Reset assertion is asynchronous; release synchronization and DFT overrides
  belong to the SoC wrapper. Ready is gated low during reset. Independent single
  AW/W slots commit on the cycle after both are captured. B/R slots hold under
  stalls; no replacement on a response-consumption edge. Reads sample old state
  on a simultaneous write/status edge. Invalid response payloads are zero.
- D05: Every misaligned, unmapped, RO-only write, illegal configuration or active
  safety write returns SLVERR=2 and sets IRQ bit5. Reads of defined registers are
  OKAY=0. Reserved writes are ignored within writable registers; RO-only writes
  still error even with zero strobes (6.1). Zero-strobe writable writes are no-ops.
- D06: Config1 RW fields accept only their reset values after byte merge. Rejected
  writes leave their contents intact but invalidate config_valid. A valid write
  to a configuration field also invalidates prior validation. BIST must be rerun.
  IRQ mask and W1C remain serviceable while enabled/busy. CTRL disable alone is
  always allowed, including busy; enabling requires config_valid and idle.
  Other CTRL changes require disabled/idle; start+enable and start+reset error.
  Same-cycle incoming busy participates in safety-write protection.
- D07: BIST start arms a completion wait, clears prior valid and bist_done, and
  emits one pulse. Only a subsequent status snapshot with bist_done AND healthy
  validates defaults. A stale done cannot validate. Soft reset emits one pulse,
  disables admission, and invalidates configuration; diagnostic state persists
  until external reset or a later status update. Bad bus access cancels BIST wait.
- D08: SPEC-ISSUE: CSR_UPDATE lacks fault_latched and completed-valid fields.
  Status fault is !healthy OR L3 OR independent_brake; IRQ decision_done bit7
  identifies completed transactions for decision/reason/cycle counters. Other
  status pulses atomically update status/lost but do not count another decision.
  Top must follow this convention. Label exposes only its two defined low bits.
- D09: Rejected completed decisions increment fault_count; reason9 increments
  crc_count; reasons1/2/11/12/13 increment fresh_count. B9 commit codes other than
  ok0/committed31/pending32/no_pending35 increment cert_count. Healthy->unhealthy
  transitions increment health_count, not the initial unhealthy reset condition.
  All local counters saturate. log_lost mirrors the supplied saturating B10 count.
- D10: Hardware IRQ set wins W1C, including same-cycle configuration faults.
  Clearing interrupts never changes status/config authorization. Reserved reads
  are zero. PROT is accepted without policy. Bus backpressure never gates updates.
- D11: No CSR golden function/vector exists. Local Python reference uses JSON
  fields and the specified bus rules, imports golden constants, converts all 128
  system semantic fixtures by field name and validates their hex metadata hash.
  Other FORMATS physical fields are not CSR inputs; boundary coverage applies to
  every CSR_UPDATE and register field, not invented motion/arithmetic ports.
- D12: Verification uses portable clocked immediate assertions. Each has hit
  counts, a real interface-net fault injection and a fatal nonzero failure. Binary
  fault values test functional assertions; four-state X injection tests no-X
  assertions in Icarus. Input faults separately exercise master protocol monitors.
  Counter saturation setup deposits near-maximum state in verification only;
  increments and reset are then exercised through real interfaces.
- D13: VLSIT rule file v2, skeleton and Moore example guide process separation;
  the channel slots are valid bits rather than encoded FSMs. reg_ naming follows
  VLSIT and accepted SEL. No multipliers/dividers, CDC, RAM or clock gating.
  No synthesis, STA, CDC/RDC, DFT or formal signoff is claimed.
- D14: The first baseline reached no master stall assertion: the serial driver
  waited for responses before issuing another request. Added a directed queued
  AW/W/AR request under B/R stalls. All 59 assertions then had nonzero hits;
  no RTL change was needed. Saturation uses constant force/release deposits,
  avoiding mixed blocking/nonblocking drivers in Verilator. Actual counts are
  read through AXI, with no verification-only design ports.
- D15: No Verilator/slang executable is installed (R-015); lint and Verilator
  execution are explicitly unverified. Deliver portable source and reproduction
  command; retain Icarus's harmless sensitivity-list overapproximation diagnostic.
