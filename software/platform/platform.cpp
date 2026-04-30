// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       platform.cpp
\brief      Entry point for driving riscv-core-harness on SIM or Platform Linux target
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Unified main loop for two environments, selected at compile time:

  - SIM (Verilator)
    * Entry function is `run(argc, argv)` (called by the simulation harness).
    * Uses `Cycle()` to advance time and optional reset helpers from sim headers.
    * AXI helpers write directly into the simulated model (no /dev/mem).

  - Platform (Platform Linux target)
    * Entry function is `main(argc, argv)`.
    * Maps AXI regions with `/dev/mem` via AXI setup helpers.

  Behavior:
    * Parses CLI options (log file, firmware path, etc.) with `Arguments`.
    * Configures the logger (append mode).
    * Loads the firmware text file (addr:data) into INSTR/DATA RAMs.
    * Enters a polling loop to relay stdin to the core and print core messages.

  All AXI addresses passed to helpers are **window-relative** offsets
  (consistent with the rest of the software stack).

\remarks
  - On SIM builds, `run()` is exported (instead of `main()`) for the harness.
  - Use 'q' + Enter in the console to quit the loop gracefully.

\section platform_cpp_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#ifdef SIM
#include "clocks_resets.h"
#include "sim.h"
#endif

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <sys/select.h>
#include <unistd.h>

#include "args_parser.h"
#include "axi4.h"
#include "defines.h"
#include "fifo.h"
#include "load.h"
#include "log.h"
#include "memory.h"


/// Size of the I/O buffer, in bytes.
static constexpr uword_t IO_BUFFER_BYTES = 1024U;

/// Size of the I/O buffer, rounded up to a whole number of machine words.
static constexpr uword_t IO_BUFFER_WORDS =
    (IO_BUFFER_BYTES + NB_BYTES_IN_WORD - 1U) / NB_BYTES_IN_WORD;

/// Align up 'x' to the next multiple of 'a' (a must be power of 2).
static inline uword_t AlignUp(uword_t x, uword_t a)
{
  return (x + (a - 1U)) & ~(a - 1U);
}

/*!
 * \brief Convert a word buffer to a byte buffer.
 *
 * \param[in,out] words Word-aligned buffer.
 *
 * \return Byte-addressable pointer to the same storage.
 */
static inline unsigned char* WordBufferAsBytes(uword_t* words)
{
  return reinterpret_cast<unsigned char*>(words);
}

/*!
 * \brief Execute a small idle step while waiting for a FIFO.
 */
static inline void IdleStep(void)
{
#ifdef SIM
  for (int i = 0; i < 50; ++i)
  {
    Cycle();
  }
#else
  usleep(1000);
#endif
}

/*!
 * \brief Write words to the platform-to-core FIFO.
 *
 * The write is split into chunks so it does not require the FIFO to have enough
 * free space for the complete message at once.
 *
 * \param[in] words    Pointer to words to write.
 * \param[in] nb_words Number of words to write.
 */
static void WritePtcWords(const uword_t* words, uword_t nb_words)
{
  uword_t written_words = 0U;

  while (written_words < nb_words)
  {
    uword_t free_words = PtcFifoWcount();

    if (free_words == 0U)
    {
      IdleStep();
      continue;
    }

    uword_t chunk_words = nb_words - written_words;

    if (chunk_words > free_words)
    {
      chunk_words = free_words;
    }

    (void)PtcFifoWrite(&words[written_words], chunk_words);
    written_words += chunk_words;
  }
}

static bool ReadCtpFramedMessage(uword_t* words, uword_t max_words, uword_t* payload_bytes_o)
{
  uword_t payload_bytes = 0U;

  // Wait for the frame header.
  while (!CtpFifoReadReady(1U))
  {
    IdleStep();
  }

  (void)CtpFifoRead(&payload_bytes, 1U);

  if (payload_bytes == 0U)
  {
    *payload_bytes_o = 0U;
    return true;
  }

  const uword_t payload_words =
      (payload_bytes + NB_BYTES_IN_WORD - 1U) / NB_BYTES_IN_WORD;

  if (payload_words > max_words)
  {
    /*
     * Message is larger than the local buffer.
     * Drain it to keep the FIFO stream synchronized, but report failure.
     */
    uword_t dummy;
    uword_t remaining_words = payload_words;

    while (remaining_words != 0U)
    {
      while (!CtpFifoReadReady(1U))
      {
        IdleStep();
      }

      (void)CtpFifoRead(&dummy, 1U);
      remaining_words--;
    }

    *payload_bytes_o = 0U;
    return false;
  }

  uword_t read_words = 0U;

  while (read_words < payload_words)
  {
    uword_t available_words = CtpFifoRcount();

    if (available_words == 0U)
    {
      IdleStep();
      continue;
    }

    uword_t chunk_words = payload_words - read_words;

    if (chunk_words > available_words)
    {
      chunk_words = available_words;
    }

    (void)CtpFifoRead(&words[read_words], chunk_words);
    read_words += chunk_words;
  }

  *payload_bytes_o = payload_bytes;
  return true;
}

/*!
 * \brief Write one framed message to the platform-to-core FIFO.
 *
 * Frame format:
 * - first word: payload size in bytes
 * - following words: payload bytes padded to NB_BYTES_IN_WORD
 *
 * \param[in,out] words         Word-aligned payload buffer.
 * \param[in]     payload_bytes Payload size in bytes.
 */
static void WritePtcFramedMessage(uword_t* words, uword_t payload_bytes)
{
  unsigned char* bytes = WordBufferAsBytes(words);

  const uword_t payload_words =
      AlignUp(payload_bytes, NB_BYTES_IN_WORD) / NB_BYTES_IN_WORD;

  const uword_t padded_bytes = payload_words * NB_BYTES_IN_WORD;

  for (uword_t i = payload_bytes; i < padded_bytes; i++)
  {
    bytes[i] = '\0';
  }

  WritePtcWords(&payload_bytes, 1U);
  WritePtcWords(words, payload_words);
}

#ifdef SIM
/**
 * \brief Simulation entry (called by the harness).
 */
unsigned int run(int argc, char** argv)
{
  uword_t stdin_bytes = 0U;
  uword_t stdin_words = 0U;
  uword_t ctp_words   = 0U;
  uword_t ctp_bytes   = 0U;

  uword_t io_words[IO_BUFFER_WORDS];
  unsigned char* buf = WordBufferAsBytes(io_words);

  Arguments args;

  std::memset(io_words, 0, sizeof(io_words));

  // Optional: assert RAM reset (provided by your sim integration).
  SetRamResetSignal(1);
#else
/**
 * \brief Platform entry (PolarFire Linux target).
 */
int main(int argc, char** argv)
{
  uword_t stdin_bytes = 0U;
  uword_t stdin_words = 0U;
  uword_t ctp_words   = 0U;
  uword_t ctp_bytes   = 0U;

  uword_t io_words[IO_BUFFER_WORDS];
  unsigned char* buf = WordBufferAsBytes(io_words);

  Arguments args;

  std::memset(io_words, 0, sizeof(io_words));

  // Map the AXI regions we'll use. Errors are handled by return codes.
  if (SetupSysResetAxi4() != SUCCESS)
  {
    std::cout << "Error: SetupSysResetAxi4 failed." << std::endl;
    goto clean;
  }

  if (SetupInstrAxi4() != SUCCESS)
  {
    std::cout << "Error: SetupInstrAxi4 failed." << std::endl;
    goto clean;
  }

  if (SetupDataAxi4() != SUCCESS)
  {
    std::cout << "Error: SetupDataAxi4 failed." << std::endl;
    goto clean;
  }

  if (SetupPtcAxi4() != SUCCESS)
  {
    std::cout << "Error: SetupPtcAxi4 failed." << std::endl;
    goto clean;
  }

  if (SetupCtpAxi4() != SUCCESS)
  {
    std::cout << "Error: SetupCtpAxi4 failed." << std::endl;
    goto clean;
  }
#endif

  // Parse CLI options.
  args.Parse(argc, argv);

  // Init logger in append mode.
  if (SetLogFile(args.GetLogFile()) != SUCCESS)
  {
    std::cout << "Error: unable to open log file: " << args.GetLogFile() << std::endl;
    goto clean;
  }

  // Load firmware into INSTR/DATA RAMs.
  if (LoadFirmware(args.GetFirmwareFile()) != SUCCESS)
  {
    LogPrintf("Error: unable to load firmware: %s\n", args.GetFirmwareFile().c_str());
    goto clean;
  }

  /*----------------------------------------------------------------------------
   * Main polling loop
   *
   * Monitors:
   *  - stdin  : user input to send to PTC FIFO, platform -> core
   *  - CTP FIFO: messages from core -> platform
   *----------------------------------------------------------------------------*/
  std::printf("Starting %s...\n\n",
#ifdef SIM
              "simulation"
#else
              "platform session"
#endif
  );

  while (true)
  {
    // Setup poll on STDIN with a short timeout.
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(STDIN_FILENO, &fds);

    timeval tv{};
    tv.tv_sec  = 0;
    tv.tv_usec = 10000; // 10 ms

    const int ready = select(STDIN_FILENO + 1, &fds, nullptr, nullptr, &tv);

    if (ready > 0 && FD_ISSET(STDIN_FILENO, &fds))
    {
      // Read user input. Keep one byte available for the final null terminator.
      const ssize_t n = ::read(STDIN_FILENO, buf, IO_BUFFER_BYTES - 1U);

      if (n <= 0)
      {
        // EOF or error; treat as graceful exit.
        break;
      }

      // 'q' + Enter (n == 2 and buf[0] == 'q') -> exit.
      if (n == 2 && buf[0] == 'q')
      {
        break;
      }

      // Null-terminate for logging and for the softcore command string.
      buf[n] = '\0';
      LogPrintf("Send: %s", buf);

      // Include the null terminator in the framed FIFO payload.
      const uword_t payload_bytes = static_cast<uword_t>(n) + 1U;

      WritePtcFramedMessage(io_words, payload_bytes);

      std::memset(io_words, 0, sizeof(io_words));
    }
    else if (CtpFifoReadReady(1U))
    {
      uword_t payload_bytes = 0U;

      std::memset(io_words, 0, sizeof(io_words));

      if (ReadCtpFramedMessage(io_words, IO_BUFFER_WORDS, &payload_bytes))
      {
        if (payload_bytes == 0U)
        {
          buf[0] = '\0';
        }
        else if (payload_bytes >= IO_BUFFER_BYTES)
        {
          buf[IO_BUFFER_BYTES - 1U] = '\0';
        }
        else
        {
          /*
           * payload_bytes includes the final '\0' sent by Eprintf.
           * Force it again locally for safety.
           */
          buf[payload_bytes - 1U] = '\0';
        }

        LogPrintf("Receive: %s\n", buf);
        std::printf("%s", buf);
        std::fflush(stdout);
      }
      else
      {
        LogPrintf("Error: received CTP frame is too large for local buffer.\n");
        std::printf("Error: received CTP frame is too large for local buffer.\n");
        std::fflush(stdout);
      }

      std::memset(io_words, 0, sizeof(io_words));
    }
#ifdef SIM
    else
    {
      // In simulation, tick the DUT when idle to keep things moving.
      IdleStep();
    }
#endif
  }

clean:
#ifndef SIM
  // Clean unmap on platform builds.
  FinalizeInstrAxi4();
  FinalizeSysResetAxi4();
  FinalizeDataAxi4();
  FinalizePtcAxi4();
  FinalizeCtpAxi4();
#endif

  return SUCCESS;
}
