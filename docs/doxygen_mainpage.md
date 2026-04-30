# RISC-V Core Harness Code Documentation

This documentation describes the internal structure of **riscv-core-harness**.

The goal of this page is to help developers quickly find the relevant source
files, understand how the repository is organized, and identify the main entry
points of the hardware, firmware, simulation, and build flows.

---

## Source Tree Overview {#source_tree_overview}

```text
riscv-core-harness/
├── hardware/
│   ├── common/
│   └── harness/
├── software/
│   ├── firmware/
│   └── platform/
├── simulation/
├── mk/
├── scripts/
├── install/
├── mpfs-discovery-kit/
├── cora-z7-07s/
└── docs/
```

---

## Main Code Areas {#main_code_areas}

| Area | Purpose |
|:-----|:--------|
| [hardware/common](#hardware_common) | Shared RTL packages and interfaces. |
| [hardware/harness](#hardware_harness) | RTL integration environment around the RISC-V core under test. |
| [software/firmware](#software_firmware) | Bare-metal firmware executed by the RISC-V core. |
| [software/platform](#software_platform) | Host-side platform code used by simulation and board flows. |
| [simulation](#simulation_code) | Verilator-based simulation infrastructure. |
| [mk](#makefile_fragments) | Reusable Makefile fragments. |
| [scripts](#project_scripts) | Utility scripts for documentation, formatting, linting, and firmware conversion. |
| [install](#install_scripts) | Environment installation scripts. |
| [mpfs-discovery-kit](#mpfs_support) | Microchip PolarFire SoC / MPFS Discovery Kit support. |
| [cora-z7-07s](#cora_support) | Digilent Cora Z7-07S support. |

---

## Hardware Common Files {#hardware_common}

Path:

```text
hardware/common/
```

This directory contains RTL definitions shared by the harness.

Typical contents:

- `target_pkg.sv`  
  Defines target identifiers used to select target-specific behavior.

- `axi_if.sv`  
  Defines the AXI interface used by the harness integration logic.

Start here if you are looking for shared RTL types, packages, or interfaces used
across the hardware harness.

---

## Hardware Harness {#hardware_harness}

Path:

```text
hardware/harness/
```

This directory contains the RTL environment used to integrate and validate a
RISC-V core.

Important files:

- `riscv_core_harness.sv`  
  Top-level hardware harness. This is the main RTL entry point around the core
  under test.

- `xbar.sv`  
  Address-tag-based memory routing between the core data interface and internal
  memories/FIFOs.

- `dpram.sv`  
  Generic dual-port RAM wrapper.

- `async_fifo.sv`  
  Dual-clock FIFO used for platform-to-core and core-to-platform communication.

- `axi2ram.sv`  
  AXI-to-memory access bridge used by platform-side accesses.

- `sys_reset.sv`  
  Software-visible reset control block.

Start here if you are integrating a new RISC-V core or debugging the hardware
test environment.

---

## Firmware Sources {#software_firmware}

Path:

```text
software/firmware/
```

This directory contains bare-metal firmware executed by the RISC-V core.

Subdirectories:

- `common/`  
  Shared startup code, memory helpers, CSR helpers, and common firmware support.

- `isa/`  
  YAML instruction descriptions used to generate ISA test firmware.

- `loader/`  
  Firmware used to validate basic program loading and execution.

- `echo/`  
  Firmware used to validate communication between the host/platform and the core.

- `cyclemark/`  
  CycleMark benchmark firmware used to estimate core performance.

Start here if you are debugging code that runs on the RISC-V core.

---

## Platform Software {#software_platform}

Path:

```text
software/platform/
```

This directory contains host-side C++ code used to interact with the simulated or
hardware platform.

Typical responsibilities:

- parse command-line arguments,
- load firmware images,
- drive memory-mapped platform accesses,
- communicate with the core through FIFOs,
- collect logs and execution results.

Start here if you are debugging the host-side behavior of simulation or board
communication.

---

## Simulation Code {#simulation_code}

Path:

```text
simulation/
```

This directory contains the Verilator-based simulation infrastructure.

It connects the generated Verilator model with the platform software and allows
the harness to run firmware, ISA tests, and benchmarks.

Start here if you are debugging simulation execution, traces, timeouts, or
platform/model interactions.

---

## Makefile Fragments {#makefile_fragments}

Path:

```text
mk/
```

This directory contains reusable Makefile fragments included by the top-level Makefile.

Important files:

- `Makefile`  
  Generic Makefile template intended to be copied into a parent RISC-V project.

- `common.mk`  
  Common variables, firmware build rules, formatting, linting, and documentation
  targets.

- `isa.mk`  
  ISA string decoding and ISA YAML test selection.

- `sim.mk`  
  Verilator build and simulation targets.

- `install.mk`  
  Installation helper targets.

Start here if you are modifying the build system or adding new validation flows.

---

## Project Scripts {#project_scripts}

Path:

```text
scripts/
```

This directory contains utility scripts used by the harness flow.

Typical script categories:

- Doxygen helpers,
- firmware conversion utilities,
- UART transfer helpers,
- project-specific wrappers.

Some generic formatting/linting utilities may be provided by the `sv-tools`
submodule when enabled.

---

## Install Scripts {#install_scripts}

Path:

```text
install/
```

This directory contains installation scripts for simulation and vendor tool
environments.

Typical install targets include:

- simulation environment,
- Microchip environment,
- AMD/Xilinx environment.

These scripts usually install tools under `/opt` and may require administrator
privileges.

---

## MPFS Discovery Kit Support {#mpfs_support}

Path:

```text
mpfs-discovery-kit/
```

This directory contains support files for the Microchip PolarFire SoC / MPFS
Discovery Kit flow.

Typical contents include:

- Libero project scripts,
- FPGA integration files,
- Linux/Yocto support,
- HSS/bootloader support,
- board-specific Makefile targets.

Start here if you are building or debugging the MPFS Discovery Kit bitstream or
Linux image.

---

## Cora Z7-07S Support {#cora_support}

Path:

```text
cora-z7-07s/
```

This directory contains support files for the Digilent Cora Z7-07S flow.

Typical contents include:

- Vivado project scripts,
- board integration files,
- Xilinx/AMD-specific build helpers.

Start here if you are working on the Zynq/Cora Z7 FPGA flow.

---

## Suggested Reading Order {#suggested_reading_order}

For a new developer, the recommended reading order is:

1. `README.md`  
   Understand the global project structure and purpose.

2. `mk/Makefile`  
   Understand how a parent project integrates the harness.

3. `docs/sim/README.md`  
   Understand how to install the simulation tools and run simulations.

4. `docs/board_support/cora-z7-07s/README.md`  
   Understand how to use this project with the Cora Z7-07S.

5. `docs/board_support/mpfs-discovery-kit/README.md`  
   Understand how to use this project with the MPFS Discovery Kit.

---

## Main Runtime Flows {#main_runtime_flows}

### ISA tests

The ISA flow uses YAML instruction descriptions from:

```text
software/firmware/isa/
```

to generate firmware programs and execute them on the core under test.

### Loader

The loader flow validates that firmware can be loaded into the harness memory
system and executed by the core.

### Echo

The echo flow validates bidirectional communication between the platform and the
RISC-V core through the harness FIFOs.

### CycleMark

The CycleMark flow runs a CoreMark-derived benchmark and reports the number of
cycles required to execute the benchmark workload.

---

## Documentation Notes {#documentation_notes}

This Doxygen documentation is primarily intended for source code navigation.

For general project usage, installation instructions, and quick-start commands,
refer to the repository `README.md`.

For implementation details, prefer starting from the file-level documentation and
then following instantiated module relationships from the generated Doxygen
pages.
