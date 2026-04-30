# RISC-V Core Harness

This repository provides a general-purpose validation environment for RISC-V cores.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Table of Contents

- [License](#license)
- [Overview](#overview)
- [Project Organization](#project-organization)
- [Documentation](#documentation)
- [Dependencies](#dependencies)
- [Limitations](#limitations)
- [Quick Start](#quick-start)
- [Known Issues](#known-issues)

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.

Some files, generated artifacts, or external components used during the build process may come from Xilinx, Digilent, Yocto, Microchip, or other third-party projects. These components remain subject to their respective licenses.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Overview

**riscv-core-harness** is a reusable validation environment for RISC-V cores.

It provides a common infrastructure to run functional tests, ISA tests, firmware programs, and performance benchmarks against a RISC-V core under test.

The environment supports both:

- **simulation-based validation**, using Verilator and Spike,
- **hardware validation**, using supported FPGA development boards.

The goal is to make it easier to integrate, test, compare, and validate different RISC-V core implementations using a shared environment.

`riscv-core-harness` is intended to be integrated from the parent RISC-V project.

The recommended flow is to copy `mk/harness.mk` into your own project root. This
file defines the project-specific paths and includes `riscv-core-harness.mk`,
which exposes all harness targets.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Project Organization

The environment is designed to build, simulate, and validate a **RISC-V** core.

It is primarily intended to be used with **Verilator** for simulation. It provides the hardware harness, firmware, host-side tools, and Makefile flows required to:

- load firmware into instruction and data memories,
- communicate with the core through FIFOs,
- compare execution traces against Spike,
- run functional and benchmark firmware,
- optionally build FPGA bitstreams for supported boards.

Each source file contains a header describing its purpose. This section only provides a high-level overview of the repository structure.

- **docs**  
  Project documentation.

- **hardware**  
  RTL files used by the harness.

  - **common**  
    Common RTL files shared across harness components.

  - **harness**  
    Hardware integration layer around the RISC-V core under test.

- **mk**  
  Makefile fragments included by the top-level Makefile to configure the project, build firmware, run simulations, and launch board-specific flows.

- **scripts**  
  Project scripts used for setup, documentation generation, formatting, linting, and utility flows.

- **simulation**  
  C++-based simulation infrastructure used to:
  - compare the RISC-V core execution against **Spike**,
  - run standalone firmware binaries,
  - evaluate functional correctness and performance.

- **software**  
  Firmware and host-side software.

  - **firmware**  
    Bare-metal firmware intended to run on the RISC-V core.

  - **platform**  
    Host-side software used to communicate with or control the simulation or FPGA platform.

- **sv-tools**  
  Shared utility scripts used for C/C++ formatting, ELF-to-HEX conversion, and related development tasks.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Documentation

Most of the documentation is available under the [docs](./docs/) directory.

The Doxygen documentation can be generated with:

```bash
make documentation
```

The generated documentation is placed in:

```text
docs/doxygen
```

Open `docs/doxygen/html/index.html` to browse the generated documentation.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Dependencies

This project is developed on **Ubuntu 24.04 LTS**.

Other Ubuntu versions may work for **simulation-only** flows, but **Ubuntu 24.04 LTS** is recommended for the full environment, especially for supported FPGA board flows.

<br>
<br>

### Simulation Environment

The simulation environment can be installed with:

```bash
make install_sim_env
```

<br>
<br>

### PolarFire SoC/FPGA — Microchip

The Microchip environment can be installed with:

```bash
make install_microchip_env
```

<br>
<br>

### Cora Z7-07S — Digilent

The AMD/Xilinx environment can be installed with:

```bash
make install_xilinx_env
```

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Limitations

### Core Interface

The harness expects the RISC-V core to expose an OBI interface compatible with the harness integration layer.

If the core uses another bus protocol, a bridge must be implemented between the core interface and the harness memory interface.

<br>
<br>

### Verilog/SystemVerilog Sources

The environment currently supports **Verilog** and **SystemVerilog** RTL source files.

Other HDL languages are not supported by the default flow.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Quick Start

Add **riscv-core-harness** inside your project, either as a regular clone:

```bash
git clone https://github.com/Kawanami-git/riscv-core-harness.git
cd riscv-core-harness
git submodule update --init --recursive
```

or as a Git submodule:

```bash
git submodule add https://github.com/Kawanami-git/riscv-core-harness.git
git submodule update --init --recursive
```

<br>
<br>

Install the simulation environment:

```bash
make install_sim_env
```

Optionally, install one of the supported FPGA tool environments:

```bash
make install_microchip_env
make install_xilinx_env
```

> 📝 **Note:** These installers place tools under `/opt` and require administrator privileges.

<br>
<br>

Copy the generic [harness Makefile template](./mk/Makefile) into your project and configure it for your core.

Your project should then look like this:  
```text
your_project/
├── Makefile
├── riscv-core-harness/
└── your_riscv_core/
```

<br>
<br>

At minimum, set:

```makefile
DUT_DIR = /path/to/your/riscv/core/
ISA     = rv32i_zicntr
```

`DUT_DIR` must point to the directory containing the RTL sources of the RISC-V core under test.

Adapt the core instance inside [riscv_core_harness.sv](./hardware/harness/riscv_core_harness.sv) so that it matches the ports of your RISC-V core.

You can then run the main validation flows.

<br>
<br>

### ISA tests

```bash
make -f harness.mk isa
```

<br>
<br>

### Loader firmware

```bash
make -f harness.mk loader
```

<br>
<br>

### Echo firmware

```bash
make -f harness.mk echo
```

<br>
<br>

### CycleMark benchmark

```bash
make -f harness.mk cyclemark
```

> ⚠️ CycleMark simulation can take a long time. Let it finish normally or time out.

For more information about the simulation environment and board support, see:

- [Simulation documentation](./docs/sim/README.md)
- [Board support documentation](./docs/board_support/)

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Known Issues

No known issue is currently documented in this section.
