// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       memory.h
\brief      Low-level memory & shared-RAM helpers for bare-metal firmware.

\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Minimal primitives to read/write memory-mapped regions and to synchronize
  with the platform via the two shared RAMs:

    - PTC (Platform → Core): the platform publishes messages for the core.
      * Platform increments PTC_PLATFORM_COUNT after writing a message.
      * Core reads the message size at PTC_DATA_SIZE, then data at PTC_DATA.
      * Core acknowledges by incrementing PTC_CORE_COUNT.

    - CTP (Core → Platform): the core publishes messages for the platform.
      * Core increments CTP_CORE_COUNT after writing a message.
      * Platform reads size/data, then acknowledges by incrementing
        CTP_PLATFORM_COUNT.
      * Core is allowed to send a new message when CTP_PLATFORM_COUNT == CTP_CORE_COUNT.

\remarks
  - All addresses and sizes are assumed word-aligned (NB_BYTES_IN_WORD).
  - Use volatile when touching MMIO/shared RAM to avoid compiler reordering.

\section firmware_memory_h_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#ifndef MEMORY_H
#define MEMORY_H

#include <stddef.h>
#include <stdint.h>

#include "defines.h"

/*!
 * \brief Write a byte-size region (word-granular) to memory.
 *
 * \param addr  Byte address to start writing (must be word-aligned).
 * \param data  Pointer to the source words.
 * \param size  Number of bytes to write (multiple of NB_BYTES_IN_WORD).
 */
void MemWrite(uintptr_t addr, const uword_t* data, uword_t size);

/*!
 * \brief Read a byte-size region (word-granular) from memory.
 *
 * \param addr  Byte address to start reading (must be word-aligned).
 * \param data  Pointer to the destination words.
 * \param size  Number of bytes to read (multiple of NB_BYTES_IN_WORD).
 */
void MemRead(uintptr_t addr, uword_t* data, uword_t size);

/*!
 * \brief Embedded printf: format into the CTP shared buffer and notify platform.
 *
 * Supported specifiers: %s, %d, %u, %lu, %x
 *
 * \return Number of characters written.
 */
uword_t Eprintf(const char* fmt, ...);

#endif
