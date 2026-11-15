# VCU118 preparation (Claude, 09/11/2026)

Goal: joint Traj planner + firmware + TSM-X board run on VCU118 (XCVU9P, no ARM -> MicroBlaze) for the
remaining manuscript_v5 pending items (joint run, interface latency, ACK/command delivery, power).
License rule (user, 05/11 + 09/11): the 30-day Enterprise eval is activated ONLY when everything that can be
prepared on the PC is ready. RTL of Traj and TSM-X is frozen (late-ACK edit of 09/11 was reverted; see
../backup_before_ackfix_0911 and memory project_tsmx_hw).

## Done
fw/tsm_fw_packet.{h,c}  firmware core: 8 planner waypoint words (binary32, CSR order) + packet template
                        (seq/snapshot/epochs/ids) -> E2 x/v/a + CRC32 -> 721-bit packet. Port of
                        e2e_traj_tsm/tb_e2e_traj_tsm.sv::firmware_packet. Compile with -ffp-contract=off.
fw/make_fw_testdata.py  35 bench cases -> fw/fw_cases.txt (recorded_wp.mem + vectors.mem packets).
fw/host_test.c          x86 gcc: FW_PACKETS 35/35 bit-exact, frame-7 mutant word changes the packet.
fw/qemu/                same code as MicroBlaze machine code (mb-gcc 12.2, little endian, soft-float binary64,
                        -mxl-barrel-shift -mno-xl-soft-mul) on QEMU petalogix-ml605:
                        "MB_FW_PACKETS 35/35 mutant CHANGED".
  rebuild/run:  cd fw && gcc -O2 -std=c99 -ffp-contract=off -o host_test.exe host_test.c tsm_fw_packet.c -lm && ./host_test.exe
                cd fw/qemu && mb-gcc ... -nostdlib -T link.ld start.S mb_main.c ../tsm_fw_packet.c -lm -lc -lgcc -o mb_fw_test.elf
                qemu-system-microblazeel.exe -M petalogix-ml605 -nographic -serial stdio -monitor none -kernel mb_fw_test.elf

## Done 10/11/2026 (PC side complete except the licensed build)
board/rtl/tsmx_board_shim_v2.v, tsmx_board_top_v2.v  board glue only (m_tsmx_top untouched): CTRL.bit1 1 us time base
        (spec 6.2 sampling), CTRL.bit2 ACK_HOLD (executor keeps ACK present; plans with apply > 40 ms need it),
        0x03C TIME_ACK (time + ACK in one clock, as the reference benches), FREE_CYC / BRAKE_T_US / BRAKE_CYC.
        Unit test tb/board/tb_shim_v2.sv (sim_shim_v2.sh): SHIM_V2 PASS.
build_vcu118_joint.tcl  BD: MicroBlaze 100 MHz (128 KB LMB, MDM debug memory access), DDR4 C1 (board interface,
        VCU118_DDR=083|062 MUST match the board revision), clk_wiz 100/150/300 MHz from the MIG ui_clk, planner
        (150/300 MHz) held in reset by gpio_0 until DDR is loaded, TSM-X 100 MHz + AXIS FIFO, UART, IIC, timer.
        VCU118_STOP=bd validates the BD without a licence: ###BD_OK (10/11). Full build needs the XCVU9P licence.
vcu118_joint.xdc        brake -> GPIO_LED_0 (AT32), heartbeat -> GPIO_LED_1 (AV34).
fw/make_joint_data.py   DDR images from the RTL E2E bench inputs; planner payload MD5 = board-proven 07/10 payload.
fw/joint_fw.c           PASS1 replay of the 207-job E2E sequence (bit-exact checks), PASS2 real-time 1 us time base
        with ACK-holding executor (timing), PASS3 ACK withheld (brake rise age). mb/joint_fw.elf 27 KB (mb-gcc).
        host_joint_test.c on the real images: packets 35/35, splice round-trip 35/35, mutant changes request.
board_run_joint.tcl     xsdb: program, halt MicroBlaze, load + read back DDR images, run firmware.
board_capture.py        UART capture (auto-detects the COM port).   board_check_joint.py  verdict + numbers JSON.
fill_paper_board.py     fills the board \pending items only on verdict PASS (dry run by default).

## Board day (in this order)
1. Activate the licence (user's decision); then: vivado -mode batch -source build_vcu118_joint.tcl  (VCU118_DDR=062
   if the DDR4 C1 chips are MT40A256M16LY-062E). Expect ###BIT; check timing_summary.rpt (WNS>=0).
2. Rebuild firmware if anything changed: see mb-gcc line in fw/mb (same flags as the QEMU build, -T mb/lmb.ld).
3. Board: USB-JTAG cable and USB-UART cable (connector names in UG1224), power on. Start:  python board_capture.py
4. In another shell:  C:/Vivado/Vivado/2023.2/bin/xsdb.bat board_run_joint.tcl
5. When the capture prints JOINT_DONE:  python board_check_joint.py board_logs/uart_*.log
6. Power (optional): read VCCINT (and other rails) idle and while PASS2 runs with the board system controller
   power readout (see UG1224 for the VCU118 System Controller UI); write power.json by hand.
7. python fill_paper_board.py board_logs/results_joint.json [--power power.json]   (dry run) then add --apply,
   rebuild manuscript_v5 (main -> bridge -> supplementary -> bridge -> main) and merge.

## Blocked on the user
- (resolved 10/11) Vivado Enterprise device support installed: xcvu9p 70 parts, board vcu118 2.0/2.3/2.4.
  Installing devices is free and does not use the license; needed for the block design (MicroBlaze, MIG DDR4,
  UART, JTAG-to-AXI, AXI IIC for power), IP generation and behavioural system simulation.
- License source: VCU118 kit voucher / lab licence vs. 30-day eval shared with BEV.

## Bitstream built 11/11/2026 (licence active since 10/11, eval expires 09-jan-2027)
out_joint/system_wrapper_joint.bit (md5 6d5125a84536140fa2c68946c768d4a8) + system_wrapper_joint.xsa, DDR4 C1 = 083 variant.
Routed timing: WNS +0.006 ns, WHS +0.010 ns ("All user specified timing constraints are met"). 323,766 LUT (27.4 %),
314,579 FF, 281.5 BRAM36, 72 URAM; vectorless power estimate 7.19 W (4.65 W dynamic).
History: unconstrained placement put the design in SLR0/SLR2 with SLR1 empty (DDR4 C1 is in SLR2, banks 71/72) ->
routed WNS -2.97 ns (reports in impl_try1_reports/). Fixed by vcu118_floorplan.tcl (MIG+planner SLR2, TSM-X+MicroBlaze
SLR1) + Explore/AggressiveExplore directives; now also in build_vcu118_joint.tcl. Synthesis runs serially (-jobs 1:
TSM-X synth peaks 16 GB). If the board's DDR4 is the 062 variant: VCU118_DDR=062 full rebuild (~10-12 h on this PC).
Windows Update rebooted the PC mid-build once (11/11 11:00): pause updates before long builds.

## LAB REMOTE BOARD (12/11/2026) — supersedes the local steps 3-4 above
Lab docs: vla_new_arch/VCU118/README_Remote_VCU118 (1).md. Access ONLY: hw_server <LAB_BOARD_IP>:3122 (JTAG serial
<JTAG_SERIAL>, xcvu9p_0, 15 MHz) and raw TCP UART <LAB_BOARD_IP>:4002 (115200 8N1, ONE client at a time). No SSH/file copy.
UART pins AW25 (RX) / BB21 (TX) match our board-file 2.4 rs232_uart. Lab preset is board part 3.0 (not installed here; our
build uses 2.4) -> DDR4 C1 variant unknown: ask the lab admin for the C1 chip marking (MT40A256M16GE-083E vs
MT40A256M16LY-062E). Bitstreams: out_joint/ (083, timing met 11/11) and out_joint_062/ (062, build launched 12/11).
Board day (remote):
 0. Install Tailscale, get lab access; check: Test-NetConnection <LAB_BOARD_IP> -Port 3122 / 4002 -> True.
 1. python board_capture.py            (connects to <LAB_BOARD_IP>:4002; close any other UART client first)
 2. [set VCU118_DDR=062 if needed]  C:/Vivado/Vivado/2023.2/bin/xsdb.bat board_run_joint.tcl
    (connects tcp:<LAB_BOARD_IP>:3122; if the 2023.2 xsdb cannot talk to the host's 2026.1 hw_server, install the free
     Vivado Lab Edition 2026.1 and run its xsdb instead)
 3. python board_check_joint.py board_logs/uart_*.log ; python fill_paper_board.py board_logs/results_joint.json [--apply]
Rail power: no remote power readout is available -> fill_paper_board.py writes "Rail power was not measured."
DDR loading goes over remote JTAG (MDM debug memory access, ~9 MB): expect minutes; not tested yet over Tailscale.
