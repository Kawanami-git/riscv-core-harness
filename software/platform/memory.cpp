// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       memory.cpp
\brief      Thin, safe helpers on top of the AXI4 backend (impl)
\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  See \ref memory.h. This layer:
  - Enforces alignment (AXI can only access word-aligned words),
  - Delegates to \ref InstrAxi4Write / \ref Axi4Write / \ref Axi4Read,
  - Implements a tiny PTC/CTP mailbox with consistent local counters.

\remarks
  - All addresses are \b window-relative for the AXI backend.
  - The shared-memory helpers rely on the address constants from \ref defines.h.

\section memory_cpp_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#include "memory.h"

#include <cstdio>
#include <cstdlib>

#include "axi4.h"
#include "log.h"

static inline bool IsAligned(const uintptr_t addr, const uword_t size, const uword_t granule)
{
  return ((addr % granule) == 0u) && ((size % granule) == 0u);
}

uword_t MemWrite(const uintptr_t addr, const uword_t* data, const uword_t size)
{
  uword_t alignedSize;
  alignedSize = (size + (NB_BYTES_IN_WORD - 1)) & ~(NB_BYTES_IN_WORD - 1);

  if (addr >= SYS_RESET_START_ADDR && addr <= SYS_RESET_END_ADDR)
  {
    return SysResetAxi4Write(addr, data, alignedSize, AxiBurst::Fixed);
  }
  else if (addr >= INSTR_RAM_START_ADDR && addr <= INSTR_RAM_END_ADDR)
  {
    alignedSize = (size + (4U - 1U)) & ~(4U - 1U);
    return InstrAxi4Write(addr, (uint32_t*)data, alignedSize, AxiBurst::Incr);
  }
  else if (addr >= DATA_RAM_START_ADDR && addr <= DATA_RAM_END_ADDR)
  {
    return DataAxi4Write(addr, data, alignedSize, AxiBurst::Incr);
  }
  else
  {
    return FAILURE;
  }
}

uword_t MemRead(const uintptr_t addr, uword_t* data, const uword_t size)
{
  uword_t alignedSize;
  alignedSize = (size + (NB_BYTES_IN_WORD - 1)) & ~(NB_BYTES_IN_WORD - 1);

  if (addr >= SYS_RESET_START_ADDR && addr <= SYS_RESET_END_ADDR)
  {
    return SysResetAxi4Read(addr, data, alignedSize, AxiBurst::Fixed);
  }
  if (addr >= INSTR_RAM_START_ADDR && addr <= INSTR_RAM_END_ADDR)
  {
    alignedSize = (size + (4 - 1)) & ~(4 - 1);
    return InstrAxi4Read(addr, (uint32_t*)data, alignedSize, AxiBurst::Incr);
  }
  if (addr >= DATA_RAM_START_ADDR && addr <= DATA_RAM_END_ADDR)
  {
    return DataAxi4Read(addr, data, alignedSize, AxiBurst::Incr);
  }
  else
  {
    return FAILURE;
  }
}

uword_t InstrMemReset()
{
  uword_t flag = SUCCESS;
  uint32_t value = 0x00;
  uint32_t buf = 0x00;
  for (int i = INSTR_RAM_START_ADDR; i <= INSTR_RAM_END_ADDR; i += 4)
  {
    if ((flag = InstrAxi4Write(i, &value, 4, AxiBurst::Fixed)) != SUCCESS)
    {
      return flag;
    }
  }

  for (int i = INSTR_RAM_START_ADDR; i <= INSTR_RAM_END_ADDR; i += 4)
  {
    if ((flag = InstrAxi4Read(i, &buf, 4, AxiBurst::Fixed)) != SUCCESS)
    {
      return flag;
    }
    if(buf != value)
    {
      return FAILURE;
    }
  }

  return SUCCESS;
}

uword_t DataMemReset()
{
  uword_t flag = SUCCESS;
  uword_t value = 0x00;
  uword_t buf = 0x00;
  for (int i = DATA_RAM_START_ADDR; i <= DATA_RAM_END_ADDR; i += NB_BYTES_IN_WORD)
  {
    if ((flag = DataAxi4Write(i, &value, NB_BYTES_IN_WORD, AxiBurst::Fixed)) != SUCCESS)
    {
      return flag;
    }
  }

    for (int i = DATA_RAM_START_ADDR; i <= DATA_RAM_END_ADDR; i += NB_BYTES_IN_WORD)
  {
    if ((flag = DataAxi4Read(i, &buf, NB_BYTES_IN_WORD, AxiBurst::Fixed)) != SUCCESS)
    {
      return flag;
    }
    if(buf != value)
    {
      return FAILURE;
    }
  }

  return SUCCESS;
}
