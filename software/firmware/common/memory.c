// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       memory.c
\brief      Low-level memory & shared-RAM helpers (bare-metal).
\author     Kawanami
\version    1.0
\date       28/04/2026

\details

\section memory_c_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#include "memory.h"

#include "defines.h"

/*!
 * \brief Check whether an integer address-sized value is aligned.
 *
 * \param v Value to test.
 * \param g Required alignment granularity, in bytes.
 *
 * \return Non-zero if `v` is aligned to `g`, zero otherwise.
 */
static inline int IsAlignedUintptr(uintptr_t v, uword_t g)
{
  return ((v % g) == 0u);
}

/*!
 * \brief Check whether a size value is aligned.
 *
 * \param v Size value to test.
 * \param g Required alignment granularity, in bytes.
 *
 * \return Non-zero if `v` is aligned to `g`, zero otherwise.
 */
static inline int IsAlignedSize(uword_t v, uword_t g)
{
  return ((v % g) == 0u);
}


void MemWrite(uintptr_t addr, const uword_t* data, uword_t size)
{
  /* Word granularity contract. */
  if (!IsAlignedUintptr(addr, NB_BYTES_IN_WORD) || !IsAlignedSize(size, NB_BYTES_IN_WORD))
  {
    return; /* silently ignore in bare-metal; caller must pass aligned args */
  }

  volatile uword_t* p     = (volatile uword_t*)addr;
  const size_t      beats = (size_t)(size / NB_BYTES_IN_WORD);

  for (size_t i = 0; i < beats; ++i)
  {
    p[i] = data[i];
  }
}

void MemRead(uintptr_t addr, uword_t* data, uword_t size)
{
  if (!IsAlignedUintptr(addr, NB_BYTES_IN_WORD) || !IsAlignedSize(size, NB_BYTES_IN_WORD))
  {
    return;
  }

  volatile const uword_t* p     = (volatile const uword_t*)addr;
  const size_t            beats = (size_t)(size / NB_BYTES_IN_WORD);

  for (size_t i = 0; i < beats; ++i)
  {
    data[i] = p[i];
  }
}
