"""Gom mot ban luu tru cho buoi chay board thanh cong 07/10/2026: nguon, ket qua tong hop, log mo phong, log board."""
import shutil, hashlib, os
from pathlib import Path
R = Path(__file__).resolve().parents[1]
A = R / "LUU_TRU_BOARD_2026-10-07"
def cp(src, dst_dir, rel=None):
    s = R / src
    if not s.exists(): print("  THIEU:", src); return
    d = A / dst_dir / (rel if rel else s.name)
    d.parent.mkdir(parents=True, exist_ok=True)
    if s.is_dir():
        shutil.copytree(s, d, dirs_exist_ok=True, ignore=shutil.ignore_patterns("*.bak*", "__pycache__", "*.o", ".Xil"))
    else: shutil.copy2(s, d)
# ---------------- 01 nguon
for d in ["rtl/include", "rtl/src", "HMAO"]: cp(d, "01_source", d)
for f in ["hw_tsm_only/ocm/hmao_pkg.sv"]: cp(f, "01_source", "board_variants/tsm_ocm/hmao_pkg.sv")
cp("constrain", "01_source", "constrain")
cp("hw_project/planning_hw.srcs/sources_1/bd/system/system.bd", "01_source", "block_design/system.bd")
for f in ["tsm_demo.c", "tsm_multicase.c", "tsm_onecase.c", "traj_demo.c", "demo_golden.h", "multicase_data.h", "onecase_data.h",
          "lscript_r5.ld", "lscript_r5_ocm.ld", "lscript_r5_ocm_small.ld", "gen_demo_payload.py", "gen_multicase_data.py",
          "demo_cases.json", "demo_bank.bin"]:
    cp("sw/board/" + f, "01_source", "firmware_r5/" + f)
cp("sw/payloads/v2", "01_source", "ddr_payload_weights_v2")
for f in ["build_board_v2d.tcl", "ipcache_guard.tcl", "run_build_full_retry.sh", "gen_psu_init_zcu106_sodimm.tcl", "board_build_elf.sh",
          "board_run_demo_zcu106.tcl", "board_rerun_r5_demo.tcl", "board_run_traj_zcu106.tcl", "board_run_tsm_multi_zcu106.tcl",
          "board_run_tsm_ocm_zcu106.tcl", "board_run_tsm_only_zcu106.tcl", "board_run_onecase_zcu106.tcl", "board_verify_ddr.tcl",
          "board_check_bit_freshness.tcl", "board_test_ddr.tcl", "board_test_ddr_deep.tcl", "board_ddr_phy_dump.tcl", "board_read_spd.tcl",
          "board_pl0_freq_rerun.tcl", "board_pl0_sweep.py", "verify_build_tsm_board.ps1", "make_archive_board_0710.py"]:
    cp("scripts/" + f, "01_source", "scripts/" + f)
for f in ["build_tsm_only.tcl", "build_tsm_ocm.tcl", "tsm_only_cdc.xdc", "run_build.sh", "run_build_ocm.sh"]:
    cp("hw_tsm_only/" + f, "01_source", "scripts/tsm_only/" + f)
for d in ["tb/system", "tb/e2e/tb_planning_top_e2e.sv", "tb/integration/tb_hmao_mini_val_73.sv", "tb/integration/tb_hmao_edge_cases.sv"]:
    cp(d, "01_source", d)
for f in ["sim_sysbd/build_bd.tcl", "sim_sysbd/gen_scripts.tcl", "sim_sysbd/gen_sysbd_data.py", "sim_sysbd/data",
          "sim_replay/build_bd.tcl", "sim_replay/gen_scripts.tcl", "sim_replay/gen_replay_data.py", "sim_replay/data",
          "sim_traj/build_bd.tcl"]:
    cp(f, "01_source", "system_sim/" + f)
for f in ["docs/HUONG_DAN_BOARD_0710.md", "docs/TSM_BOARD_FIX_2026_10_06.md", "docs/HUONG_DAN_DEMO_ZCU106.md"]:
    cp(f, "01_source", "docs/" + Path(f).name)
# ---------------- 02 ket qua tong hop / build
for f in ["deliverables/v2d/system_wrapper_v2d.bit", "deliverables/v2d/system_wrapper_v2d.xsa"]: cp(f, "02_synthesis", "full_soc_v2d/" + Path(f).name)
cp("reports/impl_v2d", "02_synthesis", "full_soc_v2d/reports")
cp("hw_project/planning_hw.runs/impl_1/system_wrapper_routed.dcp", "02_synthesis", "full_soc_v2d/system_wrapper_routed.dcp")
cp("reports/board_fix_validation/build_full.log", "02_synthesis", "full_soc_v2d/build_full.log")
for f in ["psu_init_zcu106_ram_x16_8gb.tcl", "psu_init_zcu106.tcl", "psu_init_zcu106_sodimm_x16_8gb.tcl"]:
    cp("deliverables/zcu106/" + f, "02_synthesis", "psu_init/" + f)
cp("deliverables/v2d/psu_init_v2d_components.tcl", "02_synthesis", "psu_init/psu_init_zcu104_preset_components.tcl")
cp("deliverables/tsm_only_ocm", "02_synthesis", "tsm_only_ocm")
cp("deliverables/tsm_only", "02_synthesis", "tsm_only_ddr")
for f in ["vitis_ws_v2d/tsm_demo/Debug/tsm_demo.elf", "vitis_ws_v2d/tsm_only/tsm_multicase.elf", "vitis_ws_v2d/tsm_only/tsm_onecase_ocm.elf",
          "vitis_ws_v2d/traj_demo/traj_demo.elf"]:
    cp(f, "02_synthesis", "firmware_elf/" + Path(f).name)
# ---------------- 03 log board (cac log luu tu dong)
cp("reports/board_fix_validation/demo_full_0710.log", "03_board_results", "full_demo/xsdb_load_and_ddr_verify.log")
cp("reports/board_fix_validation/pl0_sweep.log", "03_board_results", "pl0_frequency_sweep/pl0_sweep_uart.log")
# ---------------- 04 mo phong
S = "04_simulation_results/"
for src, dst in [("sim_sysbd/prj/tsm_sysbd.sim/sim_1/behav/xsim/sysbd_full_fixed.log", "tsm_system_16case_realclock_PASS.log"),
                 ("sim_sysbd/prj/tsm_sysbd.sim/sim_1/behav/xsim/sim_rtl.log", "tsm_system_BEFORE_FIX_0x48.log"),
                 ("sim_sysbd/prj/tsm_sysbd.sim/sim_1/behav/xsim/sim_diag.log", "tsm_system_BEFORE_FIX_9AR_trace.log"),
                 ("sim_sysbd/prj/tsm_sysbd.sim/sim_2/behav/xsim/sim_net.log", "tsm_netlist_BEFORE_FIX_0x48.log"),
                 ("sim_replay/prj/tsm_replay.sim/sim_1/behav/xsim/replay_nobp.log", "tsm_replay_53case_PASS.log"),
                 ("sim_replay/prj/tsm_replay.sim/sim_1/behav/xsim/replay_bp3.log", "tsm_replay_53case_backpressure_PASS.log"),
                 ("sim_traj/prj/traj_sysbd.sim/sim_1/behav/xsim/traj_sysbd.log", "traj_system_smartconnect_PASS.log"),
                 ("reports/hmao_mini_val_73/mini_val_73.log", "tsm_mini_val_219_PASS.log"),
                 ("reports/hmao_edge_cases/edge_cases.log", "tsm_edge_cases_28_PASS.log")]:
    cp(src, S, dst)
print("chep xong")
