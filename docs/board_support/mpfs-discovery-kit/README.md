# Microchip MPFS DISCOVERY KIT

This document provides instructions on how to install the tools required to set up the **MPFS DISCOVERY KIT** development board from **Microchip** for use with the **RISC-V core harness**. This file only covers tool installation steps.<br>

> ⚠️ The following instructions are written for **Ubuntu 24.04 LTS**. If you are using another Linux distribution or version, you can still follow the general steps, but you may need to make slight adjustments to install the required dependencies or tools.

> 📝
>
> **Default tools location** for **Microchip** tools are **/opt/microchip/**. This path can be changed in the installation script, but make sure to consistently use the paths matching your actual **Microchip** installation throughout this tutorial. 

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
- [Microchip License](#microchip-license)
- [Known Issues](#known-issues)

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## **Required Hardware**

The following hardware is required to be able to use the **RISC-V core harness** with the **MPFS DISCOVERY KIT**:
- The [MPFS DISCOVERY KIT](https://www.microchip.com/en-us/development-tool/mpfs-disco-kit)
- An Ethernet cable (optional)
- A class A1 or A2 microSD card (preferably SanDisk) with at least 16GB capacity

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## **Required Tools**
To generate a bitstream, a bootloader and a Linux image, the following tools are required:

-	[Libero SoC Design Suite](https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/fpga/libero-software-later-versions): Required for FPGA design, place & route, bitstream generation, and FPGA/bootloader programming on the board. Be sure to install the full suite.

-	[SoftConsole](https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/soc-fpga/softconsole): Required for HSS compilation.

- The Linux **repo, chrpath, diffstat, lz4...** commands: Required to build the Linux image.

- The Linux **dd** command: Required to flash the Linux image onto a SD card.

These tools can be installed through the Makefile target:
```bash
make install_microchip_env
```

<br>
<br>

---

<br>
<br>
<br>
<br>
<br>

## Microchip License

To use the Microchip tools suite, a Microchip License is necessary.

<br>
<br>

### Get a License

The Microchip License can be requested from their [website](https://www.microchip.com/en-us/products/fpgas-and-plds/fpga-and-soc-design-tools/fpga/licensing) by clicking on **Request a Free License or Register and Manage Licenses** and then **Request Free License**.

The license to take is the **Libero Silver 1Yr Floating License for Windows/Linux Server**:
![Microchip_free_license.png](img/Microchip_free_license.png)

A MAC ID will be asked by Microchip:
![Microchip_mac_id_request.png](img/Microchip_mac_id_request.png)

It can be found by using the following command:
```bash
ip -br link
```

![Microchip_mac_id.png](img/Microchip_mac_id.png)

An example of MAC: ab:ef:12:23:45:cd.

The license will be sent by email.

<br>
<br>

### Install the License

The license must be placed in `/opt/microchip/` (same path as the tools).<br>
If not, the **run_license_daemon.sh** script shall be modified to specify the path of the license file:<br>
`export LICENSE_FILE_DIR=/opt/microchip/` -> `export LICENSE_FILE_DIR=path/to/dir`

The license has to be modified, by replacing **<put.hostname.here>** with your computer name in its top line:<br>
**SERVER <put.hostname.here> abef122345cd 1702**.<br>

You can now switch to one of the available branches, such as **Single-Cycle**.

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

<br>
<br>

---
