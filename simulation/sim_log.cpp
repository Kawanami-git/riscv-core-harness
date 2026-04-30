// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       sim_log.cpp
\brief      VCD tracing helpers for the Verilator simulation backend
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Implementation of the helpers declared in \ref sim_log.h.
  This module only manages the Verilator VCD tracer lifecycle; it does not
  advance time nor evaluate the DUT.

\section sim_log_cpp_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#include "sim_log.h"

#include <cstdio>  // std::fprintf
#include <utility> // std::exchange

#include "Vriscv_core_harness.h"

/// Provided by the simulation harness (top-level testbench)
extern Vriscv_core_harness* dut;

/// Single tracer instance for the whole simulation.
static VerilatedVcdC* gTrace = nullptr;

void InitLogs(const std::string& traceFilename)
{
  // If a trace is already active, close and discard it first.
  if (gTrace != nullptr)
  {
    gTrace->close();
    delete gTrace;
    gTrace = nullptr;
  }

  // Enable tracing globally. This must be done before trace() attachment.
  Verilated::traceEverOn(true);

  // Allocate a new tracer and attach it to the DUT.
  gTrace = new VerilatedVcdC();

  // Defensive: check DUT is available before attaching.
  if (dut == nullptr)
  {
    std::fprintf(stderr, "[InitLogs] DUT pointer is null, cannot attach trace.\n");
    delete std::exchange(gTrace, nullptr);
    return;
  }

  // Depth = 5 is usually enough for typical designs; increase if needed.
  dut->trace(gTrace, 5);

  // Open the VCD file. If open fails, Verilator will typically abort; we guard anyway.
  gTrace->open(traceFilename.c_str());
}

void TraceDump(vluint64_t simTime)
{
  // If tracing isn’t initialized, just ignore the request to stay robust.
  if (gTrace == nullptr)
  {
    return;
  }

  // Dump one timestamp. The caller is responsible for calling eval() before this.
  gTrace->dump(simTime);
}

void FinalizeLogs()
{
  if (gTrace == nullptr)
  {
    return;
  }

  // Close VCD, free tracer, and clear the pointer.
  gTrace->close();
  delete gTrace;
  gTrace = nullptr;
}
