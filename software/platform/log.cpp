// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       log.cpp
\brief      Minimal file-backed logger (thread- & process-safe)

\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Implementation of a tiny logging facility used across the riscv-core-harness
  runtime. The logger:
    - Opens the log file once in append mode via SetLogFile().
    - Serializes writes across threads with a mutex.
    - Uses flock(2) when available to serialize writes across processes.
    - Flushes on every call to avoid losing messages on crashes.

  The public API is intentionally small:
    - SetLogFile(path) : configure/open the destination file.
    - LogPrintf(fmt, ...) : append a formatted message.
    - LogClose() : flush and close the file (optional).

  The implementation keeps the FILE* open for the program lifetime (unless
  LogClose() is called), which avoids the overhead of open/close per message.

\remarks
  - On non-POSIX platforms, flock is a no-op; thread-safety remains via mutex.
  - If you need timestamps or log levels, prepend in LogPrintf() before
    vfprintf() (see comments in the source).
  - The header-only constants (e.g., SUCCESS/FAILURE) come from defines.h.

\section log_cpp_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

// SPDX-License-Identifier: MIT
#include "log.h"

#include <cstdarg>
#include <cstdio>
#include <mutex>
#include <string>

#include "defines.h"

#if defined(__unix__) || defined(__APPLE__)
#define LOG_HAVE_FLOCK 1
#include <sys/file.h>
#include <unistd.h>
#else
#define LOG_HAVE_FLOCK 0
#endif

// Avoid global 'using namespace std;' in headers; keep symbols qualified here.
namespace
{
// Current log path (for info/debug only).
std::string gLogPath;

// Open FILE* kept for the lifetime of the logger.
std::FILE* gLogFile = nullptr;

// Thread-safety across LogPrintf() calls.
std::mutex gLogMutex;

// Small RAII guard for flock/lock/unlock on POSIX, no-op elsewhere.
struct FileLockGuard
{
  explicit FileLockGuard(std::FILE* f) : file(f)
  {
#if LOG_HAVE_FLOCK
    if (file)
    {
      ::flock(::fileno(file), LOCK_EX);
    }
#endif
  }
  ~FileLockGuard()
  {
#if LOG_HAVE_FLOCK
    if (file)
    {
      ::flock(::fileno(file), LOCK_UN);
    }
#endif
  }
  std::FILE* file;
};
} // namespace

std::uint32_t SetLogFile(const std::string& filename)
{
  std::lock_guard<std::mutex> lk(gLogMutex);

  // Close any previous file.
  if (gLogFile)
  {
    std::fflush(gLogFile);
    std::fclose(gLogFile);
    gLogFile = nullptr;
  }

  // Open once in append mode; create if missing.
#if defined(_WIN32)
  gLogFile = std::fopen(filename.c_str(), "ab"); // binary append on Windows
#else
  gLogFile = std::fopen(filename.c_str(), "a");
#endif

  if (!gLogFile)
  {
    gLogPath.clear();
    return FAILURE;
  }

  // Optional: line-buffer the stream for faster flushes per line.
  // If you want immediate writes, use _IONBF (no buffering).
  std::setvbuf(gLogFile, nullptr, _IOLBF, 0);

  gLogPath = filename;
  return SUCCESS;
}

void LogPrintf(const char* format, ...)
{
  if (!format)
  {
    return;
  }

  std::lock_guard<std::mutex> lk(gLogMutex);
  if (!gLogFile)
  {
    return;
  }

  // Process-safe region (shared between processes using the same file).
  FileLockGuard flock_guard(gLogFile);

  // If you want timestamps/levels, prepend here (strftime/gettimeofday etc.)
  // Example:
  // std::fprintf(gLogFile, "[%ld.%03ld] ", sec, msec);

  va_list args;
  va_start(args, format);
  std::vfprintf(gLogFile, format, args);
  va_end(args);

  // Ensure the message reaches disk promptly (useful for crash scenarios).
  std::fflush(gLogFile);
}

void LogClose()
{
  std::lock_guard<std::mutex> lk(gLogMutex);
  if (!gLogFile)
  {
    return;
  }

  std::fflush(gLogFile);
  std::fclose(gLogFile);
  gLogFile = nullptr;
  gLogPath.clear();
}
