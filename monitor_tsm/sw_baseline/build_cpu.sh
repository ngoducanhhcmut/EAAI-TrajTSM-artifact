#!/bin/sh
# Claude 04/11/2026: bare-metal TSM-X software baseline for ZCU106 A53 (EL3, caches on) and R5F (lockstep core 0).
set -eu
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
A=/c/Vivado/Vitis/2023.2/gnu/aarch64/nt/aarch64-none/bin/aarch64-none-elf-gcc.exe
R=/c/Vivado/Vitis/2023.2/gnu/armr5/nt/gcc-arm-none-eabi/bin/armr5-none-eabi-gcc.exe
BA=ws/a53plat/psu_cortexa53_0/standalone_domain/bsp/psu_cortexa53_0
BR="$ROOT/vitis_ws_v2d/v2d_plat/psu_cortexr5_0/standalone_domain/bsp/psu_cortexr5_0"
$A -O2 -Wall -mcpu=cortex-a53 -I$BA/include -c bench.c -o a53_bench.o
$A -O2 -Wall -mcpu=cortex-a53 -I$BA/include -c tsmx_kernel.c -o a53_kernel.o
$A -mcpu=cortex-a53 -Wl,-T,lscript_a53.ld -L$BA/lib -o tsmx_a53.elf a53_bench.o a53_kernel.o -Wl,--start-group,-lxil,-lgcc,-lc,--end-group
RF="-mcpu=cortex-r5 -mfloat-abi=hard -mfpu=vfpv3-d16 -DARMR5 -O2 -Wall"
$R $RF -I"$BR/include" -c bench.c -o r5_bench.o
$R $RF -I"$BR/include" -c tsmx_kernel.c -o r5_kernel.o
$R -mcpu=cortex-r5 -mfloat-abi=hard -mfpu=vfpv3-d16 -Wl,-T,"$ROOT/journalQ1/board_r5/fw/lscript_r5.ld" -L"$BR/lib" -o tsmx_r5.elf r5_bench.o r5_kernel.o -Wl,--start-group,-lxil,-lgcc,-lc,-lm,--end-group
ls -la tsmx_a53.elf tsmx_r5.elf
