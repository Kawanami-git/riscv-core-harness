// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       load.h
\brief      Firmware loader API for riscv-core-harness (addr:data textual format)
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Public API to load a textual firmware file into the riscv-core-harness memories.

  The file format is one line per word:
    addr_hex:data_hex

  Addresses possibly coming from SPIKE (user-space 0x8...) are normalized into
  the AXI fabric **offset** by masking to the lower 24 bits (tag + offset)
  before region dispatch (INSTR vs DATA). Writes are then performed through the
  AXI helpers provided by \ref memory.h.

  The loader:
  - Resets INSTR/DATA RAMs before programming,
  - Parses the firmware and performs aligned writes,
  - Releases core reset if and only if no error occurred.

\remarks
  - Addresses passed to AXI helpers are **window-relative offsets**, not
    absolute physical addresses.
  - Lines that cannot be parsed or addresses out of the expected ranges are
    counted as errors and prevent reset release.

\section load_h_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#ifndef LOAD_H
#define LOAD_H

#include <string>

#include "defines.h"

/*!
 * \brief Load a firmware text file into the riscv-core-harness INSTR/DATA memories.
 *
 * The file must contain lines of the form "<addr_hex>:<data_hex>".
 * Each line programs either the instruction RAM (4 bytes) or the data RAM
 * (NB_BYTES_IN_WORD), depending on the normalized AXI offset region.
 *
 * - INSTR region: 4-byte writes via \ref InstrMemWrite
 * - DATA  region: word-wide writes via \ref MemWrite
 *
 * Resets both memories before programming and, if no error occurs, releases
 * the core reset at the end.
 *
 * \param[in] filename  Path to the firmware file.
 *
 * \return
 *  - \ref SUCCESS on success (no errors encountered),
 *  - \ref FAILURE on failure (I/O error, parse error, out-of-range address, or
 *    any write failure).
 */
uword_t LoadFirmware(const std::string& filename);

#endif
