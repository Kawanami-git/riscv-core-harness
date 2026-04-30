// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       args_parser.cpp
\brief      Implementation of the command-line argument parser.
\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  Parses a small set of long/short options to configure the simulation runtime:
  - --firmware, -f : firmware image path
  - --logfile,  -l : log output path
  - --spike,    -s : reference (Spike) trace path
  - --waveform, -w : waveform (e.g., VCD) output path
  - --help          : display usage and return

\remarks
  - TODO: extend validation and error reporting (unknown flags, missing values).

\section args_parser_cpp_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#include "args_parser.h"

#include <cstdio>   // std::printf, std::fprintf
#include <cstdlib>  // std::exit
#include <getopt.h> // getopt_long

// Optional: usage helper (not part of the public API)
void Arguments::PrintUsage(const char* progname)
{
  std::printf("Usage: %s [options]\n"
              "  -f, --firmware <path>   Firmware/binary image file\n"
              "  -l, --logfile  <path>   Log output file\n"
              "  -s, --spike    <path>   Spike golden trace file\n"
              "  -w, --waveform <path>   Waveform output file (e.g., .vcd)\n"
              "      --help              Show this help and exit\n",
              progname ? progname : "program");
}

void Arguments::Parse(int argc, char* argv[])
{
  // Table of long options
  static const struct option kLongOptions[] = {{"logfile", required_argument, nullptr, 'l'},
                                               {"firmware", required_argument, nullptr, 'f'},
                                               {"spike", required_argument, nullptr, 's'},
                                               {"waveform", required_argument, nullptr, 'w'},
                                               {"help", no_argument, nullptr, 0},
                                               {nullptr, 0, nullptr, 0}};

  // Reset getopt's global state in case Parse() is called multiple times
  optind = 1;

  for (;;)
  {
    int       long_index = 0;
    const int opt        = getopt_long(argc, argv, "l:f:s:w:", kLongOptions, &long_index);

    if (opt == -1)
    {
      break; // no more options
    }

    // Handle "--help" which comes via 'opt == 0' and kLongOptions[long_index].name == "help"
    if (opt == 0)
    {
      if (kLongOptions[long_index].name && std::string(kLongOptions[long_index].name) == "help")
      {
        this->PrintUsage(argv && argv[0] ? argv[0] : nullptr);
        std::exit(0);
      }
      // Unknown long option with flag==nullptr falls through (ignore).
      continue;
    }

    // Defensive: getopt_long guarantees optarg ≠ nullptr for required_argument,
    // but we guard anyway to avoid UB if the contract is broken.
    const char* val = (optarg != nullptr) ? optarg : "";

    switch (opt)
    {
    case 'l':
      mLogFile = val;
      break;
    case 'f':
      mFirmwareFile = val;
      break;
    case 's':
      mSpikeFile = val;
      break;
    case 'w':
      mWaveformFile = val;
      break;
    default:
      // Unknown/unsupported option: ignore silently.
      break;
    }
  }
}
