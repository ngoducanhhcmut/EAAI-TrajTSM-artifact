# R6 decisions
Project TSM-X; author TSMX project; version 0.1; date 2026-10-29.

1. Authority: the designer delegates every decision and explicitly authorizes this
   implementation/test scope. This overrides skill R-005/006, module-list approval,
   and any ambiguity escalation in R-026. Only R6-owned paths are written.
   Rules: `.agents/skills/vlsit-asic-ip-microspec/reference/templates/VLSIT_RTL_Design_Rule.md` v2.
   Sources: Moore example, skeletons, TB guide, accepted SEL and arithmetic ABI.
2. Gap scan: G-001..006 are missing template headings 1.1,2.3,7.1,7.3,14.2,14.3.
   Existing spec5.3/5.4/7/14 supplies the functional contract; no functional blocker.
3. ABI request176 = x64,v32,a32,cid8,phase32,limit8, MSB first. Response50 =
   accept1,reason8,stop_valid1,stop32,count8. Reasons use golden REASONS enum:
   ok0,numeric4,range14,horizon16. Stop invalid is valid0,value0.
4. SPEC-ISSUE Row352: the seven declared field widths add to288, while spec9.2
   allocates352. Golden pack_row returns288 bits; pack_trajectory zero-extends
   that integer into352 bits. Follow golden: Row352={zero64,phase32,xlo64,xhi64,
   vlo32,vhi32,midpoint_a32,jerk32}. Do not sign-extend the whole record.
   The preliminary commentary called the table Row288; its field sum is288,
   but its published allocation is352. This decision records the exact distinction.
5. Streaming ports: o_row_valid/i_row_ready/o_row_data[400:0]. Packed data is
   {cid8,epoch32,index8,Row352,last1}. epoch is the supplied original phase,
   copied without inferred wall-clock timestamps; supervisor retains transaction
   ID out of band. index starts0. Rows appear before the next cell computation.
   B3 consumes adjacent rows in increasing index. Terminal metadata follows all
   row handshakes and is held until consumed. No full candidate buffer is needed.
   last1 identifies the appended successful terminal endpoint. A partial horizon
   has no appended endpoint/last; terminal reject and count delimit its rows.
   This avoids predicting completion before the last integration. B3 must keep
   results provisional until terminal accept, as spec10.3 already requires.
6. No accepted request can interleave another context. BOOT suppresses channels
   during reset. Asynchronous reset clears context and private arithmetic tags;
   wrapper owns synchronized release and DFT reset control. Timeout integration
   drains/discards rows AND terminal metadata before reuse; no hidden cancel port.
7. Use exactly one private accepted m_tsmx_arith engine. Query profile start and
   midpoint (opcode5), then floor and ceil continuous advances (opcode7). Engine
   is never edited. Serialized calls trade area/scheduling simplicity for a
   conservative cycle bound still far below1280 per cell. Root search remains
   the accepted arithmetic implementation; no new division, remainder or Python
   behavior is synthesized. There is no ARITH-ISSUE requiring a wrapper.
8. Admission validates encoded signed ranges before arithmetic. Phase equality
   decoder covers0..128 times100000; non-grid values reject range, matching
   golden. phase_alignment is unreachable after golden's own grid guard.
   Adapter type/oversize values cannot be represented on these physical ports;
   FORMATS sentinels and physical minima/maxima are explicitly tested. Ingress
   position range is +/-10000S, velocity0..10S, acceleration-8S..0.
   Invalid inputs never enter arithmetic. Parameter max cells1..128 constrains
   requested limit; default128 preserves golden. All129 endpoints fit count8.
9. Motion details: first cell preserves measured acceleration, including instant
   profiles. At later phases instant start equals midpoint command. Finite jerk
   changes sign when initial acceleration is stronger than the target. Midpoint
   remains golden's command, even when the stop occurs inside that cell. Stop
   first records t+DT when upper velocity becomes0; parking emits at least2s
   hold and a final zero-acceleration/zero-jerk endpoint. No6s/30m truncation.
10. Fault containment: impossible accepted arithmetic guard/overflow fault emits
    numeric reject with already-emitted count/stop; does not authorize a pose.
    Legal B4 ODD positions cannot approach s64 overflow. Overflow-domain input
    positions/sentinels reject range before arithmetic; no wrap/saturation.
11. Verification: full semantic fixtures, legacy hex independently checked with
    vectors.evaluate, all B4 edge rows if present,2200 seeded random cases,
    extrema, just-outside domains, all16 profiles, standstill, upward ramp,
    stop-bracket and horizon corners. Expected rows/terminal come only from
    unmodified golden, compared in full including padding and stream tags.
    edges.ports.jsonl currently has zero B4 rows; this is explicitly counted.
12. Assertions:32 named checks cover reset, invalid zero, channel exclusivity,
    stall stability, every row field, every terminal field and complete payloads.
    Separate sampled-output mutants flip each assertion's observed DUT field,
    avoiding force/X behavior that differs between Icarus and Verilator.
    Functional source mutants independently change jerk, instant start, row
    backpressure and admission. Mutants live only in the TB folder.
13. Style deviations: HIE-02 is justified because this is a functional leaf, not
    the system structural top. PAR-03 warnings reference fixed ABI sign extension
    counts128/96, SI library coefficients2S/4S, DT100000 and operation2. These
    follow golden formulas/ABI rather than configurable physical quantities.
    Grouped next-state/data process is a Moore-example grouping adaptation,
    with a separate output decoder and sequential register process.
14. Resource caveat: accepted arithmetic instantiates paired96/128/160 restoring
    pipelines, six logical dividers per context. Unused widths are structurally
    present; synthesis pruning is unmeasured. This exceeds spec13's estimate of
    two160 dividers/context. Shared ramp xn160, xd136, vn112, vd88 follow R2.
    Multiplier operator cones are reused as-is; no mapped multiplier/DSP or area
    count is claimed. B4 adds fixed library/grid multiplication (constant-foldable).
15. Tool constraint: Icarus12 is available. No Verilator/slang was found. WSL
    enumeration returns access denied. R-015 applies: lint and Verilator5 run are
    unverified; no software installed. Repeat commands are in unit README.md.

16. Debug evidence: initial boundary run caught an off-by-one transcription of
    golden reason IDs (range15/horizon17). Golden REASONS is authoritative:
    range14/horizon16. Corrected RTL constants; no expected value was changed.

17. Mutation audit: deleting the instant midpoint-to-start assignment is
    equivalent because the earlier instant start profile query already returns
    the same target. Its survival is expected, not a coverage hole. The retained
    functional mutant instead assigns measured reg_a at instant start, producing
    a real incorrect instantaneous profile. Sampled-output mutants are distinct
    from these functional source mutants and are reported separately.
