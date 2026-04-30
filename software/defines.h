// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       defines.h
\brief      Global constants and memory map for the test environment.
\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  This file provides shared definitions used throughout the riscv-core-harness
  test environment.
  It includes return codes, address boundaries, memory sizes, and AXI mapping
  for the simulation and hardware platforms (e.g., PolarFire SoC/FPGA).

  Constants defined in this file ensure consistency across simulation, firmware,
  and runtime components. Key system-level values include:
    - Standard return/error codes
    - PolarFire SoC/FPGA FIC (Fabric Interface Controller) regions
    - Tag encoding/decoding for FPGA memory map
    - RISC-V core RAM base addresses and sizes
    - Shared memory regions for platform/core communication (PTC/CTP)

\remarks
  - TODO: .

\section defines_h_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#ifndef DEFINES_H
#define DEFINES_H

#include <stdint.h>

/******************** RETURN CODES ********************/
/// Successful operation
#define SUCCESS 0x00
/// Operation failure
#define FAILURE 0x01
/// Unaligned address
#define ADDR_NOT_ALIGNED 0x02
/// Out-of-bounds address
#define INVALID_ADDR 0x03
/// Unaligned size
#define INVALID_SIZE 0x04
/// Address + size exceeds bounds
#define OVERFLOW 0x05

/******************** ARCHITECTURE WIDTH ********************/
#ifdef XLEN32
/// Size of a word (32-bit)
typedef int32_t word_t;
/// Size of an unsigned word (32-bit)
typedef uint32_t uword_t;
/// Word-aligned address granularity (32-bit)
#define ADDR_OFFSET 0b11
/// Number of bytes in a word (32-bit)
#define NB_BYTES_IN_WORD 0x00000004
/// Format used to scan 32-bit words
#define WORD_SCAN_FMT "%x"
/// Format used to print a 32-bit word
#define WORD_PRINT_FMT "%08x"
#endif

#ifdef XLEN64
/// Size of a word (64-bit)
typedef int64_t word_t;
/// Size of an unsigned word (64-bit)
typedef uint64_t uword_t;
/// Word-aligned address granularity (64-bit)
#define ADDR_OFFSET 0b111
/// Number of bytes in a word (64-bit)
#define NB_BYTES_IN_WORD 0x00000008
/// Format used to scan 64-bit words
#define WORD_SCAN_FMT "%lx"
/// Format used to print a 64-bit word
#define WORD_PRINT_FMT "%016lx"
#endif

/******************** POLARFIRE FIC WINDOWS ********************/
/// FIC0 AXI4 start address (PolarFire SoC/FPGA)
#define FIC0_START_ADDR 0x60000000
/// Number of addressable bytes for the AXI4 (PolarFire SoC/FPGA)
#define FIC0_SIZE 0x20000000
/// AXI4 start address (PolarFire SoC/FPGA)
#define FIC1_START_ADDR 0xe0000000
/// Number of addressable bytes for the AXI4 (PolarFire SoC/FPGA)
#define FIC1_SIZE 0x20000000

/******************** FPGA FABRIC: TOP-LEVEL TAGGING ********************/
/// Most significant bit of the address used to select memories inside the FPGA
#define FPGA_FABRIC_TAG_MSB 23
/// Least significant bit of the address used to select memories inside the FPGA
#define FPGA_FABRIC_TAG_LSB 20

/******************** SYSTEM RESET REGION ********************/
/// Tag value used to identify memory-mapped regions belonging to SYS RESET
#define SYS_RESET_TAG 0b0000
/// SYS RESET memory regions start address
#define SYS_RESET_START_ADDR (SYS_RESET_TAG << FPGA_FABRIC_TAG_LSB)
/// SYS RESET memory depth
#define SYS_RESET_RAM_DEPTH 2
/// SYS RESET memory depth
#define SYS_RESET_RAM_SIZE (SYS_RESET_RAM_DEPTH * NB_BYTES_IN_WORD)
/// SYS RESET memory regions end address
#define SYS_RESET_END_ADDR (SYS_RESET_START_ADDR + SYS_RESET_RAM_SIZE - NB_BYTES_IN_WORD)

/******************** SOFTCORE : SECOND-LEVEL TAGGING ********************/
/// Tag value used to identify memory-mapped regions related to the softcore
#define SOFTCORE_TAG 0b0001
/// SOFTCORE memory regions start address
#define SOFTCORE_START_ADDR (SOFTCORE_TAG << FPGA_FABRIC_TAG_LSB)
/// Most significant bit of the tag field used to address memory-mapped regions related to the SOFTCORE
#define SOFTCORE_TAG_MSB 19
/// Least significant bit of the tag field used to address memory-mapped regions related to the SOFTCORE
#define SOFTCORE_TAG_LSB 16

/******************** INSTR RAM ********************/
/// Tag value identifying the SOFTCORE instruction memory region
#define INSTR_RAM_TAG 0b0000
/// Start address of the SOFTCORE instruction memory region
#define INSTR_RAM_START_ADDR (SOFTCORE_START_ADDR + (INSTR_RAM_TAG << SOFTCORE_TAG_LSB))
/// Depth of the SOFTCORE instruction memory region (in words)
#define INSTR_RAM_DEPTH 4096
/// Size of the SOFTCORE instruction memory region (in bytes)
#define INSTR_RAM_SIZE (INSTR_RAM_DEPTH * 4)
/// End address of the SOFTCORE instruction memory region
#define INSTR_RAM_END_ADDR (INSTR_RAM_START_ADDR + INSTR_RAM_SIZE - 4)

/******************** DATA RAM ********************/
/// Tag value identifying the SOFTCORE data memory region
#define DATA_RAM_TAG 0b0100
/// Start address of the SOFTCORE data memory region
#define DATA_RAM_START_ADDR \
  (SOFTCORE_START_ADDR + (DATA_RAM_TAG << SOFTCORE_TAG_LSB))
/// Depth of the SOFTCORE data memory region (in words)
#define DATA_RAM_DEPTH 4096
/// Size of the SOFTCORE data memory region (in bytes)
#define DATA_RAM_SIZE (DATA_RAM_DEPTH * NB_BYTES_IN_WORD)
/// End address of the SOFTCORE data memory region
#define DATA_RAM_END_ADDR (DATA_RAM_START_ADDR + DATA_RAM_SIZE - NB_BYTES_IN_WORD)

/******************** PTC FIFO ********************/
/// Tag value identifying the SOFTCORE platform-to-core FIFO
#define PTC_FIFO_TAG 0b0101
/// Start address of the SOFTCORE platform-to-core FIFO
#define PTC_FIFO_START_ADDR (SOFTCORE_START_ADDR + (PTC_FIFO_TAG << SOFTCORE_TAG_LSB))
/// Depth of the SOFTCORE platform-to-core FIFO
#define PTC_FIFO_DEPTH 4095
/// Size of the SOFTCORE platform-to-core FIFO
#define PTC_FIFO_SIZE (2 * NB_BYTES_IN_WORD)
/// Platform-to-core FIFO status register address
#define PTC_FIFO_STATUS_ADDR (PTC_FIFO_START_ADDR)
/// Platform-to-core FIFO data address
#define PTC_FIFO_DATA_ADDR (PTC_FIFO_STATUS_ADDR + NB_BYTES_IN_WORD)

/******************** CTP FIFO ********************/
/// Tag value identifying the SOFTCORE core-to-platform FIFO
#define CTP_FIFO_TAG 0b0110
/// Start address of the SOFTCORE core-to-platform FIFO
#define CTP_FIFO_START_ADDR (SOFTCORE_START_ADDR + (CTP_FIFO_TAG << SOFTCORE_TAG_LSB))
/// Depth of the SOFTCORE core-to-platform FIFO (in words)
#define CTP_FIFO_DEPTH 4095
/// Size of the SOFTCORE core-to-platform FIFO (in bytes)
#define CTP_FIFO_SIZE (2 * NB_BYTES_IN_WORD)
/// Core-to-platform FIFO status register address
#define CTP_FIFO_STATUS_ADDR (CTP_FIFO_START_ADDR)
/// Core-to-platform FIFO data address
#define CTP_FIFO_DATA_ADDR (CTP_FIFO_STATUS_ADDR + NB_BYTES_IN_WORD)


#endif
