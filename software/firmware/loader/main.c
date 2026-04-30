// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       main.c
\brief      Minimal demo firmware: prints via Eprintf and exercises format args.
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Bare-metal entry that:
    - clears the CTP shared RAM,
    - sends a few formatted messages through Eprintf(),
    - returns to the start stub (which loops forever).

  This is useful to validate the firmware load path, shared-memory plumbing,
  and the embedded printf implementation.

\section loader_main_c_version_history Version history
| Version | Date       | Author     | Description      |
|:-------:|:----------:|:-----------|:-----------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version. |
********************************************************************************
*/

#include "defines.h"
#include "memory.h"
#include "fifo.h"

int main(void)
{
  word_t  integer  = -123456789;
  uword_t uinteger = 123456789;
#ifdef XLEN64
  uword_t hex = 0xabcdef0123456789ULL;
#else
  uword_t hex = 0xabcdef01UL;
#endif
  const char* s = "Eprintf arguments test end.\n";

  // Simple banner + formatting exercise
  Eprintf("Hi, I've been loaded correctly.\n");
  Eprintf("Beginning Eprintf arguments test.\n");

  Eprintf("Integer (-123456789): %d\n", integer);
  Eprintf("Unsigned Integer (123456789): %u\n", uinteger);
#ifdef XLEN64
  Eprintf("Hex (0xabcdef0123456789): 0x%lx\n", hex);
#else
  Eprintf("Hex (0xabcdef01): 0x%x\n", hex);
#endif
  Eprintf("String: %s", s);

  // start.s will loop after main returns
  return 0;
}
