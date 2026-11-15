# W9a2 read-only W9b dump audit

W9b uses `../tb/e2e/results/wp_rtl_s00.txt` through `wp_rtl_s34.txt` (`tsmx_hw/eval_nuscenes/w9b/replay.py:251,265`). Its token map is `../sw/golden_spec/summary.csv:2` through `:36`: 35 consecutive scene-0103 frames, saved RQ1 indices 822 through 856.

These dumps do **not** predate final bert_v2. All 35 files are byte-identical to `../tb/e2e/results/final_35/`. Their local (+07) modification dates are 2026-10-03, except s00/s01/s02 rewritten on 2026-10-04. Per-file UTC dates and SHA256 are in `rtl_dump_audit.json`.

Version evidence: `../reports/unit/e2e_files_f.txt:1` lists `rtl/src/bert_v2/*`, `planning_top.sv`, and `gru_waypoint_decoder.sv`. `../VERIFICATION_HISTORY.md:3018` records the V2 integration/payload; `:3089` records the GRU multi-frame wp_prev reset fix (S_IDLE and S_DONE); `:3114` identifies final timing-fixed RTL and 35/35 successful samples. The five final logs are `../reports/unit/tb_planning_top_e2e_f0.log` through `f4.log`; f0 records 7/7 and exits 2026-10-03. Later s00..02 regressions equal final_35 (`:3164`, `:3197`; `../reports/unit/tb_planning_top_e2e_e2e_r150.log`, `..._r150c.log`). An immutable producing source commit is unavailable.

Recomputed directly from hex words: max absolute difference versus saved `../sw/eval_trainval/out/pred_hw_new.npy` is 0.026161670684814453 m at s16, RQ1 index 838, token `0a0d6b8c2e884134a3b48df43d54c36a`. Against the actual testbench `../tb/e2e/vec/sXX_wp.hex` references the maximum is 0.0000209808349609375 m (20.9808349609375 ?m), consistent with the reported ?21 ?m. The TB loads that reference at `../tb/e2e/tb_planning_top_e2e.sv:254` and writes CSR dumps and CLS error count at `:279`; all 35 CLS error counts are zero.

The 35 token IDs and all 35 masks agree with the trainval dataset, but zero of 35 token arrays are bit-identical (`../sw/golden_spec/sample_XX/input_tokens.bin` versus `../sw/eval_trainval/out/dataset.npz`). Thus the 26.162 mm figure is a cross-artifact comparison with different encoded inputs, not a same-input RTL/GRU error measurement. This audit does not isolate the numerical origin of each differing input or prove that input differences alone explain every waypoint difference. No paper numbers or source artifacts were changed.

|Sample|RQ1 index|Frame token|Dump UTC modification|Max vs saved (m)|
|---|---|---|---|---|
|s00|822|3e8750f331d7499e9b5123e9eb70f2e2|2026-10-03T22:39:38.097545+00:00|1.14440917969e-05|
|s01|823|3950bd41f74548429c0f7700ff3d8269|2026-10-03T19:03:13.411940+00:00|3.81469726562e-06|
|s02|824|c5f58c19249d4137ae063b0e9ecd8b8e|2026-10-03T20:25:41.403181+00:00|2.86102294922e-06|
|s03|825|700c1a25559b4433be532de3475e58a9|2026-10-03T06:56:03.817746+00:00|2.86102294922e-06|
|s04|826|747aa46b9a4641fe90db05d97db2acea|2026-10-03T08:15:31.153341+00:00|0.00839805603027|
|s05|827|f4f86af4da3b49e79497deda5c5f223a|2026-10-03T09:33:10.279913+00:00|3.81469726562e-06|
|s06|828|6832e717621341568c759151b5974512|2026-10-03T10:58:49.635415+00:00|2.09808349609e-05|
|s07|829|c59e60042a8643e899008da2e446acca|2026-10-03T03:02:18.901386+00:00|4.76837158203e-06|
|s08|830|fa65a298c01f44e7a182bbf9e5fe3697|2026-10-03T04:25:25.055878+00:00|1.52587890625e-05|
|s09|831|a98fba72bde9433fb882032d18aedb2e|2026-10-03T05:48:14.714689+00:00|1.33514404297e-05|
|s10|832|b6b0d9f2f2e14a3aaa2c8aedeb1edb69|2026-10-03T07:11:13.892032+00:00|9.53674316406e-06|
|s11|833|796b1988dd254f74bf2fb19ba9c5b8c6|2026-10-03T08:35:02.789832+00:00|9.53674316406e-06|
|s12|834|0d0700a2284e477db876c3ee1d864668|2026-10-03T10:03:35.921399+00:00|0.00643920898438|
|s13|835|de7593d76648450e947ba0c203dee1b0|2026-10-03T11:16:59.149416+00:00|0.0037367939949|
|s14|836|f753d3f87e5b40af87ff2cbf7c8e7082|2026-10-03T02:57:40.084151+00:00|9.53674316406e-07|
|s15|837|b22fa0b3c34f47b6a360b60f35d5d567|2026-10-03T04:15:53.965889+00:00|3.33786010742e-06|
|s16|838|0a0d6b8c2e884134a3b48df43d54c36a|2026-10-03T05:34:04.692096+00:00|0.0261616706848|
|s17|839|8e9c2cba0ee74056aa3746e8391d54a9|2026-10-03T06:50:43.146688+00:00|1.31130218506e-06|
|s18|840|fdc39b23ab4242eda6ec5e1e6574fe33|2026-10-03T08:08:13.194257+00:00|9.53674316406e-07|
|s19|841|9ee4020153674b9e9943d395ff8cfdf3|2026-10-03T09:24:42.615349+00:00|3.33786010742e-06|
|s20|842|5b03af7a953245b5a3b23191ed4da62a|2026-10-03T10:49:31.499729+00:00|0.00214576721191|
|s21|843|d0ecf474e0e64950aa265cd44b9c9d75|2026-10-03T02:58:35.968269+00:00|6.19888305664e-06|
|s22|844|456ec36cb4a44ca78f36fbd90c0c34fa|2026-10-03T04:17:17.191625+00:00|3.81469726562e-06|
|s23|845|6bfd42cf0aba4f1a94ec11fa43e2dd92|2026-10-03T05:35:50.417408+00:00|0.00766086578369|
|s24|846|0af0feb5b1394b928dd13d648de898f5|2026-10-03T06:54:06.173613+00:00|1.90734863281e-06|
|s25|847|61d9340c5ad8418dafe7a4af1b96e6b9|2026-10-03T08:12:47.354866+00:00|3.33786010742e-06|
|s26|848|9e7683e8586542a1b6032980c45f15ce|2026-10-03T09:29:55.041010+00:00|5.72204589844e-06|
|s27|849|cc57c1ea80fe46a7abddfdb15654c872|2026-10-03T10:54:57.240908+00:00|3.81469726562e-06|
|s28|850|4cf5d6c3f6ab42aab23f67b5a9782d1a|2026-10-03T02:58:55.156374+00:00|4.76837158203e-06|
|s29|851|6d9984d09d52479e837da2fd09e192cc|2026-10-03T04:17:35.470160+00:00|0.019434928894|
|s30|852|38a28a3aaf2647f2a8c0e90e31267bf8|2026-10-03T05:36:04.487618+00:00|7.62939453125e-06|
|s31|853|6402fd1ffaf041d0b9162bd92a7ba0a2|2026-10-03T06:54:02.149697+00:00|5.72204589844e-06|
|s32|854|ce94ef7a0522468e81c0e2b3a2f1e12d|2026-10-03T08:11:37.307709+00:00|2.38418579102e-06|
|s33|855|9fcdc52b791045e99c623c5fc643331f|2026-10-03T09:28:08.353337+00:00|1.43051147461e-06|
|s34|856|1c9a906c40f6417bbe1cea06d6e55501|2026-10-03T10:53:40.616858+00:00|3.81469726562e-06|
