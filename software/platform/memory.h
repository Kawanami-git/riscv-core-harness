
// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       memory.h
\brief      Thin, safe helpers on top of the AXI4 backend (reads/writes, mailbox)
\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  Convenience functions layered atop axi4.h:
  - Word-aligned DATA reads/writes,
  - 32-bit INSTR writes,
  - Simple shared-memory mailbox (PTC/CTP counters + size handshakes).

  Notes:
  - All \b addresses are interpreted as \b relative to the AXI window mapped
    by the backend (\ref SetupAxi4 / \ref SetupInstrAxi4). If you hold absolute
    addresses, convert to the proper window-relative offset beforehand (or use
    a higher wrapper that does it for you).

\remarks
  - TODO: .

\section memory_h_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 19/12/2025 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#ifndef MEMORY_H
#define MEMORY_H

#include <cstdint>

#include "defines.h"

/*!
 * \brief Write into a memory.
 *
 * This function allows to address all the memories available inside the
 * hardware design.
 *
 * \param[in] addr  Window-relative byte address.
 * \param[in] data  Source buffer (non-null if \p size > 0).
 * \param[in] size  Number of bytes to write.
 *
 * \retval SUCCESS            OK
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size misaligned
 * \retval FAILURE            Invalid addr
 */
uword_t MemWrite(const uintptr_t addr, const uword_t* data, const uword_t size);

/*!
 * \brief Read from a memory.
 *
 * This function allows to address all the memories available inside the
 * hardware design.
 *
 * \param[in]  addr  Window-relative byte address.
 * \param[out] data  Destination buffer (non-null if \p size > 0).
 * \param[in]  size  Number of bytes.
 *
 * \retval SUCCESS            OK
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size misaligned
 * \retval FAILURE            Invalid addr
 */
uword_t MemRead(const uintptr_t addr, uword_t* data, const uword_t size);

/*!
 * \brief Fill a region of the INSTR window with the same 32-bit value.
 *
 * \param[in] addr   Window-relative start address (4B aligned).
 * \param[in] size   Number of bytes (multiple of 4).
 * \param[in] value  32-bit pattern.
 *
 * \retval See InstrMemWrite
 */
uword_t InstrMemReset();

/*!
 * \brief Fill a region of the DATA window with the same word value.
 *
 * \param[in] addr   Window-relative start address (aligned to
 * NB_BYTES_IN_WORD). \param[in] size   Number of bytes (multiple of
 * NB_BYTES_IN_WORD). \param[in] value  Word pattern.
 *
 * \retval See MemWrite
 */
uword_t DataMemReset();

#endif
