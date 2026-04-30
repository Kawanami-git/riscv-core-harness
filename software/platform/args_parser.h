// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       args_parser.h
\brief      Command-line argument parser for simulation runtime.
\author     Kawanami
\date       28/04/2026
\version    1.0

\details
  Lightweight parser used to process command-line inputs at simulation runtime.
  It extracts configuration options (firmware path, log output, waveform file,
  optional golden trace, etc.) and exposes them through a small C++ class.

\remarks
  - TODO: .

\section args_parser_h_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#ifndef ARGS_PARSER_H
#define ARGS_PARSER_H

#include <string>

/*!
 * \class Arguments
 * \brief Holds all user-provided options parsed from argv/argc.
 *
 * Typical usage:
 * \code
 *   Arguments args;
 *   args.Parse(argc, argv);
 *   if (!args.GetFirmwareFile().empty()) { ... }
 * \endcode
 */
class Arguments
{
public:
  /*!
   * \brief Parse command-line options and populate the internal fields.
   *
   * Supported flags are implementation-defined (see args_parser.cpp). The
   * parser is intentionally simple and focuses on extracting file paths and
   * basic toggles used by the simulation environment.
   *
   * \param[in] argc  Number of arguments as passed to main().
   * \param[in] argv  Argument vector as passed to main().
   */
  void Parse(int argc, char* argv[]);

  /*!
   * \brief Print a short usage message (program synopsis and supported flags).
   *
   * Displays the command-line syntax and the recognized options used by the
   * simulation environment.
   *
   * \param[in] progname  Program name to display in the usage banner
   *                      (typically argv[0]).
   */
  void PrintUsage(const char* progname);

  /*!
   * \brief Get the path of the log output file (if provided).
   * \return Reference to the selected log file path, or an empty string if unset.
   */
  inline const std::string& GetLogFile() const noexcept { return mLogFile; }

  /*!
   * \brief Get the path of the firmware/binary image.
   * \return Reference to the firmware path, or an empty string if unset.
   */
  inline const std::string& GetFirmwareFile() const noexcept { return mFirmwareFile; }

  /*!
   * \brief Get the path of the reference (Spike) trace file, if any.
   * \return Reference to the Spike trace path, or an empty string if unset.
   */
  inline const std::string& GetSpikeFile() const noexcept { return mSpikeFile; }

  /*!
   * \brief Get the path of the waveform output file (e.g., VCD/FSDB), if any.
   * \return Reference to the waveform file path, or an empty string if unset.
   */
  inline const std::string& GetWaveformFile() const noexcept { return mWaveformFile; }

private:
  /// Log filename (empty if not specified)
  std::string mLogFile;
  /// Firmware filename (empty if not specified)
  std::string mFirmwareFile;
  /// Spike golden trace filename (empty if not specified)
  std::string mSpikeFile;
  /// Waveform filename (empty if not specified)
  std::string mWaveformFile;
};

#endif // ARGS_PARSER_H
