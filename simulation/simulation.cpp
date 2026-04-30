// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       simulation.cpp
\brief      Simulation entry point (standalone program runner)
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Minimal `main()` for launching a standalone simulation run:
  - parse CLI arguments,
  - initialize the simulation and waveform tracing,
  - hand off to the user `run()` entry point (defined in platform/),
  - finalize the simulation cleanly.

  This binary is distinct from the Spike-based checker (see
  `simulation_vs_spike.cpp`).

\remarks
  - Requires a waveform filename (`--waveform <file>`) to enable tracing.
  - `run()` performs the detailed scenario (loading firmware, I/O loop, etc.).

\section simulation_cpp_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#include "simulation.h"

#include <cstdio>
#include <cstdlib>

#include "args_parser.h"
#include "defines.h"
#include "sim.h"
#include "sim_log.h"

int main(int argc, char** argv, char** /*env*/)
{
  // Parse CLI flags (log/firmware/waveform…)
  Arguments args;
  args.Parse(argc, argv);

  // Require a waveform path for tracing; keep usage message concise.
  if (args.GetWaveformFile().empty())
  {
    std::fprintf(
        stderr,
        "Usage: %s --waveform <file> [--logfile <file>] [--firmware <file>] [--spike <file>]\n",
        argv[0]);
    return EXIT_FAILURE;
  }

  // Initialize simulation (alloc DUT, start tracing if requested)
  InitSim(args.GetWaveformFile());

  // Delegate to user-defined scenario (platform/)
  const unsigned int rc = run(argc, argv);

  // Always finalize the simulation stack
  FinalizeSim();

  // Map user return code to process exit status
  return (rc == SUCCESS) ? EXIT_SUCCESS : EXIT_FAILURE;
}
