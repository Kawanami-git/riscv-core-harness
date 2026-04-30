// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       axi4.cpp
\brief      AXI4 access backend (simulation & Linux target)

\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Implementation of the AXI4 memory helper API declared in \ref axi4.h.

  Two backends are provided via conditional compilation:
  - SIM (Verilator simulation): cycles accurate handshakes on the DUT AXI pins.
  - Platform (Linux target): /dev/mem mapping and plain loads/stores.

  Only single-beat style transactions are modeled. Bursts are not implemented.

\remarks
  - In simulation, the API performs explicit AW/W/B and AR/R handshakes and
    advances time using cycle().
  - On hardware, the mapped addresses are accessed through volatile pointers to
    prevent the compiler from optimizing MMIO accesses.

\section axi4_cpp_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#include "axi4.h"

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <inttypes.h>
#include <unistd.h>
#include "log.h"
/*------------------------------------------------------------------------------
 * Small helpers
 *----------------------------------------------------------------------------*/

/*!
 * \brief Quick alignment check for both address and size.
 * \param addr    Base address (byte address).
 * \param size    Transfer size in bytes.
 * \param granule Alignment granularity (bytes).
 * \return true if both \p addr and \p size are multiples of \p granule.
 */
static inline bool IsAligned(uintptr_t addr, uword_t size, uword_t granule)
{
  return ((addr % granule) == 0u) && ((size % granule) == 0u);
}

#ifdef SIM

/*==============================================================================
 *                          SIMULATION (Verilator)
 *============================================================================*/

#include "Vriscv_core_harness.h"
#include "sim.h"

/// Provided by the simulation harness.
extern Vriscv_core_harness* dut;

/*--------------------------- System Reset window mapping ----------------------*/

uword_t SysResetAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t size, AxiBurst mode)
{
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, size, 4))
  {
    return ADDR_NOT_ALIGNED;
  }

  uint32_t     localAddr = static_cast<uint32_t>(addr);
  const size_t beats     = static_cast<size_t>(size / NB_BYTES_IN_WORD);

  for (size_t i = 0; i < beats; i++)
  {
    // --- AW phase (single-beat, 4-byte) ---
    dut->s_sys_reset_awaddr_i  = localAddr;
    dut->s_sys_reset_awburst_i = 0b00;
#ifdef XLEN64
    dut->s_sys_reset_awsize_i = 0b011; // 8 bytes
#else
    dut->s_sys_reset_awsize_i = 0b010; // 4 bytes
#endif
    dut->s_sys_reset_awlen_i   = 0;
    dut->s_sys_reset_awvalid_i = 1;
    while (dut->s_sys_reset_awready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_sys_reset_awvalid_i = 0;

    // --- W phase (data + strobes) ---
    dut->s_sys_reset_wdata_i = data[i];
#ifdef XLEN64
    dut->s_sys_reset_wstrb_i = 0xFF;
#else
    dut->s_sys_reset_wstrb_i = 0x0F;
#endif
    dut->s_sys_reset_wlast_i  = 1;
    dut->s_sys_reset_wvalid_i = 1;
    while (dut->s_sys_reset_wready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_sys_reset_wvalid_i = 0;

    // --- B phase (response) ---
    dut->s_sys_reset_bready_i = 1;
    while (dut->s_sys_reset_bvalid_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_sys_reset_bready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += NB_BYTES_IN_WORD;
    }
  }

  return SUCCESS;
}

uword_t SysResetAxi4Read(const uintptr_t addr, uword_t* data, const uword_t size, AxiBurst mode)
{
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, size, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  uword_t      localAddr = static_cast<uword_t>(addr);
  const size_t beats     = static_cast<size_t>(size / NB_BYTES_IN_WORD);

  for (size_t i = 0; i < beats; i++)
  {
    // --- AR phase (single-beat, 4B or 8B) ---
    dut->s_sys_reset_araddr_i  = localAddr;
    dut->s_sys_reset_arburst_i = 0b00;
#ifdef XLEN64
    dut->s_sys_reset_arsize_i = 0b011; // 8 bytes
#else
    dut->s_sys_reset_arsize_i = 0b010; // 4 bytes
#endif
    dut->s_sys_reset_arlen_i   = 0;
    dut->s_sys_reset_arvalid_i = 1;
    while (dut->s_sys_reset_arready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_sys_reset_arvalid_i = 0;

    // --- R phase ---
    dut->s_sys_reset_rready_i = 1;
    while (dut->s_sys_reset_rvalid_o == 0)
    {
      Cycle();
    }
    data[i] = dut->s_sys_reset_rdata_o;
    Cycle();
    dut->s_sys_reset_rready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += NB_BYTES_IN_WORD;
    }
  }

  return SUCCESS;
}

/*------------------------------- Instruction window mapping -------------------------*/

uword_t InstrAxi4Write(const uintptr_t addr, const uint32_t* data, const uword_t size, AxiBurst mode)
{
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, size, 4))
  {
    return ADDR_NOT_ALIGNED;
  }

  uint32_t     localAddr = static_cast<uint32_t>(addr);
  const size_t beats     = static_cast<size_t>(size / 4);

  for (size_t i = 0; i < beats; i++)
  {
    // --- AW phase (single-beat, 4-byte) ---
    dut->s_instr_awaddr_i  = localAddr;
    dut->s_instr_awburst_i = 0b00;
    dut->s_instr_awsize_i  = 0b010; // 4 bytes
    dut->s_instr_awlen_i   = 0;
    dut->s_instr_awvalid_i = 1;
    while (dut->s_instr_awready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_instr_awvalid_i = 0;

    // --- W phase (data + strobes) ---
    dut->s_instr_wdata_i  = data[i];
    dut->s_instr_wstrb_i  = 0xF;
    dut->s_instr_wlast_i  = 1;
    dut->s_instr_wvalid_i = 1;
    while (dut->s_instr_wready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_instr_wvalid_i = 0;

    // --- B phase (response) ---
    dut->s_instr_bready_i = 1;
    while (dut->s_instr_bvalid_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_instr_bready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += 4;
    }
  }

  return SUCCESS;
}

uword_t InstrAxi4Read(const uintptr_t addr, uint32_t* data, const uword_t size, AxiBurst mode)
{
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, size, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  uword_t      localAddr = static_cast<uword_t>(addr);
  const size_t beats     = static_cast<size_t>(size / NB_BYTES_IN_WORD);

  for (size_t i = 0; i < beats; i++)
  {
    // --- AR phase (single-beat, 4B or 8B) ---
    dut->s_instr_araddr_i  = localAddr;
    dut->s_instr_arburst_i = 0b00;
    dut->s_instr_arsize_i  = 0b010; // 4 bytes
    dut->s_instr_arlen_i   = 0;
    dut->s_instr_arvalid_i = 1;
    while (dut->s_instr_arready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_instr_arvalid_i = 0;

    // --- R phase ---
    dut->s_instr_rready_i = 1;
    while (dut->s_instr_rvalid_o == 0)
    {
      Cycle();
    }
    data[i] = dut->s_instr_rdata_o;
    Cycle();
    dut->s_instr_rready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += 4;
    }
  }

  return SUCCESS;
}

/*------------------------------- Data window mapping -------------------------*/

uword_t DataAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t size, AxiBurst mode)
{
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, size, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  uword_t      localAddr = static_cast<uword_t>(addr);
  const size_t beats     = static_cast<size_t>(size / NB_BYTES_IN_WORD);

  for (size_t i = 0; i < beats; i++)
  {
    // --- AW phase (single-beat, 4B or 8B) ---
    dut->s_data_awaddr_i  = localAddr;
    dut->s_data_awburst_i = 0b00;
#ifdef XLEN64
    dut->s_data_awsize_i = 0b011; // 8 bytes
#else
    dut->s_data_awsize_i = 0b010; // 4 bytes
#endif
    dut->s_data_awlen_i   = 0;
    dut->s_data_awvalid_i = 1;
    while (dut->s_data_awready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_data_awvalid_i = 0;

    // --- W phase ---
    dut->s_data_wdata_i  = data[i];
    dut->s_data_wlast_i  = 1;
    dut->s_data_wvalid_i = 1;
#ifdef XLEN64
    dut->s_data_wstrb_i = 0xFF;
#else
    dut->s_data_wstrb_i = 0x0F;
#endif
    while (dut->s_data_wready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_data_wvalid_i = 0;

    // --- B phase ---
    dut->s_data_bready_i = 1;
    while (dut->s_data_bvalid_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_data_bready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += NB_BYTES_IN_WORD;
    }
  }

  return SUCCESS;
}

uword_t DataAxi4Read(const uintptr_t addr, uword_t* data, const uword_t size, AxiBurst mode)
{
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, size, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  uword_t      localAddr = static_cast<uword_t>(addr);
  const size_t beats     = static_cast<size_t>(size / NB_BYTES_IN_WORD);

  for (size_t i = 0; i < beats; i++)
  {
    // --- AR phase (single-beat, 4B or 8B) ---
    dut->s_data_araddr_i  = localAddr;
    dut->s_data_arburst_i = 0b00;
#ifdef XLEN64
    dut->s_data_arsize_i = 0b011; // 8 bytes
#else
    dut->s_data_arsize_i = 0b010; // 4 bytes
#endif
    dut->s_data_arlen_i   = 0;
    dut->s_data_arvalid_i = 1;
    while (dut->s_data_arready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_data_arvalid_i = 0;

    // --- R phase ---
    dut->s_data_rready_i = 1;
    while (dut->s_data_rvalid_o == 0)
    {
      Cycle();
    }
    data[i] = dut->s_data_rdata_o;
    Cycle();
    dut->s_data_rready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += NB_BYTES_IN_WORD;
    }
  }

  return SUCCESS;
}

/*------------------------------- Platform-to-Core window mapping -------------------------*/

uword_t PtcAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t nb_words, AxiBurst mode)
{
  if (data == nullptr || nb_words == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, nb_words*NB_BYTES_IN_WORD, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  uword_t      localAddr = static_cast<uword_t>(addr);
  const size_t beats     = nb_words;

  for (size_t i = 0; i < beats; i++)
  {
    // --- AW phase (single-beat, 4B or 8B) ---
    dut->s_ptc_awaddr_i  = localAddr;
    dut->s_ptc_awburst_i = 0b00;
#ifdef XLEN64
    dut->s_ptc_awsize_i = 0b011; // 8 bytes
#else
    dut->s_ptc_awsize_i = 0b010; // 4 bytes
#endif
    dut->s_ptc_awlen_i   = 0;
    dut->s_ptc_awvalid_i = 1;
    while (dut->s_ptc_awready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_ptc_awvalid_i = 0;

    // --- W phase ---
    dut->s_ptc_wdata_i  = data[i];
    dut->s_ptc_wlast_i  = 1;
    dut->s_ptc_wvalid_i = 1;
#ifdef XLEN64
    dut->s_ptc_wstrb_i = 0xFF;
#else
    dut->s_ptc_wstrb_i = 0x0F;
#endif
    while (dut->s_ptc_wready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_ptc_wvalid_i = 0;

    // --- B phase ---
    dut->s_ptc_bready_i = 1;
    while (dut->s_ptc_bvalid_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_ptc_bready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += NB_BYTES_IN_WORD;
    }
  }

  return SUCCESS;
}

uword_t PtcAxi4Read(const uintptr_t addr, uword_t* data, const uword_t nb_words, AxiBurst mode)
{
  if (data == nullptr || nb_words == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, nb_words*NB_BYTES_IN_WORD, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  uword_t      localAddr = static_cast<uword_t>(addr);
  const size_t beats     = nb_words;

  for (size_t i = 0; i < beats; i++)
  {
    // --- AR phase (single-beat, 4B or 8B) ---
    dut->s_ptc_araddr_i  = localAddr;
    dut->s_ptc_arburst_i = 0b00;
#ifdef XLEN64
    dut->s_ptc_arsize_i = 0b011; // 8 bytes
#else
    dut->s_ptc_arsize_i = 0b010; // 4 bytes
#endif
    dut->s_ptc_arlen_i   = 0;
    dut->s_ptc_arvalid_i = 1;
    while (dut->s_ptc_arready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_ptc_arvalid_i = 0;

    // --- R phase ---
    dut->s_ptc_rready_i = 1;
    while (dut->s_ptc_rvalid_o == 0)
    {
      Cycle();
    }
    data[i] = dut->s_ptc_rdata_o;
    Cycle();
    dut->s_ptc_rready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += NB_BYTES_IN_WORD;
    }
  }

  return SUCCESS;
}

/*------------------------------- Core-to-Platform window mapping -------------------------*/

uword_t CtpAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t nb_words, AxiBurst mode)
{
  if (data == nullptr || nb_words == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, nb_words*NB_BYTES_IN_WORD, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  uword_t      localAddr = static_cast<uword_t>(addr);
  const size_t beats     = nb_words;

  for (size_t i = 0; i < beats; i++)
  {
    // --- AW phase (single-beat, 4B or 8B) ---
    dut->s_ctp_awaddr_i  = localAddr;
    dut->s_ctp_awburst_i = 0b00;
#ifdef XLEN64
    dut->s_ctp_awsize_i = 0b011; // 8 bytes
#else
    dut->s_ctp_awsize_i = 0b010; // 4 bytes
#endif
    dut->s_ctp_awlen_i   = 0;
    dut->s_ctp_awvalid_i = 1;
    while (dut->s_ctp_awready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_ctp_awvalid_i = 0;

    // --- W phase ---
    dut->s_ctp_wdata_i  = data[i];
    dut->s_ctp_wlast_i  = 1;
    dut->s_ctp_wvalid_i = 1;
#ifdef XLEN64
    dut->s_ctp_wstrb_i = 0xFF;
#else
    dut->s_ctp_wstrb_i = 0x0F;
#endif
    while (dut->s_ctp_wready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_ctp_wvalid_i = 0;

    // --- B phase ---
    dut->s_ctp_bready_i = 1;
    while (dut->s_ctp_bvalid_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_ctp_bready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += NB_BYTES_IN_WORD;
    }
  }

  return SUCCESS;
}

uword_t CtpAxi4Read(const uintptr_t addr, uword_t* data, const uword_t nb_words, AxiBurst mode)
{
  if (data == nullptr || nb_words == 0u)
  {
    return FAILURE;
  }

  if (!IsAligned(addr, nb_words*NB_BYTES_IN_WORD, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  uword_t      localAddr = static_cast<uword_t>(addr);
  const size_t beats     = nb_words;

  for (size_t i = 0; i < beats; i++)
  {
    // --- AR phase (single-beat, 4B or 8B) ---
    dut->s_ctp_araddr_i  = localAddr;
    dut->s_ctp_arburst_i = 0b00;
#ifdef XLEN64
    dut->s_ctp_arsize_i = 0b011; // 8 bytes
#else
    dut->s_ctp_arsize_i = 0b010; // 4 bytes
#endif
    dut->s_ctp_arlen_i   = 0;
    dut->s_ctp_arvalid_i = 1;
    while (dut->s_ctp_arready_o == 0)
    {
      Cycle();
    }
    Cycle();
    dut->s_ctp_arvalid_i = 0;

    // --- R phase ---
    dut->s_ctp_rready_i = 1;
    while (dut->s_ctp_rvalid_o == 0)
    {
      Cycle();
    }
    data[i] = dut->s_ctp_rdata_o;
    Cycle();
    dut->s_ctp_rready_i = 0;

    if(mode != AxiBurst::Fixed)
    {
      localAddr += NB_BYTES_IN_WORD;
    }
  }

  return SUCCESS;
}

#else
/*==============================================================================
 *                          PLATFORM (Linux)
 *============================================================================*/

#include <fcntl.h>
#include <iostream>
#include <sys/mman.h>

/// System reset AXI Mapped base addresses (volatile to prevent compiler reordering/merging)
static volatile uword_t* gSysResetAxiBase = nullptr;
/// Instruction AXI Mapped base addresses (volatile to prevent compiler reordering/merging)
static volatile uint32_t* gInstrAxiBase = nullptr;
/// Data AXI Mapped base addresses (volatile to prevent compiler reordering/merging)
static volatile uword_t* gDataAxiBase = nullptr;
/// Ptc AXI Mapped base addresses (volatile to prevent compiler reordering/merging)
static volatile uword_t* gPtcAxiBase = nullptr;
/// Ctp AXI Mapped base addresses (volatile to prevent compiler reordering/merging)
static volatile uword_t* gCtpAxiBase = nullptr;

/// Tracked mmap sizes (used on unmap)
static uword_t gSysResetAxiSize = 0;
/// Tracked mmap sizes (used on unmap)
static uint32_t gInstrAxiSize = 0;
/// Tracked mmap sizes (used on unmap)
static uword_t gDataAxiSize = 0;
/// Tracked mmap sizes (used on unmap)
static uword_t gPtcAxiSize = 0;
/// Tracked mmap sizes (used on unmap)
static uword_t gCtpAxiSize = 0;

/*!
 * \brief Open /dev/mem with O_RDWR|O_SYNC or exit with a clear error message.
 */
static int OpenDevMem()
{
  int fd = ::open("/dev/mem", O_RDWR | O_SYNC);
  return fd;
}

/*--------------------------- System Reset window mapping ----------------------*/

uword_t SetupSysResetAxi4()
{
  int fd = OpenDevMem();
  if (fd < 0)
  {
    return FAILURE;
  }
  void* base = ::mmap(nullptr, SYS_RESET_RAM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FIC0_START_ADDR + SYS_RESET_START_ADDR);
  ::close(fd);

  if (base == MAP_FAILED)
  {
    return FAILURE;
  }

  gSysResetAxiBase = reinterpret_cast<volatile uword_t*>(base);
  gSysResetAxiSize = SYS_RESET_RAM_SIZE;

  return SUCCESS;
}

void FinalizeSysResetAxi4()
{
  if (gSysResetAxiBase)
  {
    ::munmap((void*)gSysResetAxiBase, gSysResetAxiSize);
    gSysResetAxiBase = nullptr;
    gSysResetAxiSize = 0;
  }
}

uword_t SysResetAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t size, AxiBurst mode)
{
  uword_t localAddr = addr - SYS_RESET_START_ADDR;

  if (gSysResetAxiBase == nullptr)
  {
    return INVALID_ADDR;
  }
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }
  if (!IsAligned(localAddr, size, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  volatile uword_t* p     = gSysResetAxiBase + static_cast<uintptr_t>(localAddr) / NB_BYTES_IN_WORD;
  const size_t      beats = static_cast<size_t>(size / NB_BYTES_IN_WORD);
  for (size_t i = 0; i < beats; ++i)
  {
    *p = data[i];
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

uword_t SysResetAxi4Read(const uintptr_t addr, uword_t* data, const uword_t size, AxiBurst mode)
{
  uword_t localAddr = addr - SYS_RESET_START_ADDR;

  if (gSysResetAxiBase == nullptr)
  {
    return INVALID_ADDR;
  }
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }
  if (!IsAligned(localAddr, size, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  volatile const uword_t* p     = gSysResetAxiBase + static_cast<uintptr_t>(localAddr) / NB_BYTES_IN_WORD;
  const size_t            beats = static_cast<size_t>(size / NB_BYTES_IN_WORD);
  for (size_t i = 0; i < beats; ++i)
  {
    data[i] = *p;
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

/*--------------------------- Instruction window mapping ----------------------*/

uword_t SetupInstrAxi4()
{
  int fd = OpenDevMem();
  if (fd < 0)
  {
    return FAILURE;
  }
  void* base = ::mmap(nullptr, INSTR_RAM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FIC0_START_ADDR + INSTR_RAM_START_ADDR);
  ::close(fd);

  if (base == MAP_FAILED)
  {
    return FAILURE;
  }

  gInstrAxiBase = reinterpret_cast<volatile uint32_t*>(base);
  gInstrAxiSize = INSTR_RAM_SIZE;

  return SUCCESS;
}

void FinalizeInstrAxi4()
{
  if (gInstrAxiBase)
  {
    ::munmap((void*)gInstrAxiBase, gInstrAxiSize);
    gInstrAxiBase = nullptr;
    gInstrAxiSize = 0;
  }
}

uword_t InstrAxi4Write(const uintptr_t addr, const uint32_t* data, const uword_t size, AxiBurst mode)
{
  uword_t localAddr = addr - INSTR_RAM_START_ADDR;

  if (gInstrAxiBase == nullptr)
  {
    return INVALID_ADDR;
  }
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }
  if (!IsAligned(localAddr, size, 4))
  {
    return ADDR_NOT_ALIGNED;
  }

  volatile uint32_t* p     = gInstrAxiBase + static_cast<uintptr_t>(localAddr) / 4;
  const size_t       beats = static_cast<size_t>(size / 4);
  for (size_t i = 0; i < beats; ++i)
  {
    *p = data[i];
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

uword_t InstrAxi4Read(const uintptr_t addr, uint32_t* data, const uword_t size, AxiBurst mode)
{
  uword_t localAddr = addr - INSTR_RAM_START_ADDR;

  if (gInstrAxiBase == nullptr)
  {
    return INVALID_ADDR;
  }
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }
  if (!IsAligned(localAddr, size, 4))
  {
    return ADDR_NOT_ALIGNED;
  }

  volatile const uint32_t* p     = gInstrAxiBase + static_cast<uintptr_t>(localAddr) / 4;
  const size_t            beats = static_cast<size_t>(size / 4);
  for (size_t i = 0; i < beats; ++i)
  {
    data[i] = *p;
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

/*------------------------------- Data window mapping -------------------------*/

uword_t SetupDataAxi4()
{
  int fd = OpenDevMem();
  if (fd < 0)
  {
    return FAILURE;
  }
  void* base = ::mmap(nullptr, DATA_RAM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FIC0_START_ADDR + DATA_RAM_START_ADDR);
  ::close(fd);

  if (base == MAP_FAILED)
  {
    return FAILURE;
  }

  gDataAxiBase = reinterpret_cast<volatile uword_t*>(base);
  gDataAxiSize = DATA_RAM_SIZE;

  return SUCCESS;
}

void FinalizeDataAxi4()
{
  if (gDataAxiBase)
  {
    ::munmap((void*)(gDataAxiBase), gDataAxiSize);
    gDataAxiBase = nullptr;
    gDataAxiSize = 0;
  }
}

uword_t DataAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t size, AxiBurst mode)
{
  uword_t localAddr = addr - DATA_RAM_START_ADDR;

  if (gDataAxiBase == nullptr)
  {
    LogPrintf("INVALID_ADDR\n");
    return INVALID_ADDR;
  }
  if (data == nullptr || size == 0u)
  {
    LogPrintf("addr %p size %lx\n", data, size);
    return FAILURE;
  }
  if (!IsAligned(localAddr, size, NB_BYTES_IN_WORD))
  {
    LogPrintf("ADDR_NOT_ALIGNED\n");
    return ADDR_NOT_ALIGNED;
  }

  /*
  * Without usleep, the platform writes data and waits for an AXI response indefinitely.
  * I think it is due to the poorly handled AXI4 FSM inside memory modules.
  * As this is not the main topic of this project, I will keep this software fix for now.
  */
  volatile uword_t* p     = gDataAxiBase + static_cast<uintptr_t>(localAddr) / NB_BYTES_IN_WORD;
  const size_t      beats = static_cast<size_t>(size / NB_BYTES_IN_WORD);
  for (size_t i = 0; i < beats; ++i)
  {
    *p = data[i];
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

uword_t DataAxi4Read(const uintptr_t addr, uword_t* data, const uword_t size, AxiBurst mode)
{
  uword_t localAddr = addr - DATA_RAM_START_ADDR;

  if (gDataAxiBase == nullptr)
  {
    return INVALID_ADDR;
  }
  if (data == nullptr || size == 0u)
  {
    return FAILURE;
  }
  if (!IsAligned(localAddr, size, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  volatile const uword_t* p     = gDataAxiBase + static_cast<uintptr_t>(localAddr) / NB_BYTES_IN_WORD;
  const size_t            beats = static_cast<size_t>(size / NB_BYTES_IN_WORD);
  for (size_t i = 0; i < beats; ++i)
  {
    data[i] = *p;
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

/*------------------------------- Platform-to-Core window mapping -------------------------*/

uword_t SetupPtcAxi4()
{
  int fd = OpenDevMem();
  if (fd < 0)
  {
    return FAILURE;
  }
  void* base = ::mmap(nullptr, PTC_FIFO_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FIC0_START_ADDR + PTC_FIFO_START_ADDR);
  ::close(fd);

  if (base == MAP_FAILED)
  {
    return FAILURE;
  }

  gPtcAxiBase = reinterpret_cast<volatile uword_t*>(base);
  gPtcAxiSize = PTC_FIFO_SIZE;

  return SUCCESS;
}

void FinalizePtcAxi4()
{
  if (gPtcAxiBase)
  {
    ::munmap((void*)(gPtcAxiBase), gPtcAxiSize);
    gPtcAxiBase = nullptr;
    gPtcAxiSize = 0;
  }
}

uword_t PtcAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t nb_words, AxiBurst mode)
{
  uword_t localAddr = addr - PTC_FIFO_START_ADDR;

  if (gPtcAxiBase == nullptr)
  {
    return INVALID_ADDR;
  }
  if (data == nullptr || nb_words == 0u)
  {
    return FAILURE;
  }
  if (!IsAligned(localAddr, nb_words*NB_BYTES_IN_WORD, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  /*
  * Without usleep, the platform writes data and waits for an AXI response indefinitely.
  * I think it is due to the poorly handled AXI4 FSM inside memory modules.
  * As this is not the main topic of this project, I will keep this software fix for now.
  */
  volatile uword_t* p     = gPtcAxiBase + static_cast<uintptr_t>(localAddr) / NB_BYTES_IN_WORD;
  const size_t      beats = nb_words;
  for (size_t i = 0; i < beats; ++i)
  {
    *p = data[i];
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

uword_t PtcAxi4Read(const uintptr_t addr, uword_t* data, const uword_t nb_words, AxiBurst mode)
{
  uword_t localAddr = addr - PTC_FIFO_START_ADDR;

  if (gPtcAxiBase == nullptr)
  {
    return INVALID_ADDR;
  }
  if (data == nullptr || nb_words == 0u)
  {
    return FAILURE;
  }
  if (!IsAligned(localAddr, nb_words*NB_BYTES_IN_WORD, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  volatile const uword_t* p     = gPtcAxiBase + static_cast<uintptr_t>(localAddr) / NB_BYTES_IN_WORD;
  const size_t            beats = nb_words;
  for (size_t i = 0; i < beats; ++i)
  {
    data[i] = *p;
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

/*------------------------------- Core-to-Platform window mapping -------------------------*/

uword_t SetupCtpAxi4()
{
  int fd = OpenDevMem();
  if (fd < 0)
  {
    return FAILURE;
  }
  void* base = ::mmap(nullptr, CTP_FIFO_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, FIC0_START_ADDR + CTP_FIFO_START_ADDR);
  ::close(fd);

  if (base == MAP_FAILED)
  {
    return FAILURE;
  }

  gCtpAxiBase = reinterpret_cast<volatile uword_t*>(base);
  gCtpAxiSize = CTP_FIFO_SIZE;

  return SUCCESS;
}

void FinalizeCtpAxi4()
{
  if (gCtpAxiBase)
  {
    ::munmap((void*)(gCtpAxiBase), gCtpAxiSize);
    gCtpAxiBase = nullptr;
    gCtpAxiSize = 0;
  }
}

uword_t CtpAxi4Write(const uintptr_t addr, const uword_t* data, const uword_t nb_words, AxiBurst mode)
{
  uword_t localAddr = addr - CTP_FIFO_START_ADDR;

  if (gCtpAxiBase == nullptr)
  {
    return INVALID_ADDR;
  }
  if (data == nullptr || nb_words == 0u)
  {
    return FAILURE;
  }
  if (!IsAligned(localAddr, nb_words*NB_BYTES_IN_WORD, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  /*
  * Without usleep, the platform writes data and waits for an AXI response indefinitely.
  * I think it is due to the poorly handled AXI4 FSM inside memory modules.
  * As this is not the main topic of this project, I will keep this software fix for now.
  */
  volatile uword_t* p     = gCtpAxiBase + static_cast<uintptr_t>(localAddr) / NB_BYTES_IN_WORD;
  const size_t      beats = nb_words;
  for (size_t i = 0; i < beats; ++i)
  {
    *p = data[i];
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

uword_t CtpAxi4Read(const uintptr_t addr, uword_t* data, const uword_t nb_words, AxiBurst mode)
{
  uword_t localAddr = addr - CTP_FIFO_START_ADDR;

  if (gCtpAxiBase == nullptr)
  {
    return INVALID_ADDR;
  }
  if (data == nullptr || nb_words == 0u)
  {
    return FAILURE;
  }
  if (!IsAligned(localAddr, nb_words*NB_BYTES_IN_WORD, NB_BYTES_IN_WORD))
  {
    return ADDR_NOT_ALIGNED;
  }

  volatile const uword_t* p     = gCtpAxiBase + static_cast<uintptr_t>(localAddr) / NB_BYTES_IN_WORD;
  const size_t            beats = nb_words;
  for (size_t i = 0; i < beats; ++i)
  {
    data[i] = *p;
    if(mode != AxiBurst::Fixed) { p++; }
  }

  return SUCCESS;
}

#endif // SIM / Platform
