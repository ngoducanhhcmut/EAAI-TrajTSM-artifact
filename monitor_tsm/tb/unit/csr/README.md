TSM-X, TSMX project, version 0.1

From repository root, regenerate and run all verification:

```powershell
$env:PYTHONPATH='tsmx_hw/golden;tsm2_pilot/vendor'
py -3.13 -B tsmx_hw/tb/unit/csr/run.py
```

The script regenerates only local test artifacts, runs baseline Icarus, all 59
individual assertion faults, and eight functional source mutants. Each fault
must produce its own ASSERT_FAIL with nonzero status. Master-interface faults
test the master protocol monitors; source mutants test design behavior.
The independent Python reference consumes the JSON map and uses no CSR RTL.
Every physical output is compared on every cycle. Original fixtures are unchanged.

From this TB directory, Verilator 5 reproduction:

```sh
verilator --binary --timing --assert -Wno-fatal --top-module tb_m_tsmx_csr -I. --Mdir obj_dir ../../../rtl/csr/m_tsmx_csr.sv tb_m_tsmx_csr.sv
./obj_dir/Vtb_m_tsmx_csr
```

Use `obj_dir/Vtb_m_tsmx_csr.exe` on native Windows. The runner automatically
performs this build/run when Verilator is in PATH. No Icarus-only constructs,
VPI, dynamic force indices, or simulator-specific conditional branches are used.
No Verilator executable was found in the delivery environment; compile/run on
that simulator remains unverified. Its baseline requires no fault plusargs.
Four-state no-X mutant tests are demonstrated using Icarus.

CSR has no dedicated golden vector file. gen_vectors.py imports the golden
module constants and converts all system.ports.jsonl rows by semantic name,
checking hex SHA256, acceptance, candidate, mode and reason CRC32. It emits
2400 deterministic random bus operations, every JSON register/access/strobe,
all CSR_UPDATE field extrema, reset aborts, saturation, and explicit W1C races.
Non-CSR FORMATS fields are outside this module's interface.

vectors_summary.json records seed, counts, fixture hash and scenario tags.
assertions.json records each assertion, antecedent, consequent and fault target.
simulation.log records every hit count and the final PASS line.
mutation_summary.json and mutant directories preserve exact failures/replacements.

The Icarus constant-select diagnostic in compile.log concerns sensitivity-list
overapproximation, not an inferred latch or altered behavior. Icarus is not lint.
Lint options for this Windows environment: OSS CAD Suite, MSYS2 Verilator,
WSL Verilator, or Conda Verilator; nothing was installed.
