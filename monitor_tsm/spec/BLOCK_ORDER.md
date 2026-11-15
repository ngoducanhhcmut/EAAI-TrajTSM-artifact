# TSM-X RTL implementation order

Contract: [TSMX_Design_Specification.md](TSMX_Design_Specification.md), sections 5/9.
Dependencies mean elaborated RTL implementation dependencies, not incoming signals.
All blocks use explicit requests/responses; top owns golden history and immutable
pending/backup records. No agent edits another block's files or golden/verify/vectors.
Unit-test fixture mapping is in each specification subsection. Start with header/ABI
elaboration checks; a G1 fingerprint change requires reviewing affected adapters.

| Block / module | RTL dependencies | Complexity | Parallel wave |
|---|---|---|---:|
| Integer motion / `m_tsmx_arith` | None | L | 1 |
| Packed-record CRC/SHA / `m_tsmx_codec` | None | L | 1 |
| B7 / `m_tsmx_sel` | None | S | 1 |
| B8 / `m_tsmx_supervisor` | None | S | 1 |
| B10 / `m_tsmx_rec` | None | M | 1 |
| CSR / `m_tsmx_csr` | None; workbook is data contract | M | 1 |
| B1 / `m_tsmx_ingress` | Codec verified through top-facing precompute contract | M | 2 |
| B2 / `m_tsmx_splice` | Arithmetic | M | 2 |
| B4 / `m_tsmx_mrmgen` | Arithmetic, private per-instance hardware | L | 2 |
| B3 / `m_tsmx_geom` | Arithmetic, private pipelined hardware | L | 2 |
| B9 / `m_tsmx_cert` | Codec verified through top-facing precompute contract | M | 2 |
| B13 / `m_tsmx_health` | B4 and B3, dedicated BIST instances | M | 3 |
| Authority / `m_tsmx_arb` | B8 and B9 verified semantics | M | 3 |
| Integration / `m_tsmx_top` | All above | L | 4 |

S/M/L are ASSUMPTION-009 effort estimates. Leaf proof/test work can run concurrently.
S1b Wave2: G=8 B4 contexts, P=8 B3 lanes; tagged row streaming B4->B3,
>=35 row slots and32 actor states per lane. Each owns private arithmetic:
s160 B4, s128 rational B3 and s96 integer-time updates. Codec consumes packed
records with zero LSB byte padding, without JSON or decimal conversion.
B3 actor-cell II48 covers both event pieces and all swept points; divider II1.
Wave4 full dual-sweep/helper budget is1,168,034 cycles (6.229515ms); prove
cell1280, drain1536, FIFO/stall bounds and187.5MHz after RTL/synthesis.
Early-out cancels only later candidates within the same golden-ordered sweep.

Suggested file ownership: `rtl/<block>/m_tsmx_<block>.sv` and `tb/unit/<block>/`.
Use canonical module names above, even when directory abbreviations differ.
No RTL is delivered by S1; all test methods listed in the specification are future work.
