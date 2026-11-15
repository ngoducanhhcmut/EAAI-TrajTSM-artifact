"""Claude 04/11/2026: decode run_cpu_bench.tcl logs (struct ts_out in bench.c) and compare with the hardware.
usage: python parse_cpu.py results/cpu_<time>.log
"""
import re, struct, sys
F32 = ['cpu', 'ncases', 'mism_b4', 'mism_b3', 'mism_sel', 'first_bad_case', 'first_bad_what', 'motion_range']
F64 = ['tick_hz', 'sel_max_ticks', 'sel_sum_ticks', 'sel_max_case', 'full_b4_ticks', 'full_b3_ticks', 'full_rows',
       'full_sweep_ticks', 'full_b4_cyc', 'full_b3_cyc', 'full_sweep_cyc', 'full2_sweep_ticks', 'full2_rows', 'reps']
HW_WORST_CYC = 947263          # TSM-X P=G=2 worst_apos decision (stream sim / board cycle counter)

def main():
    text = open(sys.argv[1], errors='replace').read()
    cores = {}
    for tag, words in re.findall(r'CORE (\S+) wall_ms=\d+ words=(\S+)', text):
        w = [int(x, 16) for x in words.split(',')]
        raw = struct.pack('<37I', *w)
        d = dict(zip(F32, struct.unpack_from('<8I', raw, 0)))
        d.update(zip(F64, struct.unpack_from('<14Q', raw, 32)))
        d['magic'] = struct.unpack_from('<I', raw, 144)[0]
        cores[tag] = d
    hz = cores.get('A53', next(iter(cores.values())))['tick_hz'] or 100_000_000   # same IOU_SCNTRS counter
    for tag, d in cores.items():
        ms = lambda t: t / hz * 1e3
        ok = d['mism_b4'] == d['mism_b3'] == d['mism_sel'] == 0 and d['magic'] == 0x75B0C0DE
        cpu_mhz = d['full_sweep_cyc'] / d['full_sweep_ticks'] * hz / 1e6 if d['full_sweep_ticks'] else 0
        print(f"== {tag}: bit-exact vs golden {'PASS' if ok else 'FAIL'} ({d['ncases']} cases; mism b4/b3/sel "
              f"{d['mism_b4']}/{d['mism_b3']}/{d['mism_sel']}, first bad {d['first_bad_case']}/{d['first_bad_what']}); "
              f"counter {hz/1e6:.3f} MHz, core ~{cpu_mhz:.0f} MHz")
        print(f"   select_world per case: max {ms(d['sel_max_ticks']):.3f} ms, mean {ms(d['sel_sum_ticks'])/d['ncases']:.3f} ms")
        print(f"   one full sweep (16 cand x 32 obj, v=9.8 a=+2, {d['full_rows']} rows): {ms(d['full_sweep_ticks']):.3f} ms "
              f"(B4 {ms(d['full_b4_ticks']):.3f}, B3 {ms(d['full_b3_ticks']):.3f}); two sweeps {2*ms(d['full_sweep_ticks']):.3f} ms")
        print(f"   one full sweep (v=10 a=0, {d['full2_rows']} rows): {ms(d['full2_sweep_ticks']):.3f} ms")
    for mhz in (100, 187.5):
        print(f"HW TSM-X worst decision {HW_WORST_CYC} cycles = {HW_WORST_CYC/mhz/1e3:.3f} ms @ {mhz} MHz")

if __name__ == '__main__':
    main()
