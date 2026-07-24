# TDRV32

**TDRV32 is an open-source, five-stage RV32IMC processor core written in
SystemVerilog.** It is intended for architecture study, RTL verification,
bare-metal software, FPGA prototyping, and open-source ASIC experimentation.

[![CI](https://github.com/tedduy/TDRV32/actions/workflows/ci.yml/badge.svg)](https://github.com/tedduy/TDRV32/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![SystemVerilog](https://img.shields.io/badge/RTL-SystemVerilog-orange.svg)](rtl/logical)
[![RISC-V](https://img.shields.io/badge/ISA-RV32IMC-283272?logo=riscv&logoColor=white)](https://github.com/riscv/riscv-isa-manual)

## Overview

```text
Fetch → Decode → Execute → Memory → Writeback
```

TDRV32 implements a single-issue, in-order pipeline with forwarding, load-use
hazard detection, control-flow recovery, iterative multiplication and division,
and machine-mode system support.

| Area | Support |
| --- | --- |
| ISA | RV32IMC, Zicsr, Zifencei, Zicntr |
| Pipeline | Five-stage, single-issue, in-order |
| Hazards | Data forwarding, load-use stalls, branch and jump flushes |
| System | Machine-mode CSRs, exceptions, interrupts, `MRET`, `WFI` |
| Memory | Separate instruction and data native interfaces |
| Integration | Dual AHB-Lite master wrapper |
| Verification | Commit interface and RVFI |

The primary integration boundaries are:

- `tdrv32_core`: processor core with native instruction and data interfaces.
- `tdrv32_top`: system wrapper exposing dual AHB-Lite master interfaces.
- `tdrv32_pipeline`: five-stage pipeline implementation.

## Quick Start

### Docker

Docker is the recommended environment. Clone the repository and initialize the
FreeRTOS kernel submodule:

```bash
git clone https://github.com/tedduy/TDRV32.git
cd TDRV32
git submodule update --init
make mount
```

Inside the container:

```bash
make doctor
make lint
make test
make formal
make riscv-formal
```

`make mount` pulls `ghcr.io/tedduy/tdrv32:ci-main` when needed and mounts the
repository at `/workspace`.

If the repository was cloned without submodules, initialize them with:

```bash
git submodule update --init
```

### Local toolchain

To install the pinned tools directly in the repository:

```bash
make setup
make doctor
make test
```

## Verification

GitHub Actions validates:

- Repository consistency and Verilator lint.
- Cocotb simulation with Verilator.
- Protocol properties with SymbiYosys.
- ISA-level RVFI checks with `riscv-formal`.
- Bare-metal, Dhrystone, and FreeRTOS firmware execution.

Additional local flows are available:

```bash
make cocotb-iverilog     # Optional simulator compatibility check
make random-regression   # Seeded constrained-random regression
make coverage            # Code and functional coverage
make act4-test           # Generate and run only the ACT4 tests
make synth-yosys         # Yosys synthesis sanity check
```

ACT4 uses the official `ghcr.io/riscv/act4-build:act4` image. Use
`make mount-act4` for an interactive ACT4 shell. Generated ELFs run on TDRV32
with a reusable Verilator simulation binary.

See [verification/README.md](verification/README.md) for the verification plan
and coverage policy.

## Firmware

TDRV32 includes three software workloads:

| Workload | Purpose |
| --- | --- |
| `smoke` | Startup, traps, counters, M extension, and `FENCE.I` |
| `dhrystone` | Integer workload and performance reporting |
| `freertos` | Timer interrupts, task scheduling, and context switching |

Run a workload through Cocotb and Verilator:

```bash
make firmware-run FW_NAME=smoke
make firmware-run FW_NAME=dhrystone FW_MAX_CYCLES=1000000
make firmware-run FW_NAME=freertos FW_MAX_CYCLES=1000000
```

The FreeRTOS kernel is tracked as a Git submodule under
`firmware/freertos/FreeRTOS-Kernel`.

## FPGA and ASIC

The [DE2-115 directory](fpga/de2_115) contains the Intel FPGA integration and
Quartus project files.

Open an OpenLane 2 development shell with:

```bash
make mount-openlane
```

The repository is mounted at `/workspace`; PDK data persists in the
`tdrv32-openlane-pdk` Docker volume.

Run the baseline `sky130A` RTL-to-GDSII flow directly from the host with:

```bash
make openlane
```

The baseline hardens the minimal `tdrv32_asic_wrapper` boundary with the
`sky130_fd_sc_hd` library at a 25 ns clock period and 20% initial core
utilization. Results are written below `asic/openlane/runs/`.

## Repository Structure

```text
rtl/logical/              Synthesizable SystemVerilog RTL
rtl/sdc/                  Timing constraints
verification/cocotb/     Simulation testbench
verification/formal/     Protocol and RVFI formal checks
verification/compliance/ Architectural test configuration
firmware/                Bare-metal, Dhrystone, and FreeRTOS software
fpga/de2_115/            DE2-115 FPGA integration
mk/                      Modular Make targets
scripts/                 Setup and automation utilities
```

Recommended entry points:

- [tdrv32_core.sv](rtl/logical/tdrv32_core.sv)
- [tdrv32_pipeline.sv](rtl/logical/pipeline/tdrv32_pipeline.sv)
- [test_core.py](verification/cocotb/test_core.py)

## Open-Source Toolchain

TDRV32 is developed and verified with
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build),
[Verilator](https://github.com/verilator/verilator),
[Icarus Verilog](https://github.com/steveicarus/iverilog),
[Yosys](https://github.com/YosysHQ/yosys),
[SymbiYosys](https://github.com/YosysHQ/sby),
[Boolector](https://github.com/Boolector/boolector),
[Cocotb](https://github.com/cocotb/cocotb),
[riscv-formal](https://github.com/YosysHQ/riscv-formal),
[RISC-V Architectural Tests](https://github.com/riscv-non-isa/riscv-arch-test),
and [OpenLane 2](https://github.com/efabless/openlane2).

## License

TDRV32 is licensed under the [Apache License 2.0](LICENSE).
