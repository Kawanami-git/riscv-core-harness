// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       csr.h
\brief      Low-level CSR access helpers for bare-metal firmware.

\author     Kawanami
\version    1.1
\date       16/05/2026

\details
  Generic low-level helpers to read RISC-V CSRs from bare-metal firmware.

  CSR addresses are encoded as immediates in RISC-V CSR instructions. Therefore,
  the CSR address passed to these helpers must be known at compile time.

\remarks
  - The CSR address must be a compile-time constant.
  - The CSR address definitions below are project-specific.
    When integrating another RISC-V core, update these definitions to match the
    CSRs implemented by the target core.
  - On standard RISC-V cores, reading an unimplemented CSR may raise an illegal
    instruction exception.

\section firmware_csr_h_version_history Version history
| Version | Date       | Author   | Description                         |
|:-------:|:----------:|:---------|:------------------------------------|
| 1.0     | 28/04/2026 | Kawanami | Initial version.                    |
| 1.1     | 16/05/2026 | Kawanami | Add Mhpmcounter5-13.                |
********************************************************************************
*/

#ifndef CSR_H
#define CSR_H

#include <stdint.h>


/// Machine cycle counter CSR address
#define CSR_MCYCLE        0xB00u
/// MHPMCOUNTER_3 CSR address
#define MHPMCOUNTER_3  0xB03u
/// MHPMCOUNTER_4 CSR address
#define MHPMCOUNTER_4  0xB04u
/// MHPMCOUNTER_5 CSR address
#define MHPMCOUNTER_5  0xB05u
/// MHPMCOUNTER_6 CSR address
#define MHPMCOUNTER_6  0xB06u
/// MHPMCOUNTER_7 CSR address
#define MHPMCOUNTER_7  0xB07u
/// MHPMCOUNTER_8 CSR address
#define MHPMCOUNTER_8  0xB08u
/// MHPMCOUNTER_9 CSR address
#define MHPMCOUNTER_9  0xB09u
/// MHPMCOUNTER_10 CSR address
#define MHPMCOUNTER_10  0xB0Au
/// MHPMCOUNTER_11 CSR address
#define MHPMCOUNTER_11  0xB0Bu
/// MHPMCOUNTER_12 CSR address
#define MHPMCOUNTER_12  0xB0Cu
/// MHPMCOUNTER_13 CSR address
#define MHPMCOUNTER_13  0xB0Du



/*!
 * \brief Read a CSR using a compile-time CSR address.
 *
 * \param csr_addr CSR address encoded as a 12-bit immediate.
 *
 * \return CSR value.
 *
 * \note `csr_addr` must be known at compile time.
 */
#define CSR_READ(csr_addr)                    \
  ({                                          \
    uintptr_t value;                          \
    __asm__ volatile("csrr %0, %1"            \
                     : "=r"(value)            \
                     : "i"(csr_addr));        \
    value;                                    \
  })

/*!
 * \brief Generic CSR read helper.
 *
 * \param csr_addr CSR address encoded as a 12-bit immediate.
 *
 * \return CSR value.
 *
 * \note This is a macro, not a function, because RISC-V CSR addresses must be
 *       instruction immediates.
 */
#define csr_read(csr_addr) CSR_READ(csr_addr)

#endif
