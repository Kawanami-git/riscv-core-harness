// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       log.h
\brief      Minimal logging helpers (file-backed, process-safe).
\author     Kawanami
\date       19/12/2025
\version    1.0

\details
  Tiny file logger with process-safe and thread-safe writes:
  - The log file is opened once by setLogFile().
  - Each write is protected by flock (processes, when
    available on the platform).
  - LogPrintf() accepts a printf-style format string.

\remarks
  - If you need timestamps or log levels, it’s easy to enrich LogPrintf()
    (see comments in the .cpp).

\section log_h_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 19/12/2025 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#ifndef LOG_H
#define LOG_H

#include <cstdint>
#include <string>

/*!
 * \brief Configure the log file path and open the file in append mode.
 * \param[in] filename  Path to the log file (created if it does not exist).
 * \return SUCCESS on success, FAILURE on error (e.g., cannot open file).
 */
std::uint32_t SetLogFile(const std::string& filename);

/*!
 * \brief Append a formatted message to the current log file.
 *
 * Thread-safe (std::mutex) and process-safe (flock, when available).
 * Does nothing if no file has been configured.
 *
 * \param[in] format  printf-style format string
 * \param[in] ...     variable arguments matching \p format
 */
void LogPrintf(const char* format, ...);

#endif // LOG_H
