// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       fifo.h
\brief      Low-level FIFOs access helpers for platform-side software

\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Minimal primitives to read/write memory-mapped FIFOs from the platform-side
  microprocessor.

  The platform-to-core FIFO is written by the platform and read by the softcore.
  The core-to-platform FIFO is written by the softcore and read by the platform.

  Register map:
  - Status register:
    - bit  0     : empty
    - bit  1     : full
    - bits  7:2  : reserved
    - bits 19:8  : rcount[11:0], readable word count
    - bits 31:20 : wcount[11:0], writable word count

\remarks
  - TODO: Link this file to the specification.
  - These helpers do not perform bounds or readiness checks before data
    transfers. The caller must check readable/writable counts before calling
    PtcFifoWrite() or CtpFifoRead().

\section platform_fifo_h_version_history Version history
| Version | Date       | Author       | Description                                |
|:-------:|:----------:|:-------------|:-------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami     | Initial platform-side version.             |
********************************************************************************
*/

#ifndef FIFO_H
#define FIFO_H

#include <stdint.h>

#include "defines.h"
#include "axi4.h"

/// Mask for the FIFO empty status bit.
#define FIFO_EMPTY_MASK      0x00000001u
/// Mask for the FIFO full status bit.
#define FIFO_FULL_MASK       0x00000002u
/// Shift of the FIFO read-side count field in the status register.
#define FIFO_RCOUNT_SHIFT    8u
/// Shift of the FIFO write-side count field in the status register.
#define FIFO_WCOUNT_SHIFT    20u
/// Mask used to extract a FIFO count field after shifting.
#define FIFO_COUNT_MASK      0x00000fffu

/*!
 * \brief Read the status register of the platform-to-core FIFO.
 *
 * \return Current value of the platform-to-core FIFO status register.
 */
static inline uword_t PtcFifoStatus(void)
{
  uword_t status = 0u;

  PtcAxi4Read(
      PTC_FIFO_STATUS_ADDR,
      &status,
      1,
      AxiBurst::Fixed
  );

  return status;
}

/*!
 * \brief Read the status register of the core-to-platform FIFO.
 *
 * \return Current value of the core-to-platform FIFO status register.
 */
static inline uword_t CtpFifoStatus(void)
{
  uword_t status = 0u;

  CtpAxi4Read(
      CTP_FIFO_STATUS_ADDR,
      &status,
      1,
      AxiBurst::Fixed
  );

  return status;
}

/*!
 * \brief Write data into the platform-to-core data FIFO.
 *
 * \param[in] data      Pointer to the buffer containing the data to write.
 * \param[in] nb_words  Number of words to write into the FIFO.
 *
 * \return SUCCESS if the write operation completes.
 *
 * \warning
 *   This function does not check whether enough free slots are available. The
 *   caller must check PtcFifoWcount() before calling this function.
 */
static inline uword_t PtcFifoWrite(const uword_t* data, uword_t nb_words)
{
  for (uword_t i = 0u; i < nb_words; i++) {
    PtcAxi4Write(
        PTC_FIFO_DATA_ADDR,
        &data[i],
        1,
        AxiBurst::Fixed
    );
  }

  return SUCCESS;
}

/*!
 * \brief Read data available in the core-to-platform data FIFO.
 *
 * \param[out] data      Pointer to the buffer where read data will be stored.
 * \param[in]  nb_words  Number of words to read from the FIFO.
 *
 * \return SUCCESS if the read operation completes.
 *
 * \warning
 *   This function does not check whether enough words are available. The caller
 *   must check CtpFifoRcount() before calling this function.
 */
static inline uword_t CtpFifoRead(uword_t* data, uword_t nb_words)
{
  for (uword_t i = 0u; i < nb_words; i++) {
    CtpAxi4Read(
        CTP_FIFO_DATA_ADDR,
        &data[i],
        1,
        AxiBurst::Fixed
    );
  }

  return SUCCESS;
}

/*!
 * \brief Check whether a FIFO status value indicates an empty FIFO.
 *
 * \param[in] status FIFO status register value.
 *
 * \return 1 if FIFO is empty, 0 otherwise.
 */
static inline uword_t FifoStatusEmpty(uword_t status)
{
  return (status & FIFO_EMPTY_MASK) != 0u;
}

/*!
 * \brief Check whether a FIFO status value indicates a full FIFO.
 *
 * \param[in] status FIFO status register value.
 *
 * \return 1 if FIFO is full, 0 otherwise.
 */
static inline uword_t FifoStatusFull(uword_t status)
{
  return (status & FIFO_FULL_MASK) != 0u;
}

/*!
 * \brief Extract readable word count from a FIFO status value.
 *
 * \param[in] status FIFO status register value.
 *
 * \return Number of readable words.
 */
static inline uword_t FifoStatusRcount(uword_t status)
{
  return (status >> FIFO_RCOUNT_SHIFT) & FIFO_COUNT_MASK;
}

/*!
 * \brief Extract writable word count from a FIFO status value.
 *
 * \param[in] status FIFO status register value.
 *
 * \return Number of writable words.
 */
static inline uword_t FifoStatusWcount(uword_t status)
{
  return (status >> FIFO_WCOUNT_SHIFT) & FIFO_COUNT_MASK;
}

/*!
 * \brief Check whether the platform-to-core FIFO is full.
 *
 * \return 1 if FIFO is full, 0 otherwise.
 */
static inline uword_t PtcFifoFull(void)
{
  return FifoStatusFull(PtcFifoStatus());
}

/*!
 * \brief Returns the number of free slots in the platform-to-core FIFO.
 *
 * \return Number of writable words.
 */
static inline uword_t PtcFifoWcount(void)
{
  return FifoStatusWcount(PtcFifoStatus());
}

/*!
 * \brief Check whether at least nb_words can be written to the platform-to-core FIFO.
 *
 * \param[in] nb_words Number of words requested.
 *
 * \return 1 if enough free slots are available, 0 otherwise.
 */
static inline uword_t PtcFifoWriteReady(uword_t nb_words)
{
  uword_t status = PtcFifoStatus();

  if (FifoStatusFull(status)) {
    return 0u;
  }

  return FifoStatusWcount(status) >= nb_words;
}

/*!
 * \brief Check whether the core-to-platform FIFO is empty.
 *
 * \return 1 if FIFO is empty, 0 otherwise.
 */
static inline uword_t CtpFifoEmpty(void)
{
  return FifoStatusEmpty(CtpFifoStatus());
}

/*!
 * \brief Returns the number of available words in the core-to-platform FIFO.
 *
 * \return Number of readable words.
 */
static inline uword_t CtpFifoRcount(void)
{
  return FifoStatusRcount(CtpFifoStatus());
}

/*!
 * \brief Check whether at least nb_words can be read from the core-to-platform FIFO.
 *
 * \param[in] nb_words Number of words requested.
 *
 * \return 1 if enough words are available, 0 otherwise.
 */
static inline uword_t CtpFifoReadReady(uword_t nb_words)
{
  uword_t status = CtpFifoStatus();

  if (FifoStatusEmpty(status)) {
    return 0u;
  }

  return FifoStatusRcount(status) >= nb_words;
}

#endif
