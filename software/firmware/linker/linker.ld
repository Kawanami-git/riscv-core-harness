/* SPDX-License-Identifier: MIT */
/*!
********************************************************************************
\file       linker.ld
\brief      Linker script for RISC-V bare-metal firmware.

\author     Kawanami
\version    1.0
\date       28/04/2026

\details
  Defines the on-chip memory layout and section placement:
    - INSTR_RAM : executable code (.start, .text)
    - DATA_RAM  : .data, .rodata, .bss, and a fixed-size stack
    - PTC_MEM   : platform→core shared region (symbol: ptc_memory)
    - CTP_MEM   : core→platform shared region (symbol: cpt_memory)

  Also exports useful symbols:
    _data_start/_data_end, _bss_start/_bss_end,
    _stack_start/_stack_end/_stack_top,
    _heap_start/_heap_end.

\remarks
  - `_stack_top` is used by the start code to initialize `sp`.
  - Adjust `_stack_size` as needed for your firmware.
  - Section names must match the firmware build (start.s places code in `.start`).

\section linker_ld_version_history Version history
| Version | Date       | Author     | Description        |
|:-------:|:----------:|:-----------|:-------------------|
| 1.0     | 28/04/2026 | Kawanami   | Initial version.   |
********************************************************************************
*/

MEMORY {
    INSTR_RAM  (rx)  : ORIGIN = 0x00100000, LENGTH = 16K
    DATA_RAM   (rw)  : ORIGIN = 0x00140000, LENGTH = 16K
    PTC_MEM    (rw)  : ORIGIN = 0x00150000, LENGTH = 1K
    CTP_MEM    (rw)  : ORIGIN = 0x00160000, LENGTH = 1K
}

SECTIONS {
    .text : {
        KEEP(*(.start))
        *(.text*)
    } > INSTR_RAM

    .data : {
        _data_start = .;
        *(.data*)
        _data_end = .;
    } > DATA_RAM

    .rodata : {
        *(.rodata*)
    } > DATA_RAM

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        _bss_end = .;
    } > DATA_RAM

    _stack_size = 2048;
    .stack (NOLOAD) : {
        . = ORIGIN(DATA_RAM) + LENGTH(DATA_RAM) - _stack_size;
        _stack_start = .;
        . = . + _stack_size;
        _stack_end = .;
    } > DATA_RAM

    .ptc_memory ORIGIN(PTC_MEM) :
    {
        PROVIDE(ptc_memory = .);
    } > PTC_MEM

    .cpt_memory ORIGIN(CTP_MEM) :
    {
        PROVIDE(cpt_memory = .);
    } > CTP_MEM

    PROVIDE(_stack_top = _stack_end);
    PROVIDE(_heap_start = _bss_end);
    PROVIDE(_heap_end   = _stack_start);
}
