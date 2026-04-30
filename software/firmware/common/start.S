/* SPDX-License-Identifier: MIT */
/*!
********************************************************************************
\file       start.S
\brief      Minimal RISC-V firmware entry (stack init + call main, then halt).
\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Sets the stack pointer to _stack_top, calls main, and then halts
  by looping forever.
  When building for Spike, an optional termination sequence is appended
  (tohost write + ebreak) to support golden-trace workflows.

\remarks
  - _stack_top must be provided by the linker script.
  - Runs in machine mode by default (platform dependent).
  - The .S extension enables the C preprocessor, allowing #ifdef SPIKE.

\section start_s_version_history Version history
| Version | Date       | Author     | Description                      |
|:-------:|:----------:|:-----------|:---------------------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.                 |
********************************************************************************
*/

.section .start, "ax", @progbits
.globl _start
.globl main

_start:
    # Clear registers that Spike initializes (for deterministic traces).
    addi x5,  x0, 0
    addi x10, x0, 0
    addi x11, x0, 0

    # Initialize stack and jump into C entry point.
    la      sp, _stack_top
    call    main

#ifdef SPIKE
    # Terminate Spike test by writing to tohost, then issuing ebreak.
    la  t1, tohost
    li  t2, 1
    sw  t2, 0(t1)
    ebreak
#endif

1:
    # If main returns, halt by looping forever.
    j       1b

#ifdef SPIKE
.section .tohost, "aw", @progbits
.globl tohost, fromhost
.balign 8

tohost:   .dword 0
fromhost: .dword 0
#endif
