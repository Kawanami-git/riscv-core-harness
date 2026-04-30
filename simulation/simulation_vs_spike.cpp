// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       simulation_vs_spike.cpp
\brief      ISA-level simulation against Spike golden trace
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  This program:
  - parses a Spike log,
  - resets and loads firmware into the DUT,
  - steps the simulation and compares PC, GPR/CSR and memory effects
    against the Spike trace.

  It relies on the TB helpers (InitSim/FinalizeSim, Cycle/Comb, clocks_resets)
  and the memory/loader utilities.

\remarks
  - Uses single-core Spike traces (core field kept for completeness).
  - Assumes the parser produces, for each non-`ebreak` instruction, a valid
    `next` node (the next instruction), so we can check the post-commit PC.

\section simulation_vs_spike_cpp_version_history Version history
| Version | Date       | Author     | Description                                |
|:-------:|:----------:|:-----------|:-------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                           |
********************************************************************************
*/

#include <cstdio>
#include <cstdlib>
#include <cstring> // memcmp, strlen
#include <iostream>
#include <string>

#include "Vriscv_core_harness.h"
#include "args_parser.h"
#include "clocks_resets.h"
#include "defines.h"
#include "load.h"
#include "log.h"
#include "memory.h"
#include "sim.h"
#include "sim_log.h"
#include "simulation.h"
#include "spike_parser.h"

/// Provided by the Verilator harness (DUT instance).
extern Vriscv_core_harness* dut;

/*------------------------------------------------------------------------------
 * Local helpers
 *----------------------------------------------------------------------------*/

/*!
 * \brief Return true if opcode corresponds to a LOAD (0000011).
 */
static inline bool IsLoad(uint32_t instr_bin)
{
  const uint32_t opcode = instr_bin & 0x7F;
  return (opcode == 0b0000011);
}

/*!
 * \brief Return true if opcode corresponds to a STORE (0100011).
 */
static inline bool IsStore(uint32_t instr_bin)
{
  const uint32_t opcode = instr_bin & 0x7F;
  return (opcode == 0b0100011);
}

/*!
 * \brief Return true if opcode corresponds to a CSR (1110011).
 */
static inline bool IsCSR(uint32_t instr_bin)
{
  const uint32_t opcode = instr_bin & 0x7F;
  return (opcode == 0b1110011);
}

/*!
 * \brief Return the next CSR instruction or NULL.
 */
Instr* FindNextCsrInstr(Instr* current)
{
  if (IsCSR(current->instr_bin))
  {
    return current;
  }

  while (!IsCSR(current->instr_bin))
  {
    current = current->next;
    if (current == NULL)
    {
      return NULL;
    }
  }

  return current;
}

/*!
 * \brief Return true if opcode corresponds to a Branch (1100011).
 */
static inline bool IsBranch(uint32_t instr_bin)
{
  const uint32_t opcode = instr_bin & 0x7F;
  return (opcode == 0b1100011);
}

/*!
 * \brief Read the written data back from DATA RAMs image, shifted by address LSBs.
 *
 * The DATA RAMs are exposed as word-wide entries (`NB_BYTES_IN_WORD` per entry).
 * We reconstruct the exact byte/half/word/dword as Spike reports it by shifting
 * according to the byte offset (ADDR_OFFSET).
 */
static inline uword_t ReadBackAlignedData(uword_t mem_addr)
{
  const uword_t word_index = (mem_addr & 0xFFFF) / NB_BYTES_IN_WORD;
  uword_t       raw        = 0;

  if (mem_addr >= PTC_FIFO_START_ADDR &&
      mem_addr < PTC_FIFO_START_ADDR + PTC_FIFO_SIZE)
  {
    raw = dut->ptc_dpram_mem[word_index];
  }
  else if (mem_addr >= CTP_FIFO_START_ADDR &&
           mem_addr < CTP_FIFO_START_ADDR + CTP_FIFO_SIZE)
  {
    raw = dut->ctp_dpram_mem[word_index];
  }
  else
  {
    raw = dut->data_dpram_mem[word_index];
  }

  const uword_t byte_off = (mem_addr & ADDR_OFFSET) * 8; // shift in bits
  return (raw >> byte_off);
}

static inline uword_t verify_mem(Instr* instr)
{
  const uword_t  rb     = ReadBackAlignedData(instr->mem_addr);
  const uint32_t funct3 = (instr->instr_bin >> 12) & 0x7;

  if (funct3 == 0b000)
  { // SB
    if ((rb & 0xFFu) != (instr->mem_data & 0xFFu))
    {
      LogPrintf("Instruction %s (pc: 0x%x) error: SB @ 0x" WORD_PRINT_FMT
                " expected 0x" WORD_PRINT_FMT " got 0x" WORD_PRINT_FMT ".\n",
                instr->instr,
                instr->addr,
                (uword_t)instr->mem_addr,
                (uword_t)(instr->mem_data & 0xFFu),
                (uword_t)(rb & 0xFFu));
      return FAILURE;
    }
  }
  else if (funct3 == 0b001)
  { // SH
    if ((rb & 0xFFFFu) != (instr->mem_data & 0xFFFFu))
    {
      LogPrintf("Instruction %s (pc: 0x%x) error: SH @ 0x" WORD_PRINT_FMT
                " expected 0x" WORD_PRINT_FMT " got 0x" WORD_PRINT_FMT ".\n",
                instr->instr,
                instr->addr,
                (uword_t)instr->mem_addr,
                (uword_t)(instr->mem_data & 0xFFFFu),
                (uword_t)(rb & 0xFFFFu));
      return FAILURE;
    }
  }
  else if (funct3 == 0b010)
  { // SW
    if ((rb & 0xFFFFFFFFull) != (instr->mem_data & 0xFFFFFFFFull))
    {
      LogPrintf("Instruction %s (pc: 0x%x) error: SW @ 0x" WORD_PRINT_FMT
                " expected 0x" WORD_PRINT_FMT " got 0x" WORD_PRINT_FMT ".\n",
                instr->instr,
                instr->addr,
                (uword_t)instr->mem_addr,
                (uword_t)(instr->mem_data & 0xFFFFFFFFull),
                (uword_t)(rb & 0xFFFFFFFFull));
      return FAILURE;
    }
  }
  else
  { // SD (or wider on RV64)
    if (rb != instr->mem_data)
    {
      LogPrintf("Instruction %s (pc: 0x%x) error: SD @ 0x" WORD_PRINT_FMT
                " expected 0x" WORD_PRINT_FMT " got 0x" WORD_PRINT_FMT ".\n",
                instr->instr,
                instr->addr,
                (uword_t)instr->mem_addr,
                (uword_t)instr->mem_data,
                (uword_t)rb);
      return FAILURE;
    }
  }

  return SUCCESS;
}

static inline uword_t verify_gpr(Instr* instr)
{
  if (instr->rd >= 0)
  {
    if (dut->gpr_memory[instr->rd] != instr->rd_data)
    {
      LogPrintf("Instruction %s (pc: 0x%x) error: GPR x%02u expected 0x" WORD_PRINT_FMT
                " got 0x" WORD_PRINT_FMT ".\n",
                instr->instr,
                instr->addr,
                (unsigned)instr->rd,
                (uword_t)instr->rd_data,
                (uword_t)dut->gpr_memory[instr->rd]);
      return FAILURE;
    }
  }

  return SUCCESS;
}

/*!
 * \brief Execute and check a firmware run against a Spike trace.
 *
 * Steps:
 *  - Parse Spike log
 *  - Reset and program the DUT memories
 *  - Step the DUT and compare PC, GPR/CSR, and memory effects
 *
 * \return SUCCESS on pass, FAILURE otherwise.
 */
static uint32_t run(const std::string& firmwarefile, const std::string& spikefile)
{
  uint32_t flag = SUCCESS;

  // Parse Spike log (ownership returned; FreeSpike when done)
  SpikeLog* spike = ParseSpike(spikefile);
  if (spike == nullptr)
  {
    return FAILURE;
  }

  // Reset RAMs and load firmware into INSTR/DATA
  SetRamResetSignal(1);
  if (LoadFirmware(firmwarefile) != SUCCESS)
  {
    FreeSpike(spike);
    return FAILURE;
  }

  Instr* instr = spike->instructions;
  while (std::memcmp(instr->instr, "ebreak", std::strlen("ebreak")) != 0)
  {
    /*
     * Spike does not implement CSRs (except for mcycle).
     * In case of CSR op, overwrite the data read by decode
     * with the spike data.
     * It ensures compatibility between spike and the design.
     */
    if (!dut->pipeline_flush && dut->decode_csr_raddr)
    {
      Instr* csr = FindNextCsrInstr(instr);

      if (!csr)
      {
        LogPrintf("Error: A CSR instruction has been detected in Decode but no CSR instruction has "
                  "been found in the Spike Golden Trace. Current instruction to be committed: %s "
                  "(pc: 0x%x).\n",
                  instr->instr,
                  instr->addr);
        return FAILURE;
      }
      dut->csr_en   = 1;
      dut->csr_data = csr->rd_data;
      Comb();
    }
    else
    {
      dut->csr_en   = 0;
      dut->csr_data = 0;
      Comb();
    }

    if (dut->instr_committed)
    {
      if (IsStore(instr->instr_bin))
      {
        flag = verify_mem(instr);
        if (flag != SUCCESS)
        {
          break;
        }
      }
      else
      {
        flag = verify_gpr(instr);
        if (flag != SUCCESS)
        {
          break;
        }
      }
      instr = instr->next;
    }

    Cycle();
  }

  // Final commit edge before reporting
  Cycle();

  FreeSpike(spike);
  return flag;
}

/*------------------------------------------------------------------------------
 * Program main()
 *----------------------------------------------------------------------------*/

int main(int argc, char** argv, char** /*env*/)
{
  Arguments args;
  args.Parse(argc, argv);

  // Minimal CLI validation
  if (args.GetLogFile().empty() || args.GetFirmwareFile().empty() || args.GetSpikeFile().empty() ||
      args.GetWaveformFile().empty())
  {
    args.PrintUsage(argv[0]);
    return EXIT_FAILURE;
  }

  if (SetLogFile(args.GetLogFile()) != SUCCESS)
  {
    std::fprintf(stderr, "Error: unable to open log file: %s\n", args.GetLogFile().c_str());
    return EXIT_FAILURE;
  }

  // Initialize TB + waves, then run the Spike-vs-DUT checker
  InitSim(args.GetWaveformFile());

  const uint32_t flag = run(args.GetFirmwareFile(), args.GetSpikeFile());

  if (flag != SUCCESS)
  {
    LogPrintf("FAILURE\n");
  }
  else
  {
    LogPrintf("SUCCESS\n");
  }

  FinalizeSim();
  return (flag == SUCCESS) ? EXIT_SUCCESS : EXIT_FAILURE;
}
