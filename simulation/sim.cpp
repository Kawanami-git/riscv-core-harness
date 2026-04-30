// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       sim.cpp
\brief      Verilator simulation control loop (time, clock, tracing)
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Implements the simulation backend used to drive the DUT:
  - Creates/destructs the top-level Verilated model.
  - Advances time and generates clock edges.
  - Hooks optional waveform tracing (VCD) when a file name is provided.
  - Exposes small helpers for one tick, one cycle, and pure combinational eval.

  Timing model:
  - \ref Tick advances simulation time by SIM_STEP and performs one clock toggle.
  - \ref Cycle performs two ticks (one full clock period).
  - Tracing (if enabled) dumps at the two evaluation points per tick:
    pre-edge (small delta) and post-edge.

\remarks
  - \ref MAX_SIM_TIME is used as a simple timeout to avoid endless runs.
  - This file contains **internal** comments only; public briefs live in sim.h.

\section sim_cpp_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#include "sim.h"

#include <cinttypes> // PRIu64
#include <cstdio>    // std::printf

#include "Vriscv_core_harness.h"
#include "clocks_resets.h"
#include "sim_log.h"

/// Global DUT instance (shared with other simulation units)
Vriscv_core_harness* dut = nullptr;

/// Simulation time (used by Verilator tracing), advanced in steps of SIM_STEP
static uint64_t gSimTime = 0;
/// Tick counter (one Tick() toggles the clock once)
static uint64_t gTicks = 0;
/// Error counter (increment from your checks/asserts if desired)
static uint64_t gErrors = 0;
/// Waveform tracing flag
static bool gTraceOn = false;

void InitSim(const std::string& traceFilename)
{
  // Create the DUT before attaching the tracer
  dut = new Vriscv_core_harness();

  // Enable VCD tracing if a file name is provided
  if (!traceFilename.empty())
  {
    InitLogs(traceFilename);
    gTraceOn = true;
  }

  // Bring the design to a stable starting state:
  // - Cycle() gives a full period to settle internal resets/initials.
  // - Tick() provides one more edge in case the bench expects an early edge.
  Cycle();
  Tick();
}

void FinalizeSim()
{
  // Close the VCD if it was enabled
  if (gTraceOn)
  {
    FinalizeLogs();
    gTraceOn = false;
  }

  // Delete DUT
  delete dut;
  dut = nullptr;
}

void Tick()
{
  // Be tolerant to calls during startup/shutdown
  if (dut == nullptr)
  {
    return;
  }

  // Simple simulation timeout guard
  if (gSimTime >= MAX_SIM_TIME)
  {
    std::printf("SIMULATION TIMEOUT. %" PRIu64 " ERRORS DETECTED.\n", gErrors);
    if (gTraceOn)
    {
      FinalizeLogs();
    }
    delete dut;
    dut = nullptr;
    std::fflush(stdout);
    std::fflush(stderr);
    std::_Exit(0); // immediate exit; replace with std::exit(0) if you prefer unwinding
  }

  // Advance a small delta to capture pre-edge combinational behavior
  gSimTime += (SIM_STEP / 100);
  dut->eval();
  if (gTraceOn)
  {
    TraceDump(gSimTime);
  }

  // Advance to the clock edge, toggle clocks, then evaluate post-edge state
  gSimTime += 99 * (SIM_STEP / 100);
  ++gTicks;
  ClockTick(); // toggles core_clk_i and axi_clk_i
  dut->eval();
  if (gTraceOn)
  {
    TraceDump(gSimTime);
  }
}

void Cycle()
{
  // A full clock cycle = two toggles
  Tick();
  Tick();
}

void Comb()
{
  // Pure combinational evaluation without advancing time
  if (dut == nullptr)
  {
    return;
  }
  dut->eval();
}
