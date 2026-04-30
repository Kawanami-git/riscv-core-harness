# Simulation Environment

This document explains how to set up and use the simulation environment for the **RISC-V core harness**.

> 📝 The following instructions were written for **Ubuntu 24.04 LTS**. If you are using another Linux distribution or version, you can still follow the general steps, but you may need to make slight adjustments to install the required dependencies or tools.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Table of Contents

- [Required Tools](#required-tools)
- [The Environment](#the-environment)
- [Running Existing Simulations](#running-existing-simulations)
- [Running Your Own Firmware](#running-your-own-firmware)
- [Known bugs](#known-bugs)

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Required Tools

To successfully run the simulations and tests, the following tools are required:

- **Python 3**: used to convert compiled firmware from `.elf` to `.hex` format with the `makehex.py` script
- **Verilator**: a simulator that translates Verilog code into C++ models; it is used to run the RISC-V core simulation
- **RISC-V GNU Toolchain**: the compiler toolchain required to build software for the RISC-V architecture
- **Spike**: the official simulator for the RISC-V instruction set architecture (ISA); it is used to verify and compare the core behavior against a trusted reference model

These tools can be installed using the provided Makefile target:

```bash
make install_sim_env
```

> 📝 The tools are installed in **/opt**. Therefore, root privileges are required.  

> ⚠️ Verilator preprocessing behavior may vary across versions. To ensure compatibility with the HDL, it is recommended to install Verilator through the provided installation script.  
> Spike log formatting may also vary across versions. To ensure compatibility with the simulation environment, it is recommended to install Spike through the provided installation script.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## The Environment

The provided environment can be used to build and simulate the RISC-V core. It is intended to be used with **Verilator**. It consists of a set of files designed to load firmware into a **RISC-V** instruction and data memories, and to enable communication with the core through fifos.

Users will find, in the header of each file, information about the file's purpose.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Running Existing Simulations

The environment includes preconfigured tests that can be executed easily to validate the functionality and performance of the RISC-V core.

<br>
<br>

### Running ISA Tests

To validate the RISC-V core implementation instruction by instruction, **ISA** tests are provided. These tests perform unit-level checks on each instruction to ensure correct execution.

To run the **ISA** tests, use the following command:

```bash
make isa
```

<br>
<br>

### Running the Loader Test

The loader firmware test is designed to verify the correct loading of firmware into the RISC-V instruction and data memories.

This test also checks the functionality of **eprintf** (embedded `printf`), which writes strings and integer values into shared memory, similarly to a standard `printf`. These messages are then retrieved by the platform software and displayed in the console using a regular `printf`.

To run the loader test, use the following command:

```bash
make loader
```

<br>
<br>

### Running the Echo Test

The echo firmware test is designed to verify communication between the platform software and the RISC-V core through fifos.

From the platform software console, you can input data that will be written into the platform-to-core fifo. The firmware running on the core reads this data and writes it back into the core-to-platform fifo. The platform software then reads and displays the returned data, validating the full communication loop.

To run the echo test, use the following command:

```bash
make echo
```

<br>
<br>

### Running the CycleMark Test

**CycleMark** is based on the **CoreMark** benchmark, which is designed to evaluate the performance of microcontroller-class processors (see [CycleMark Benchmarking](https://github.com/Kawanami-git/SCHOLAR_RISC-V/tree/main/docs/benchmarking/CycleMark)). It provides a standardized and architecture-neutral way to measure how efficiently a processor handles common computational tasks such as list processing, matrix operations, and state-machine control.

To run the **CycleMark** test, use the following command:

```bash
make cyclemark
```

See the [CycleMark Benchmarking](https://github.com/Kawanami-git/SCHOLAR_RISC-V/tree/main/docs/benchmarking/CycleMark) documentation for information on how to analyze **CycleMark** logs.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Running Your Own Firmware

### Create Your Firmware Directory

In the [**firmware**](../software/firmware/) directory, copy the **echo** folder and rename it to match your firmware name.

You can then modify the contents of this directory with your own source files.

<br>
<br>

### The Platform Directory

In the [**platform**](../software/platform/) directory, you will find a **platform.cpp** file, which has two purposes:

- load your firmware into the RISC-V core,
- allow communication by checking `stdin` and displaying messages from the softcore.

This file can be modified, but its existing features are already sufficient to run and communicate with your firmware.

<br>
<br>

### Modify `common.mk`

`common.mk` is available in the [**mk**](../mk/) directory. You can use **echo** as an example.

Locate the following section:

```text
#################################### Directories ####################################
```

Add your firmware directory:

```make
# custom_firmware directory
CUSTOM_FIRMWARE_DIR = $(FIRMWARE_DIR)custom_firmware/
```

Then locate the following section:

```text
#################################### Software Files ####################################
```

Add your firmware files there:

```make
# custom firmware files
CUSTOM_FIRMWARE_FILES = $(CUSTOM_FIRMWARE_DIR)main.c \
                        $(CUSTOM_FIRMWARE_DIR)custom.c
```

Finally, add a target to build your firmware and run the simulation:

```make
# custom firmware target
.PHONY: custom_firmware
custom_firmware: firmware_work
custom_firmware: FIRMWARE_FILES=$(CUSTOM_FIRMWARE_FILES)
custom_firmware: FIRMWARE=custom
custom_firmware: firmware
```

<br>
<br>

### Modify `sim.mk`

The last file to modify is **sim.mk**, also located in the [**mk**](../mk/) directory.

Only one additional target is required. This target will build your firmware and the design under test (by calling `custom_firmware` and `dut`) and then run the simulation.

```make
# Custom target
.PHONY: custom
custom: FIRMWARE=custom_firmware
custom: dut custom_firmware
custom: run
```

You are now ready to use your custom firmware in the simulation environment by running:

```bash
make custom
```

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Known Bugs

No known issue is currently documented in this section.

<br>
<br>

---
