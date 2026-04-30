// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       sim_log.h
\brief      VCD tracing helpers for the Verilator simulation backend
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Tiny wrapper around Verilator’s tracing API. It exposes three helpers:
  - InitLogs()     : enable tracing and open the VCD file
  - TraceDump()    : dump one timestamp into the VCD
  - FinalizeLogs() : close and release the trace

  The DUT pointer (Vriscv_core_harness* dut) is provided by the simulation harness.

\remarks
  - These helpers do not call eval(); they only manage the VCD trace.
  - Calling InitLogs() multiple times will re-open the trace file.

\section sim_log_h_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#ifndef SIM_LOG_H
#define SIM_LOG_H

#include <string>
#include <verilated.h>
#include <verilated_vcd_c.h>

/*!
 * \brief Initialize VCD tracing and open the output file.
 *
 * Enables Verilator tracing, attaches a VCD tracer to the DUT, and opens
 * the given file path. If a trace is already open, it is closed and replaced.
 *
 * \param[in] traceFilename  Path to the VCD file to create/overwrite.
 */
void InitLogs(const std::string& traceFilename);

/*!
 * \brief Dump one timestamp into the VCD trace.
 *
 * Call this after advancing simulation time (and evaluating the DUT) to record
 * the waveform state at \p simTime.
 *
 * \param[in] simTime  Current simulation time (Verilator timebase).
 */
void TraceDump(vluint64_t simTime);

/*!
 * \brief Close the VCD file and release the tracer.
 *
 * Safe to call even if InitLogs() was never called or already finalized.
 */
void FinalizeLogs();

#endif // SIM_LOG_H
