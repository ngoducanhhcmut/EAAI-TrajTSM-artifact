#!/bin/sh
# board_build_elf.sh — build tsm_demo.elf truc tiep bang armr5 gcc + BSP da sinh boi board_build_app.tcl
# (dung khi xsct 'app create' khong ket noi duoc may chu Vitis — loi getsdkchan).
#   sh scripts/board_build_elf.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
GCC=/c/Vivado/Vitis/2023.2/gnu/armr5/nt/gcc-arm-none-eabi/bin/armr5-none-eabi-gcc.exe
BSP=$ROOT/vitis_ws_v2d/v2d_plat/psu_cortexr5_0/standalone_domain/bsp/psu_cortexr5_0
OUT=$ROOT/vitis_ws_v2d/tsm_demo/Debug
mkdir -p "$OUT"
"$GCC" -mcpu=cortex-r5 -mfloat-abi=hard -mfpu=vfpv3-d16 -DARMR5 -O2 -Wall -Wextra \
  -I"$BSP/include" -I"$ROOT/sw/board" -c "$ROOT/sw/board/tsm_demo.c" -o "$OUT/tsm_demo.o"
"$GCC" -mcpu=cortex-r5 -mfloat-abi=hard -mfpu=vfpv3-d16 -Wl,-T,"$ROOT/sw/board/lscript_r5.ld" \
  -L"$BSP/lib" -o "$OUT/tsm_demo.elf" "$OUT/tsm_demo.o" \
  -Wl,--start-group,-lxil,-lgcc,-lc,-lm,--end-group
echo "###ELF $OUT/tsm_demo.elf"
