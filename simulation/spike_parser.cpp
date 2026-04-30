// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       spike_parser.cpp
\brief      Spike log parser implementation.
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Implementation for \ref ParseSpike / \ref FreeSpike and helpers.
  The parser is tolerant to extra lines and skips non-user-space addresses.

\remarks
  - This implementation uses simple C-style parsing (sscanf/str*),
    tuned for the expected Spike output format.

\section spike_parser_cpp_version_history Version history
| Version | Date       | Author     | Description                                |
|:-------:|:----------:|:-----------|:-------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                           |
********************************************************************************
*/

#include "spike_parser.h"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <string>

#include "defines.h"

/*------------------------------------------------------------------------------
 * Small parsing helpers
 *----------------------------------------------------------------------------*/

/*!
 * \brief Skip leading spaces in [p, end).
 */
static inline char* RemoveSpaces(char* p, const char* end)
{
  while (p < end && *p == ' ')
  {
    ++p;
  }
  return p;
}

/*!
 * \brief Advance until a space or end.
 */
static inline char* MoveToNextSpace(char* p, const char* end)
{
  while (p < end && *p != ' ')
  {
    ++p;
  }
  return p;
}

/*!
 * \brief True if line is blank or a comment (supports '#', '//').
 */
static inline int IsCommentOrBlank(const char* s)
{
  while (*s == ' ' || *s == '\t' || *s == '\r' || *s == '\n')
  {
    ++s;
  }
  return (*s == '\0') || (*s == '#') || (s[0] == '/' && s[1] == '/');
}

/*------------------------------------------------------------------------------
 * Field parsers (bounded)
 *----------------------------------------------------------------------------*/

static inline char* ParseCore(Instr* ins, char* p, const char* end)
{
  p = MoveToNextSpace(p, end);
  p = RemoveSpaces(p, end);
  (void)std::sscanf(p, "%hhu", &ins->core);
  p = MoveToNextSpace(p, end);
  return RemoveSpaces(p, end);
}

static inline char* ParseAddr(Instr* ins, char* p, const char* end)
{
  (void)std::sscanf(p, "%" SCNx64, &ins->addr);
  p = MoveToNextSpace(p, end);
  return RemoveSpaces(p, end);
}

static inline char* ParseInstrBin(Instr* ins, char* p, const char* end)
{
  if (p < end && *p == '(')
  {
    ++p; // skip '('
  }
  (void)std::sscanf(p, "%x", &ins->instr_bin);
  p = MoveToNextSpace(p, end);
  return RemoveSpaces(p, end);
}

static inline char* ParseInstrAsm(Instr* ins, char* p, const char* end)
{
  const size_t n    = static_cast<size_t>(end - p);
  const size_t copy = (n < sizeof(ins->instr) - 1) ? n : (sizeof(ins->instr) - 1);
  std::memset(ins->instr, 0, sizeof(ins->instr));
  std::memcpy(ins->instr, p, copy - 1); // -1 to remove \n
  ins->instr[copy - 1] = '\0';          // -1 to remove \n
  return const_cast<char*>(end);
}

static inline char* ParseRd(Instr* ins, char* p, const char* end)
{
  if (p < end && *p == 'x')
  {
    ++p;
  }
  unsigned tmp = 0;
  (void)std::sscanf(p, "%u", &tmp);
  ins->rd = static_cast<int8_t>(tmp);
  p       = MoveToNextSpace(p, end);
  return RemoveSpaces(p, end);
}

static inline char* ParseRdData(Instr* ins, char* p, const char* end)
{
  (void)std::sscanf(p, "%" SCNx64, &ins->rd_data);
  p = MoveToNextSpace(p, end);
  return RemoveSpaces(p, end);
}

static inline char* ParseMem(Instr* ins, char* p, const char* end)
{
  // p should point to 'm' of "mem"
  p = MoveToNextSpace(p, end); // skip "mem"
  p = RemoveSpaces(p, end);

  (void)std::sscanf(p, "%" SCNx64, &ins->mem_addr);

  p = MoveToNextSpace(p, end);
  p = RemoveSpaces(p, end);
  if (p < end)
  {
    (void)std::sscanf(p, "%" SCNx64, &ins->mem_data);
  }
  return const_cast<char*>(end);
}

/*------------------------------------------------------------------------------
 * Core parsing routine
 *----------------------------------------------------------------------------*/

/*!
 * \brief Internal parsing routine. Builds a singly-linked list of instructions.
 *
 * Robustness features:
 *  - Bounds all scans on line using (ptr < end) guards.
 *  - Tolerates missing ')' on result lines without segfaulting.
 *  - Skips non-user-space instructions (addr < 0x80000000).
 *  - Avoids trailing empty node by pruning at the end.
 */
uint32_t Parse(SpikeLog* spike, FILE* file)
{
  char line[1024];

  spike->instructions = static_cast<Instr*>(std::calloc(1, sizeof(Instr)));
  if (!spike->instructions)
  {
    return FAILURE;
  }

  Instr* current = spike->instructions;
  Instr* next    = nullptr;

  while (std::fgets(line, sizeof(line), file) != nullptr)
  {
    // Skip unexpected / comment / blank lines
    if (std::strstr(line, ">>>>") != nullptr || std::strstr(line, "$x") != nullptr ||
        IsCommentOrBlank(line))
    {
      continue;
    }

    // -------- First line (instruction line) --------
    char* ptr   = line;
    char* lfptr = ptr + std::strlen(ptr); // end sentinel

    ptr = ParseCore(current, ptr, lfptr);
    ptr = ParseAddr(current, ptr, lfptr);
    ptr = ParseInstrBin(current, ptr, lfptr);
    ptr = ParseInstrAsm(current, ptr, lfptr);

    // Stop on ebreak (end of spike execution)
    if (std::memcmp(current->instr, "ebreak", std::strlen("ebreak")) == 0)
    {
      break;
    }

    // -------- Second line (result/output line) --------
    if (std::fgets(line, sizeof(line), file) == nullptr)
    {
      // No second line available: leave as-is and stop.
      break;
    }

    if (!IsCommentOrBlank(line))
    {
      ptr   = line;
      lfptr = ptr + std::strlen(ptr);

      // Find ')' in a bounded way; tolerate missing ')'
      while (ptr < lfptr && *ptr != ')')
      {
        ++ptr;
      }
      if (ptr < lfptr)
      {        // found ')'
        ++ptr; // skip ')'
        ptr = RemoveSpaces(ptr, lfptr);

        // Optional GPR writeback
        if (ptr < lfptr && *ptr == 'x')
        {
          ptr = ParseRd(current, ptr, lfptr);
          ptr = ParseRdData(current, ptr, lfptr);
        }

        // Optional memory access
        if ((lfptr - ptr) >= 3 && std::memcmp(ptr, "mem", 3) == 0)
        {
          (void)ParseMem(current, ptr, lfptr);
        }
      }
    }

    // Skip Spike instructions (e.g., Spike internals)
    if (current->addr < 0x00002000ULL)
    {
      // keep current node to be overwritten by next valid instruction
      std::memset(current, 0, sizeof(*current));
      continue;
    }

    // Allocate next node only when we have a valid user-space instruction
    next = static_cast<Instr*>(std::calloc(1, sizeof(Instr)));
    if (!next)
    {
      // out of memory, stop parsing cleanly
      break;
    }
    current->next = next;
    current       = next;
  }

  // ---- Prune a trailing empty node (if any) ----
  Instr* head = spike->instructions;
  if (head && head->next == nullptr && head->instr[0] == '\0')
  {
    // Only one node and it's empty → list is effectively empty
    std::free(head);
    spike->instructions = nullptr;
  }
  else if (head)
  {
    // Remove last node if it's empty
    Instr* prev = head;
    Instr* it   = head->next;
    while (it)
    {
      if (it->next == nullptr && it->instr[0] == '\0')
      {
        std::free(it);
        prev->next = nullptr;
        break;
      }
      prev = it;
      it   = it->next;
    }
  }

  return SUCCESS;
}

/*------------------------------------------------------------------------------
 * Public API
 *----------------------------------------------------------------------------*/

SpikeLog* ParseSpike(const std::string& filename)
{
  FILE* file = std::fopen(filename.c_str(), "r");
  if (!file)
  {
    std::printf("Error, unable to open file: %s\n", filename.c_str());
    return nullptr;
  }

  SpikeLog* spike = static_cast<SpikeLog*>(std::calloc(1, sizeof(SpikeLog)));
  if (!spike)
  {
    std::printf("Error, unable to allocate memory for SpikeLog structure\n");
    std::fclose(file);
    return nullptr;
  }

  (void)Parse(spike, file);
  std::fclose(file);
  return spike;
}

void FreeSpike(SpikeLog* spike)
{
  if (!spike)
  {
    return;
  }
  Instr* it = spike->instructions;
  while (it)
  {
    Instr* nxt = it->next;
    std::free(it);
    it = nxt;
  }
  std::free(spike);
}

/*------------------------------------------------------------------------------
 * Debug printers (optional helpers)
 *----------------------------------------------------------------------------*/

static void PrintInstr(const Instr* instr)
{
  if (!instr)
  {
    std::cout << "Instruction is null.\n";
    return;
  }

  std::cout << "=== Instruction Info ===\n";
  std::cout << "Core ID       : " << static_cast<int>(instr->core) << "\n";
  std::cout << "Address       : 0x" << std::hex << std::setw(16) << std::setfill('0') << instr->addr
            << std::dec << "\n";
  std::cout << "Binary        : 0x" << std::hex << std::setw(8) << std::setfill('0')
            << instr->instr_bin << std::dec << "\n";
  std::cout << "ASM           : " << instr->instr << "\n";

  if (instr->rd >= 0)
  {
    std::cout << "RD            : x" << static_cast<int>(instr->rd) << "\n";
    std::cout << "RD Data       : 0x" << std::hex << std::setw(16) << std::setfill('0')
              << instr->rd_data << std::dec << "\n";
  }
  else
  {
    std::cout << "RD            : (none)\n";
  }

  if (instr->mem_addr != 0 || instr->mem_data != 0)
  {
    std::cout << "Memory Addr   : 0x" << std::hex << std::setw(16) << std::setfill('0')
              << instr->mem_addr << std::dec << "\n";
    std::cout << "Memory Data   : 0x" << std::hex << std::setw(16) << std::setfill('0')
              << instr->mem_data << std::dec << "\n";
  }

  std::cout << "Has next?     : " << (instr->next ? "Yes" : "No") << "\n";
  std::cout << "========================\n";
}

void PrintInstrList(const Instr* head)
{
  int          index = 0;
  const Instr* cur   = head;
  while (cur)
  {
    std::cout << "Instruction #" << index << ":\n";
    PrintInstr(cur);
    cur = cur->next;
    ++index;
  }
}
