// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       clocks_resets.h
\brief      Clock and reset control API for the Verilator DUT (Vriscv_core_harness)
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Lightweight helpers to drive the DUT clocks and resets from the simulation
  harness. Both core and AXI clocks are kept in phase. Resets are active-low.

  These functions do not call `eval()` nor dump waves; advancing simulation
  time is centralized elsewhere (e.g., `cycle()`), to keep a single timing
  authority in the testbench.

\remarks
  - Active-low resets: passing 0 asserts reset; passing 1 de-asserts reset.
  - No side effects beyond writing DUT pins; no time advancement.

\section clocks_resets_h_version_history Version history
| Version | Date       | Author     | Description      |
|:-------:|:----------:|:-----------|:-----------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version. |
********************************************************************************
*/

#ifndef CLOCKS_RESETS_H
#define CLOCKS_RESETS_H

#include <cstdint>

/*!
 * \brief Drive both core and AXI clocks to a specific logic level.
 *
 * Sets `core_clk_i` and `axi_clk_i` to the same value. Any non-zero input is
 * treated as logic 1. This function does **not** call `eval()`; advance time
 * using your centralized simulation step (e.g., `cycle()`).
 *
 * \param[in] clk  Logic level (0 or non-zero for 1).
 */
void SetClkSignal(uint8_t clk);

/*!
 * \brief Toggle both core and AXI clocks (kept in phase).
 *
 * Flips `core_clk_i` and `axi_clk_i`. This function does **not** call `eval()`;
 * advance time with your central stepping function.
 */
void ClockTick();

/*!
 * \brief Control the AXI (“RAM”) reset (active-low).
 *
 * Writes `axi_rstn_i`. Passing 0 asserts reset; passing 1 de-asserts reset.
 * No call to `eval()` is performed here.
 *
 * \param[in] rstn  0 = assert reset, 1 = de-assert reset.
 */
void SetRamResetSignal(uint8_t rstn);

#endif
