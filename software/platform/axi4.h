// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       axi4.h
\brief      AXI4 memory access interface for the riscv-core-harness test environment.
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Read and write helpers for the AXI4 memory-mapped bus.

  The API is portable across:
  - Simulation (C++): direct memory pokes/peeks.
  - Platform Linux target (C): /dev/mem-style mapping via setup/finalize.

  Only basic single-beat transactions are intended; bursts are not implemented.

\remarks
  - TODO: .

\section axi4_h_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#ifndef AXI4_H
#define AXI4_H

#include <cstdint>

#include "defines.h"

typedef enum class AxiBurst
{
  Fixed = 0b00,
  Incr = 0b01,
  Wrap = 0b10,
  Reserved = 0b11
}AxiBurst;


/*!
 * \brief Prepare the AXI mapping/window for the system reset RAM writes (platform).
 *
 * Sets up the AXI window used to drives the system reset RAM.
 * Should be called before \ref SysResetAxi4Write on the Platform Linux target.
 * In simulation, the implementation may be a no-op.
 *
 * \param[in] start_addr      Absolute AXI base address of the instruction RAM window.
 * \param[in] size            Window size in bytes.
 *
 * \retval SUCCESS            Mapping created successfully.
 * \retval ADDR_NOT_ALIGNED   \p start_addr or \p size is not aligned to 4 bytes.
 * \retval FAILURE            Mapping failed (/dev/mem open or mmap error).
 */
uword_t SetupSysResetAxi4();

/*!
 * \brief Tear down the system reset RAM AXI window previously created.
 *
 * Releases resources created by SetupSysResetAxi4.
 * No-op in simulation.
 */
void FinalizeSysResetAxi4();

/*!
 * \brief System reset module AXI4 write (single-beat style).
 *
 * Performs word-aligned writes to reset/unreset modules in the FPGA. On the platform
 * target, ensure \ref SetupSysResetAxi4 was called beforehand. In simulation, the
 * backend drives the DUT AXI directly.
 * This function allows to drive the reset of the following modules:
 * - scholar_riscv.sv -> SYS_RESET_START_ADDR[0:0].
 *
 * \param[in] addr   Start byte address (AXI space relative to the mapped window).
 * \param[in] data   Pointer to words to write (source buffer). Must be non-null if \p size > 0.
 * \param[in] size   Number of bytes to write (must be a multiple of NB_BYTES_IN_WORD).
 *
 * \retval SUCCESS            Transfer completed.
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not aligned to NB_BYTES_IN_WORD.
 * \retval INVALID_ADDR       AXI window not mapped on platform target.
 * \retval FAILURE            Invalid data pointer or size.
 */
uword_t SysResetAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t size, AxiBurst mode);

/*!
 * \brief System reset module AXI4 read (single-beat style).
 *
 * Reads word-aligned data from the system reset module. On the platform
 * target, ensure \ref SetupSysResetAxi4 was called beforehand. In simulation, the
 * backend drives the DUT AXI directly.
 *
 * \param[in]  addr   Start byte address (AXI space relative to the mapped window).
 * \param[in]  size   Number of bytes to read (must be a multiple of NB_BYTES_IN_WORD).
 * \param[out] data   Destination buffer for read words. Must be non-null if \p size > 0.
 *
 * \retval SUCCESS            Transfer completed (buffer filled).
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not aligned to NB_BYTES_IN_WORD.
 * \retval INVALID_ADDR       AXI window not mapped on platform target.
 * \retval FAILURE            Backend-specific failure.
 */
uword_t SysResetAxi4Read(const uintptr_t addr, uword_t* data, const uword_t size, AxiBurst mode);

/*!
 * \brief Prepare the AXI mapping/window for instruction RAM writes (platform).
 *
 * Sets up the AXI window used to load instruction memory from the host.
 * Should be called before \ref InstrAxi4Write on the Platform Linux target.
 * In simulation, the implementation may be a no-op.
 *
 * \param[in] start_addr  Absolute AXI base address of the instruction RAM window.
 * \param[in] size        Window size in bytes.
 *
 * \retval SUCCESS            Mapping created successfully.
 * \retval ADDR_NOT_ALIGNED   \p start_addr or \p size is not aligned to 4 bytes.
 * \retval FAILURE            Mapping failed (/dev/mem open or mmap error).
 */
uword_t SetupInstrAxi4();

/*!
 * \brief Tear down the instruction RAM AXI window previously created.
 *
 * Releases resources created by SetupInstrAxi4.
 * No-op in simulation.
 */
void FinalizeInstrAxi4();

/*!
 * \brief Write instruction words via the instruction AXI window.
 *
 * This helper specifically targets the instruction memory writer path.
 * On the platform target, \ref SetupInstrAxi4 must have been called first.
 *
 * \param[in] addr   Start byte address (AXI space relative to the instr window).
 * \param[in] data   Pointer to 32-bit words to write (source buffer). Must be non-null if \p size > 0.
 * \param[in] size   Number of bytes to write (must be a multiple of 4).
 *
 * \retval SUCCESS            Transfer completed.
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not 4-byte aligned.
 * \retval INVALID_ADDR       Instruction window not mapped on platform target.
 * \retval FAILURE            Invalid data pointer or size.
 */
uword_t InstrAxi4Write(const uintptr_t addr, const uint32_t* data, const uword_t size, AxiBurst mode);

/*!
 * \brief Read instruction words via the instruction AXI window.
 *
 * This helper specifically targets the instruction memory reader path.
 * On the platform target, \ref SetupInstrAxi4 must have been called first.
 *
 * \param[in]  addr   Start byte address (AXI space relative to the mapped window).
 * \param[in]  size   Number of bytes to read (must be a multiple of 4).
 * \param[out] data   Destination buffer for read words. Must be non-null if \p size > 0.
 *
 * \retval SUCCESS            Transfer completed (buffer filled).
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not aligned to NB_BYTES_IN_WORD.
 * \retval INVALID_ADDR       AXI window not mapped on platform target.
 * \retval FAILURE            Backend-specific failure.
 */
uword_t InstrAxi4Read(const uintptr_t addr, uint32_t* data, const uword_t size, AxiBurst mode);

/*!
 * \brief Map a generic AXI space into the process address space (platform).
 *
 * Must be called before any \ref Axi4Write / \ref Axi4Read on Platform Linux.
 * Not required in simulation (implementation may be a no-op).
 *
 * \param[in] start_addr  Absolute AXI base address of the target window.
 * \param[in] size        Window size in bytes.
 *
 * \retval SUCCESS            Mapping created successfully.
 * \retval ADDR_NOT_ALIGNED   \p start_addr or \p size is not aligned to
 * NB_BYTES_IN_WORD. \retval FAILURE            Mapping failed (/dev/mem open or
 * mmap error).
 */
uword_t SetupDataAxi4();

/*!
 * \brief Unmap AXI space previously mapped by SetupAxi4 (platform).
 *
 * Call once you are done with AXI transactions. No-op in simulation.
 */
void FinalizeDataAxi4();

/*!
 * \brief Write data into the data memory (single-beat style).
 *
 * Performs word-aligned writes to the core data memory. On the platform
 * target, ensure \ref SetupDataAxi4 was called beforehand. In simulation, the
 * backend drives the DUT AXI directly.
 *
 * \param[in] addr   Start byte address (AXI space relative to the mapped window).
 * \param[in] data   Pointer to words to write (source buffer). Must be non-null if \p size > 0.
 * \param[in] size   Number of bytes to write (must be a multiple of NB_BYTES_IN_WORD).
 *
 * \retval SUCCESS            Transfer completed.
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not aligned to NB_BYTES_IN_WORD.
 * \retval INVALID_ADDR       AXI window not mapped on platform target.
 * \retval FAILURE            Invalid data pointer or size.
 */
uword_t DataAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t size, AxiBurst mode);

/*!
 * \brief Read data from the data memory (single-beat style).
 *
 * Reads word-aligned data from the core data memory. On the platform
 * target, ensure \ref SetupDataAxi4 was called beforehand. In simulation, the
 * backend drives the DUT AXI directly.
 *
 * \param[in]  addr   Start byte address (AXI space relative to the mapped window).
 * \param[in]  size   Number of bytes to read (must be a multiple of NB_BYTES_IN_WORD).
 * \param[out] data   Destination buffer for read words. Must be non-null if \p size > 0.
 *
 * \retval SUCCESS            Transfer completed (buffer filled).
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not aligned to NB_BYTES_IN_WORD.
 * \retval INVALID_ADDR       AXI window not mapped on platform target.
 * \retval FAILURE            Backend-specific failure.
 */
uword_t DataAxi4Read(const uintptr_t addr, uword_t* data, const uword_t size, AxiBurst mode);


uword_t SetupPtcAxi4();
void FinalizePtcAxi4();

/*!
 * \brief Write data into the Platform-to-Core shared (single-beat style).
 *
 * Performs word-aligned writes to the Platform-to-Core shared memory.
 * On the platform target, ensure \ref SetupPtcAxi4 was called beforehand.
 * In simulation, the backend drives the DUT AXI directly.
 *
 * \param[in] addr   Start byte address (AXI space relative to the mapped window).
 * \param[in] data   Pointer to words to write (source buffer). Must be non-null if \p size > 0.
 * \param[in] size   Number of bytes to write (must be a multiple of NB_BYTES_IN_WORD).
 *
 * \retval SUCCESS            Transfer completed.
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not aligned to NB_BYTES_IN_WORD.
 * \retval INVALID_ADDR       AXI window not mapped on platform target.
 * \retval FAILURE            Invalid data pointer or size.
 */
uword_t PtcAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t nb_words, AxiBurst mode);

/*!
 * \brief Read data from the Platform-to-Core shared memory (single-beat style).
 *
 * Reads word-aligned data from the Platform-to-Core shared data memory.
 * On the platform target, ensure \ref SetupPtcAxi4 was called beforehand.
 * In simulation, the backend drives the DUT AXI directly.
 *
 * \param[in]  addr   Start byte address (AXI space relative to the mapped window).
 * \param[in]  size   Number of bytes to read (must be a multiple of NB_BYTES_IN_WORD).
 * \param[out] data   Destination buffer for read words. Must be non-null if \p size > 0.
 *
 * \retval SUCCESS            Transfer completed (buffer filled).
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not aligned to NB_BYTES_IN_WORD.
 * \retval INVALID_ADDR       AXI window not mapped on platform target.
 * \retval FAILURE            Backend-specific failure.
 */
uword_t PtcAxi4Read(const uintptr_t addr, uword_t* data, const uword_t nb_words, AxiBurst mode);

uword_t SetupCtpAxi4();
void FinalizeCtpAxi4();

/*!
 * \brief Write data into the Core-to-Platform shared (single-beat style).
 *
 * Performs word-aligned writes to the Core-to-Platform shared memory.
 * On the platform target, ensure \ref SetupCtpAxi4 was called beforehand.
 * In simulation, the backend drives the DUT AXI directly.
 *
 * \param[in] addr   Start byte address (AXI space relative to the mapped window).
 * \param[in] data   Pointer to words to write (source buffer). Must be non-null if \p size > 0.
 * \param[in] size   Number of bytes to write (must be a multiple of NB_BYTES_IN_WORD).
 *
 * \retval SUCCESS            Transfer completed.
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not aligned to NB_BYTES_IN_WORD.
 * \retval INVALID_ADDR       AXI window not mapped on platform target.
 * \retval FAILURE            Invalid data pointer or size.
 */
uword_t CtpAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t nb_words, AxiBurst mode);

/*!
 * \brief Read data from the Core-to-Platform shared memory (single-beat style).
 *
 * Reads word-aligned data from the Core-to-Platform shared data memory.
 * On the platform target, ensure \ref SetupCtpAxi4 was called beforehand.
 * In simulation, the backend drives the DUT AXI directly.
 *
 * \param[in]  addr   Start byte address (AXI space relative to the mapped window).
 * \param[in]  size   Number of bytes to read (must be a multiple of NB_BYTES_IN_WORD).
 * \param[out] data   Destination buffer for read words. Must be non-null if \p size > 0.
 *
 * \retval SUCCESS            Transfer completed (buffer filled).
 * \retval ADDR_NOT_ALIGNED   \p addr or \p size not aligned to NB_BYTES_IN_WORD.
 * \retval INVALID_ADDR       AXI window not mapped on platform target.
 * \retval FAILURE            Backend-specific failure.
 */
uword_t CtpAxi4Read(const uintptr_t addr, uword_t* data, const uword_t nb_words, AxiBurst mode);

#endif
