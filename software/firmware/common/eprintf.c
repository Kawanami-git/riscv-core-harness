// SPDX-License-Identifier: MIT
/*!
********************************************************************************
\file       eprintf.c
\brief      Tiny printf that writes into CTP FIFO (bare-metal).

\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Minimal embedded printf implementation.

  The formatted string is first written into a local word-aligned buffer, then
  pushed to the core-to-platform FIFO as native machine words.

  Supported format specifiers:
  - %%  : literal percent character
  - %c  : character
  - %s  : string
  - %d  : signed decimal integer
  - %u  : unsigned decimal integer
  - %x  : unsigned hexadecimal integer
  - %ld : signed long decimal integer
  - %lu : unsigned long decimal integer
  - %lx : unsigned long hexadecimal integer

\remarks
  - Field width, precision, padding, alignment, and floating-point formats are
    intentionally not supported.
  - This implementation avoids C library calls so it can be used in freestanding
    bare-metal firmware.
  - NB_BYTES_IN_WORD must match sizeof(uword_t).

\section eprintf_c_version_history Version history
| Version | Date       | Author     | Description                               |
|:-------:|:----------:|:-----------|:------------------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                          |
********************************************************************************
*/

#include "defines.h"
#include "fifo.h"

#include <stdarg.h>
#include <stdint.h>

#define EPRINTF_BUFFER_SIZE 512U

#define EPRINTF_WORD_COUNT \
  ((EPRINTF_BUFFER_SIZE + NB_BYTES_IN_WORD - 1U) / NB_BYTES_IN_WORD)

typedef struct {
  uword_t  words[EPRINTF_WORD_COUNT];
  uint32_t byte_index;
  uint32_t count;
} NewEprintf;

/*!
 * \brief Return the byte-addressable view of the internal word buffer.
 *
 * \param[in,out] wor Eprintf internal context.
 *
 * \return Byte pointer to the internal buffer.
 */
static char* EprintfBuffer(NewEprintf* wor)
{
  return (char*)wor->words;
}

/*!
 * \brief Store one character into the Eprintf buffer.
 *
 * Writes one character into the local Eprintf buffer and updates the current
 * write index. One byte is always kept available for the final null terminator.
 *
 * \param[in,out] wor Eprintf internal context.
 * \param[in]     c   Character to store.
 */
static void Ewc(NewEprintf* wor, char c)
{
  char* buffer = EprintfBuffer(wor);

  if (wor->byte_index >= (EPRINTF_BUFFER_SIZE - 1U)) {
    return;
  }

  buffer[wor->byte_index] = c;
  wor->byte_index++;

  if (c != '\0') {
    wor->count++;
  }
}

/*!
 * \brief Convert an unsigned integer to a string and write it through Ewc().
 *
 * \param[in]     num  Unsigned integer to convert.
 * \param[in]     base Conversion base.
 * \param[in,out] wor  Eprintf internal context.
 *
 * \return Number of characters written.
 */
static uint32_t Euts(unsigned long num, unsigned int base, NewEprintf* wor)
{
  uint32_t count = 0U;
  char     buffer[(3U * sizeof(unsigned long)) + 2U];
  char*    ptr = buffer + sizeof(buffer) - 1U;

  *ptr = '\0';

  do {
    *--ptr = "0123456789abcdef"[num % (unsigned long)base];
    num /= (unsigned long)base;
  } while (num != 0UL);

  while (*ptr != '\0') {
    Ewc(wor, *ptr);
    ptr++;
    count++;
  }

  return count;
}

/*!
 * \brief Convert a signed integer to a string and write it through Ewc().
 *
 * \param[in]     num  Signed integer to convert.
 * \param[in]     base Conversion base.
 * \param[in,out] wor  Eprintf internal context.
 *
 * \return Number of characters written.
 */
static uint32_t Eits(long num, unsigned int base, NewEprintf* wor)
{
  unsigned long u;
  uint32_t      count = 0U;

  if ((num < 0L) && (base == 10U)) {
    Ewc(wor, '-');
    count++;

    u = 0UL - (unsigned long)num;
  } else {
    u = (unsigned long)num;
  }

  count += Euts(u, base, wor);

  return count;
}

/*!
 * \brief Push words to the core-to-platform FIFO.
 *
 * The write is split into chunks so the function does not require the FIFO to
 * have enough free space for the complete message at once.
 *
 * \param[in] words    Pointer to words to write.
 * \param[in] nb_words Number of words to write.
 */
static void EprintfWriteWords(const uword_t* words, uword_t nb_words)
{
  uword_t written_words = 0U;

  while (written_words < nb_words) {
    uword_t free_words = CtpFifoWcount();

    if (free_words == 0U) {
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

int Eprintf(const char* fmt, ...)
{
  #ifndef NO_SPIKE
    return 0;
  #endif

  va_list    args;
  NewEprintf wor;
  char*      buffer;
  uint32_t   bytes_to_send;
  uint32_t   padded_bytes;
  uint32_t   words_to_send;
  uint32_t   i;

  wor.byte_index = 0U;
  wor.count      = 0U;
  buffer         = EprintfBuffer(&wor);

  if (fmt == 0) {
    return 0;
  }

  va_start(args, fmt);

  while (*fmt != '\0') {
    if (*fmt != '%') {
      Ewc(&wor, *fmt);
      fmt++;
      continue;
    }

    fmt++;

    if (*fmt == '\0') {
      Ewc(&wor, '%');
      break;
    }

    if (*fmt == '%') {
      Ewc(&wor, '%');
    } else if (*fmt == 'c') {
      int c = va_arg(args, int);
      Ewc(&wor, (char)c);
    } else if (*fmt == 's') {
      const char* str = va_arg(args, const char*);

      if (str == 0) {
        str = "(null)";
      }

      while (*str != '\0') {
        Ewc(&wor, *str);
        str++;
      }
    } else if (*fmt == 'd') {
      int num = va_arg(args, int);
      (void)Eits((long)num, 10U, &wor);
    } else if (*fmt == 'u') {
      unsigned int num = va_arg(args, unsigned int);
      (void)Euts((unsigned long)num, 10U, &wor);
    } else if (*fmt == 'x') {
      unsigned int num = va_arg(args, unsigned int);
      (void)Euts((unsigned long)num, 16U, &wor);
    } else if (*fmt == 'l') {
      fmt++;

      if (*fmt == 'd') {
        long num = va_arg(args, long);
        (void)Eits(num, 10U, &wor);
      } else if (*fmt == 'u') {
        unsigned long num = va_arg(args, unsigned long);
        (void)Euts(num, 10U, &wor);
      } else if (*fmt == 'x') {
        unsigned long num = va_arg(args, unsigned long);
        (void)Euts(num, 16U, &wor);
      } else if (*fmt == '\0') {
        Ewc(&wor, '%');
        Ewc(&wor, 'l');
        break;
      } else {
        Ewc(&wor, '%');
        Ewc(&wor, 'l');
        Ewc(&wor, *fmt);
      }
    } else {
      Ewc(&wor, '%');
      Ewc(&wor, *fmt);
    }

    fmt++;
  }

  va_end(args);

  buffer[wor.byte_index] = '\0';

  bytes_to_send = wor.count + 1U;

  words_to_send =
      (bytes_to_send + NB_BYTES_IN_WORD - 1U) / NB_BYTES_IN_WORD;

  padded_bytes = words_to_send * NB_BYTES_IN_WORD;

  for (i = bytes_to_send; i < padded_bytes; i++) {
    buffer[i] = '\0';
  }

  /*
  * Framed CTP message format:
  * - first word: payload size in bytes, including the final '\0'
  * - following words: payload, padded to NB_BYTES_IN_WORD
  */
  uword_t payload_size_bytes = (uword_t)bytes_to_send;

  EprintfWriteWords(&payload_size_bytes, 1U);
  EprintfWriteWords(wor.words, (uword_t)words_to_send);

  return (int)wor.count;
}
