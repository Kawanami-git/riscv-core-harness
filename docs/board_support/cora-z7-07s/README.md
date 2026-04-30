# Digilent Cora Z7-07S

This document provides instructions on how to install the tools required to set up the **Cora Z7-07S** development board from **Digilent** for use with the **RISC-V core harness** core. This file only covers tool installation steps. <br> 
To run tests and evaluate the performance of the RISC-V core, please refer to the **README.md** file in the **CORA_Z7_07S** repository of each branches.

> ⚠️ The following instructions were written for **Ubuntu 24.04 LTS**. If you are using another Linux distribution or version, you can still follow the general steps, but you may need to make slight adjustments to install the required dependencies or tools.

> 📝 **Default installation path**  
> The default installation path for **AMD/Xilinx** tools is **/opt/Xilinx/**. This path can be changed in the installation script, but make sure to use the correct paths consistently throughout this tutorial.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Table of Contents

- [Required Hardware](#required-hardware)
- [Required Tools](#required-tools)
- [Xilinx License](#xilinx-license)
- [Known Issues](#known-issues)

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Required Hardware

The following hardware is required to use **RISC-V core harness** with the **Cora Z7-07S**:

- The [Cora Z7-07S](https://digilent.com/reference/programmable-logic/cora-z7/start)
- An Ethernet cable (optional)
- A microSD card rated A1 or A2 (preferably SanDisk), with at least 16 GB of capacity

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Required Tools

To generate a bitstream and a Linux image, the following tools are required:

- [AMD/Xilinx Vivado and Vitis](https://www.xilinx.com/support/download.html): required for FPGA design, place-and-route, bitstream generation and XSA export.

- The Linux **repo, chrpath, diffstat, lz4...** commands: Required to build the Linux image.

- The Linux **dd** command: Required to flash the Linux image onto a SD card.

These tools can be installed using the following Makefile target:

```bash
make install_xilinx_env
```

During installation, valid AMD/Xilinx account credentials may be required. Please provide your account credentials to complete the installation.

> 📝 Installation issues may occur. Please refer to the [Known Issues](#known-issues) section.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Xilinx License

The required Xilinx license is included with the tools. No additional license is required.

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Known Issues

- **Vivado & Vitis installation failures**

Vivado and Vitis installation may occasionally fail while fetching some modules, which can cause the installation to stop.

If this happens, simply rerun the installation process:

```bash
make install_xilinx_env
```
<br>
<br>

---
