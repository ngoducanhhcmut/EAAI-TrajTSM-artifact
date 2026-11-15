# VCU118 joint board run — 12/11/2026 (lab remote board, Tailscale)

Board: lab VCU118 (host <lab-host> = <LAB_BOARD_IP>, JTAG-SMT2NC <JTAG_SERIAL>), hw_server 2026.1, xsdb 2023.2 client.
Bitstream: out_joint/system_wrapper_joint.bit (md5 6d5125a84536140fa2c68946c768d4a8, DDR4 preset 083) — DDR4 worked
(14 images, 9.2 MB, readback OK, firmware CRCs = host CRCs). The 062 build is not needed.

**PAPER NUMBERS FROM: uart_20261112_125227.log → results_joint.json (verdict PASS)**
- PASS1 reference replay: 35/35 planner frames bit-exact, 35/35 packets, 207/207 responses, 207/207 command frames.
- PASS2 real time (pipelined planner, bench ACKs + ACK-holding executor): 207/207 responses, 207/207 command types
  equal PASS1, 35/35 frames bit-exact, 15 nominal commands, late jobs 2 (jobs 0,1 at start-up).
- Planner 40.53 ms/frame (PASS1); packet 550 us; request transfer 1300 us; decision 2.66 ms mean (max 7.59);
  response->command 55 us; frame planner-start->command 46.78 ms mean, max 53.65 ms (polling).
- PASS3: ACK withheld on job 42 → brake rose at command age 40,000 us.

Earlier logs of the same day (uart_20261112_1226..1248) are debugging runs with firmware v1..v6; do not cite.

## Findings fixed in firmware/checker only (no RTL change)
1. Planner AXI-Lite read channel (rtl/src/top/planning_top.sv, rvalid_hold, arready=~rvalid) returns the data of the
   read issued 3 reads earlier behind MicroBlaze + SmartConnect (measured with xsdb). Firmware prd(): read 8x, keep
   last. **RTL bug still open — fix needs user approval + rebuild.**
2. Checker DDR CRC used zlib; firmware uses init-0 CRC → checker fixed.
3. Firmware command check compared init-0 CRC with zlib golden → fixed; type/seq now from the FIRST command.
4. PASS2/3 sent none of the 172 bench ACKs → TSM-X stayed on the braking path → ACK replay added.
5. PASS2 started the 40 ms planner at the job time (stale requests) and printed ~23 ms of UART per job → planner
   pipelined with TSM-X jobs, records printed after the pass.
Backups: fw/joint_fw_v1_backup_1211.c / .elf. Manuscript before filling: journalQ1/manuscript_v5_backup_1211_preboard.

## Evidence files (no photos: remote board, no camera access)
- uart_20261112_125227.log — firmware UART output with host timestamps (SHIM_ID, DDRCRC, every job P1/P2/P3 line).
- xsdb_20261112_125235.log — JTAG session of that run: bitstream programming, 14 DDR image loads with readback.
- results_joint.json — checker output (verdict PASS).
- board_identity_20261112_134717.txt — board identity read after the runs: xcvu9p IDCODE 14B31093, Device DNA 4002000001716E884C10C2C5, DONE=1 on all 3 SLRs.
- wipe_20261112_134913.log — data wipe: DDR4 0x80000000+26.5 MB and 0x90000000+18.9 MB overwritten with zeros (spot reads 0), then the
  lab bitstream VCU118_flash_sd_card_remote_tcp_ethernet.bit programmed (our design and on-chip memories gone).
