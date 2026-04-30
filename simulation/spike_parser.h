// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       spike_parser.h
\brief      Spike log parser (load Spike trace into an in-memory linked list).
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Minimal parser for Spike logs to enable step-by-step comparison against the
  RISC-V DUT. The parser builds a singly linked list of decoded
  instructions with basic metadata (PC, opcode, rd/writeback, memory access).

  Notes:
  - The list is ordered in program order.
  - Non-user addresses (< 0x80000000) are skipped.
  - Parsing stops on the first "ebreak" instruction.
  - The storage is POD + raw allocation for simplicity and speed.

\remarks
  - Lines that do not match the expected Spike formatting are ignored.
  - The resulting list nodes are heap-allocated; use \ref FreeSpike().

\section spike_parser_h_version_history Version history
| Version | Date       | Author     | Description                                |
|:-------:|:----------:|:-----------|:-------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                           |
********************************************************************************
*/

#ifndef SPIKE_PARSER_H
#define SPIKE_PARSER_H

#include <cstddef>
#include <cstdint>
#include <string>

/*!
 * \brief Decoded Spike instruction node (singly linked list).
 */
struct Instr
{
  uint8_t  core;      //!< Core Id (unused: DUT is single-core)
  uint64_t addr;      //!< PC
  uint32_t instr_bin; //!< Binary encoding (32-bit)
  char     instr[32]; //!< Disassembly (truncated if longer)
  int8_t   rd;        //!< Destination register index (-1 if none)
  uint64_t rd_data;   //!< Writeback value for rd (if any)

  uint64_t mem_addr; //!< Memory address for load/store (0 if none)
  uint64_t mem_data; //!< Memory data for load/store (0 if none)

  Instr* next; //!< Next node (nullptr if tail)
};

/*!
 * \brief Spike log container (linked list + optional count).
 */
struct SpikeLog
{
  Instr* instructions; //!< Head of the linked list (nullptr if empty)
  size_t count;        //!< Number of decoded instructions
};

/*!
 * \brief Parse a Spike log file into a linked list.
 *
 * The parser reads \p filename and builds a linked list of \ref Instr nodes
 * inside a \ref SpikeLog structure. Returns nullptr on failure.
 *
 * \param[in] filename  Path to the Spike log file.
 * \return A newly allocated \ref SpikeLog* (ownership to caller), or nullptr.
 */
SpikeLog* ParseSpike(const std::string& filename);

/*!
 * \brief Free memory allocated for a \ref SpikeLog (including its list).
 *
 * Safe to call with nullptr.
 *
 * \param[in] spike  Spike log pointer returned by \ref ParseSpike().
 */
void FreeSpike(SpikeLog* spike);

/*!
 * \brief Utility: print the instruction list to stdout (for debugging).
 *
 * \param[in] head Head pointer of an instruction list (may be nullptr).
 */
void PrintInstrList(const Instr* head);

#endif /* SPIKE_PARSER_H */
