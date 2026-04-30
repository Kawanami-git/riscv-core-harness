// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       load.cpp
\brief      Firmware loader for riscv-core-harness (parses addr:data and writes RAM)
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Loads a text firmware file containing lines of the form:
    addr_hex:data_hex

  Addresses may come from SPIKE traces (user-space 0x8... addresses). We
  normalize them into the AXI fabric offset by masking to the lower 24 bits
  (tag + offset) before deciding which RAM to target and performing the write.

  Writes go through the AXI helpers:
    - InstrMemWrite() for the instruction RAM (4B beats),
    - MemWrite()      for the data RAM     (NB_BYTES_IN_WORD beats).

  The function resets the RAMs before programming, and finally releases the
  core reset if no errors occurred.

\remarks
  - Addresses passed to the AXI helpers are **window-relative** (offsets),
    not absolute physical addresses.
  - This loader enforces region membership (INSTR vs DATA). Any address outside
    those ranges is treated as DATA by default, but you may tighten it.

\section load_cpp_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#include "load.h"

#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>

#include "clocks_resets.h"
#include "log.h"
#include "memory.h"

using std::string;

/*------------------------------------------------------------------------------
 * Helpers
 *----------------------------------------------------------------------------*/

/*!
 * \brief Normalize a SPIKE/user-space address into an AXI fabric offset.
 *
 * We keep only the lower 24 bits (tag[23:20] + offset[19:0]) used by the fabric.
 * This makes 0x8___ addresses comparable to our region constants and usable
 * as window-relative offsets for the AXI backends.
 */
static inline uintptr_t NormalizeAxiOffset(uintptr_t a) { return (a & 0x00FFFFFFu); }

/*!
 * \brief Range check with [base, base+size) semantics.
 */
static inline bool InRange(uintptr_t x, uintptr_t base, uintptr_t size)
{
  return (x >= base) && (x < (base + size));
}

/*------------------------------------------------------------------------------
 * Public API
 *----------------------------------------------------------------------------*/

uword_t LoadFirmware(const string& filename)
{
  uword_t addr     = 0;
  uword_t data     = 0;
  uword_t flag     = 0;
  uword_t nbErrors = 0;
  char    line[256];

  LogPrintf("Writing firmware into softcore RAM...\n");

  // Open firmware text file
  std::FILE* f = std::fopen(filename.c_str(), "r");
  if (f == nullptr)
  {
    LogPrintf(
        "Error: unable to open firmware '%s' (%s).\n", filename.c_str(), std::strerror(errno));
    return FAILURE;
  }

  // Platform reset
  {
    uword_t tmp = 0;
    flag        = MemWrite(SYS_RESET_START_ADDR, &tmp, NB_BYTES_IN_WORD);
    if (flag != SUCCESS)
    {
      LogPrintf("Error: write %u bytes @ 0x%u failed, code=" WORD_PRINT_FMT "\n",
                4,
                (uint32_t)SYS_RESET_START_ADDR,
                flag);
      ++nbErrors;
    }
  }

#ifndef SIM
  // Clear both INSTR/DATA memories before programming
  {
    const uword_t zero = 0;
    if (flag= InstrMemReset() != SUCCESS)
    {
      LogPrintf("Error (code %u): failed to reset INSTR RAM.\n", flag);
    }
    if (flag = DataMemReset() != SUCCESS)
    {
      LogPrintf("Error (code %u): failed to reset DATA RAM.\n", flag);
    }
  }
#endif

  // Parse firmware lines: "<addr_hex>:<data_hex>"
  while (std::fgets(line, sizeof(line), f))
  {
    // strip trailing newline
    line[std::strcspn(line, "\n")] = 0;

    // skip blank/comment lines
    if (line[0] == '\0' || line[0] == '#' || (line[0] == '/' && line[1] == '/'))
    {
      continue;
    }

    // parse (WORD_SCAN_FMT uses 32/64 based on XLEN / defines.h)
    if (std::sscanf(line, WORD_SCAN_FMT ":" WORD_SCAN_FMT, &addr, &data) == 2)
    {
      const uintptr_t rel = NormalizeAxiOffset(static_cast<uintptr_t>(addr));

      if (InRange(rel, INSTR_RAM_START_ADDR, INSTR_RAM_SIZE))
      {
        // INSTR region: 4B write
        flag = MemWrite(rel, reinterpret_cast<const uword_t*>(&data), 4);
        if (flag != SUCCESS)
        {
          LogPrintf("Error: write 4 bytes @ 0x" WORD_PRINT_FMT " failed, code=" WORD_PRINT_FMT "\n",
                    (uword_t)rel,
                    flag);
          ++nbErrors;
          continue;
        }
      }
      else if (InRange(rel, DATA_RAM_START_ADDR, DATA_RAM_SIZE))
      {
        // DATA region: full word write (4B on RV32, 8B on RV64)
        flag = MemWrite(rel, &data, NB_BYTES_IN_WORD);
        if (flag != SUCCESS)
        {
          LogPrintf("Error: write %u bytes @ 0x" WORD_PRINT_FMT " failed, code=" WORD_PRINT_FMT
                    "\n",
                    (unsigned)NB_BYTES_IN_WORD,
                    (uword_t)rel,
                    flag);
          ++nbErrors;
          continue;
        }
      }
      else
      {
        // Out-of-known ranges: you can choose to treat as error or fallback.
        // Here we fallback to DATA region semantics.
        LogPrintf("Error: out-of-range write. Address: " WORD_PRINT_FMT " size: %u\n",
                  (uword_t)rel,
                  (unsigned)NB_BYTES_IN_WORD);
        ++nbErrors;
        continue;
      }
    }
    else
    {
      LogPrintf("Parsing error in line: %s\n", line);
      ++nbErrors;
    }
  }
  std::fclose(f);

  // If no error, release core reset
  if (nbErrors == 0)
  {
    uword_t tmp = 1;
    flag        = MemWrite(SYS_RESET_START_ADDR, &tmp, NB_BYTES_IN_WORD);
    if (flag != SUCCESS)
    {
      LogPrintf("Error: write %u bytes @ 0x" WORD_PRINT_FMT " failed, code=" WORD_PRINT_FMT "\n",
                4,
                (uint32_t)SYS_RESET_START_ADDR,
                flag);
      ++nbErrors;
    }
  }

  LogPrintf("Done. Errors: %u\n\n", nbErrors);
  return nbErrors ? FAILURE : SUCCESS;
}
