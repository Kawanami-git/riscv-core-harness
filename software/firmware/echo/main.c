// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       main.c
\brief      Echo firmware: mirrors framed PTC FIFO messages back to CTP FIFO.
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Bare-metal loop that:
    1) waits for one framed message in the Platform-to-Core FIFO,
    2) reads the payload into a local staging buffer,
    3) writes the same framed message into the Core-to-Platform FIFO.

  FIFO frame format, used in both directions:
    - word 0   : payload size in bytes
    - word 1.. : payload bytes, padded to NB_BYTES_IN_WORD

  For text messages, payload size includes the final '\\0'.

\section echo_main_c_version_history Version history
| Version | Date       | Author     | Description                         |
|:-------:|:----------:|:-----------|:------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                    |
********************************************************************************
*/

#include "defines.h"
#include "fifo.h"

#define ECHO_BUFFER_BYTES 1024U
#define ECHO_BUFFER_WORDS \
  ((ECHO_BUFFER_BYTES + NB_BYTES_IN_WORD - 1U) / NB_BYTES_IN_WORD)

static inline void BusyWait(void)
{
  for (volatile int i = 0; i < 16; ++i) {
    /* nop */
  }
}

static inline uword_t AlignUp(uword_t x, uword_t a)
{
  return (x + (a - 1U)) & ~(a - 1U);
}

static inline char* WordBufferAsBytes(uword_t* words)
{
  return (char*)words;
}

static void PtcReadWordsBlocking(uword_t* words, uword_t nb_words)
{
  uword_t read_words = 0U;

  while (read_words < nb_words) {
    uword_t available_words = PtcFifoRcount();

    if (available_words == 0U) {
      BusyWait();
      continue;
    }

    uword_t chunk_words = nb_words - read_words;

    if (chunk_words > available_words) {
      chunk_words = available_words;
    }

    (void)PtcFifoRead(&words[read_words], chunk_words);
    read_words += chunk_words;
  }
}

static void CtpWriteWordsBlocking(const uword_t* words, uword_t nb_words)
{
  uword_t written_words = 0U;

  while (written_words < nb_words) {
    uword_t free_words = CtpFifoWcount();

    if (free_words == 0U) {
      BusyWait();
      continue;
    }

    uword_t chunk_words = nb_words - written_words;

    if (chunk_words > free_words) {
      chunk_words = free_words;
    }

    (void)CtpFifoWrite(&words[written_words], chunk_words);
    written_words += chunk_words;
  }
}

static void PtcDrainWordsBlocking(uword_t nb_words)
{
  uword_t dummy = 0U;

  while (nb_words != 0U) {
    PtcReadWordsBlocking(&dummy, 1U);
    nb_words--;
  }
}

/*!
 * \brief Read one framed message from the platform-to-core FIFO.
 *
 * \param[out] words           Payload destination buffer.
 * \param[in]  max_words       Payload buffer capacity in words.
 * \param[out] payload_bytes_o Payload size in bytes.
 *
 * \return 1 on success, 0 if the frame was larger than the local buffer.
 */
static uword_t PtcReadFrameBlocking(
    uword_t* words,
    uword_t  max_words,
    uword_t* payload_bytes_o
)
{
  uword_t payload_bytes = 0U;

  while (!PtcFifoReadReady(1U)) {
    BusyWait();
  }

  (void)PtcFifoRead(&payload_bytes, 1U);

  const uword_t payload_words =
      AlignUp(payload_bytes, NB_BYTES_IN_WORD) / NB_BYTES_IN_WORD;

  if (payload_words > max_words) {
    PtcDrainWordsBlocking(payload_words);

    *payload_bytes_o = 0U;
    return 0U;
  }

  if (payload_words != 0U) {
    PtcReadWordsBlocking(words, payload_words);
  }

  *payload_bytes_o = payload_bytes;
  return 1U;
}

/*!
 * \brief Write one framed message into the core-to-platform FIFO.
 *
 * \param[in,out] words         Payload buffer.
 * \param[in]     payload_bytes Payload size in bytes.
 */
static void CtpWriteFrameBlocking(uword_t* words, uword_t payload_bytes)
{
  char* payload = WordBufferAsBytes(words);

  const uword_t payload_words =
      AlignUp(payload_bytes, NB_BYTES_IN_WORD) / NB_BYTES_IN_WORD;

  const uword_t padded_bytes = payload_words * NB_BYTES_IN_WORD;

  for (uword_t i = payload_bytes; i < padded_bytes; i++) {
    payload[i] = '\0';
  }

  CtpWriteWordsBlocking(&payload_bytes, 1U);

  if (payload_words != 0U) {
    CtpWriteWordsBlocking(words, payload_words);
  }
}

int main(void)
{
  uword_t buf[ECHO_BUFFER_WORDS];

  while (1) {
    uword_t payload_bytes = 0U;

    if (PtcReadFrameBlocking(buf, ECHO_BUFFER_WORDS, &payload_bytes)) {
      CtpWriteFrameBlocking(buf, payload_bytes);
    }
  }

  return 0;
}
