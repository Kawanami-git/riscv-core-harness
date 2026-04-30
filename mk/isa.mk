# SPDX-License-Identifier: MIT
# /*!
# ********************************************************************************
# \file       isa.mk
# \brief      RISC-V ISA configuration and YAML test selection helpers.
# \author     Kawanami
# \version    1.0
# \date       28/04/2026
#
# \details
#   This Makefile fragment centralizes RISC-V ISA-related configuration for
#   riscv-core-harness.
#
#   It provides:
#     - GCC-compatible ISA string handling,
#     - XLEN and ABI derivation,
#     - compact ISA extension parsing,
#     - G extension expansion,
#     - ISA extension to YAML test directory mapping,
#     - RV32/RV64-specific YAML filtering,
#     - a debug target to print the decoded ISA configuration.
#
#   The ISA variable is intentionally kept compatible with GCC `-march` syntax,
#   for example:
#     - rv32i_zicntr
#     - rv32imac
#     - rv32gc_zicntr
#     - rv64imac_zicntr
#
# \remarks
#   - This file is intended to be included before common build and simulation
#     targets that depend on XLEN, CPU_XLEN, ABI, or ISA_YAML_FILES.
#   - Integer ABIs are selected by default. Hard-float ABIs can be selected by
#     overriding ABI from the command line.
#   - The YAML directory mapping is tolerant to both lowercase and *_instr naming
#     conventions to ease future extension additions.
#
# \section isa_mk_version_history Version history
# | Version | Date       | Author   | Description      |
# |:-------:|:----------:|:---------|:-----------------|
# | 1.0     | 28/04/2026 | Kawanami | Initial version. |
# ********************************************************************************
# */


#################################### RISC-V ISA Configuration ####################################

# GCC-compatible RISC-V architecture string.
ISA ?= rv32i_zicntr

# ISA string split on underscores, separating base ISA from multi-letter extensions.
ISA_PARTS := $(subst _, ,$(ISA))

# Base ISA field, such as rv32i, rv32imac, rv32gc, rv64i, or rv64imac.
RISCV_BASE_ARCH := $(firstword $(ISA_PARTS))

# Derive XLEN, CPU_XLEN, and default ABI from the base ISA.
ifeq ($(findstring rv32,$(RISCV_BASE_ARCH)),rv32)
XLEN := XLEN32
CPU_XLEN := 32
ABI ?= ilp32
else ifeq ($(findstring rv64,$(RISCV_BASE_ARCH)),rv64)
XLEN := XLEN64
CPU_XLEN := 64
ABI ?= lp64
else
$(error Unsupported ISA: $(ISA))
endif

# Compact extension string with the rv32/rv64 prefix removed.
RISCV_BASE_EXTS_RAW := $(patsubst rv32%,%,$(patsubst rv64%,%,$(RISCV_BASE_ARCH)))

# Compact single-letter extension list split into individual letters.
RISCV_BASE_EXTS_SPLIT := $(strip $(shell printf '%s' '$(RISCV_BASE_EXTS_RAW)' | sed 's/./& /g'))

# Multi-letter extensions extracted from the GCC ISA string.
RISCV_EXTRA_EXTS := $(wordlist 2,$(words $(ISA_PARTS)),$(ISA_PARTS))

# Expansion of the RISC-V G extension.
ifneq ($(filter g,$(RISCV_BASE_EXTS_SPLIT)),)
RISCV_G_EXTENSIONS := i m a f d zicsr zifencei
else
RISCV_G_EXTENSIONS :=
endif

# Final decoded ISA extension list used by the harness.
ISA_EXTENSIONS := $(sort \
	$(filter-out g,$(RISCV_BASE_EXTS_SPLIT)) \
	$(RISCV_G_EXTENSIONS) \
	$(RISCV_EXTRA_EXTS))

####################################                          ####################################


#################################### ISA YAML Test Selection ####################################

# Normalized root directory containing ISA YAML descriptions.
ISA_YAML_ROOT = $(patsubst %/,%,$(ISA_YAML_DIR))

# Helper macro returning all YAML files found recursively in a directory.
find_yaml = $(sort $(shell find "$(1)" -type f -name "*.yaml" 2>/dev/null))

# YAML directories associated with the base integer extension.
ISA_EXT_i_YAML_DIRS = $(ISA_YAML_ROOT)/i

# YAML directories associated with the multiplication/division extension.
ISA_EXT_m_YAML_DIRS = $(ISA_YAML_ROOT)/m $(ISA_YAML_ROOT)/M_instr

# YAML directories associated with the atomic extension.
ISA_EXT_a_YAML_DIRS = $(ISA_YAML_ROOT)/a $(ISA_YAML_ROOT)/A_instr

# YAML directories associated with the single-precision floating-point extension.
ISA_EXT_f_YAML_DIRS = $(ISA_YAML_ROOT)/f $(ISA_YAML_ROOT)/F_instr

# YAML directories associated with the double-precision floating-point extension.
ISA_EXT_d_YAML_DIRS = $(ISA_YAML_ROOT)/d $(ISA_YAML_ROOT)/D_instr

# YAML directories associated with the compressed instruction extension.
ISA_EXT_c_YAML_DIRS = $(ISA_YAML_ROOT)/c $(ISA_YAML_ROOT)/C_instr

# YAML directories associated with the control and status register extension.
ISA_EXT_zicsr_YAML_DIRS = $(ISA_YAML_ROOT)/zicsr $(ISA_YAML_ROOT)/Zicsr_instr

# YAML directories associated with the instruction-fetch fence extension.
ISA_EXT_zifencei_YAML_DIRS = $(ISA_YAML_ROOT)/zifencei $(ISA_YAML_ROOT)/Zifencei_instr

# YAML directories associated with the base counter/timer extension.
ISA_EXT_zicntr_YAML_DIRS = $(ISA_YAML_ROOT)/zicntr $(ISA_YAML_ROOT)/Zicntr_instr

# Helper macro returning YAML files for a decoded ISA extension.
yaml_files_for_ext = $(foreach dir,$(ISA_EXT_$(1)_YAML_DIRS),$(call find_yaml,$(dir)))

# Raw YAML file list selected from the decoded ISA extension list.
ISA_YAML_FILES_RAW = $(foreach ext,$(ISA_EXTENSIONS),$(call yaml_files_for_ext,$(ext)))

# YAML files describing RV64-only instructions, filtered out for RV32 builds.
RV64_ONLY_YAML_PATTERNS := \
	%/addiw.yaml \
	%/slliw.yaml \
	%/sraiw.yaml \
	%/srliw.yaml \
	%/lwu.yaml \
	%/ld.yaml \
	%/sd.yaml \
	%/addw.yaml \
	%/subw.yaml \
	%/sllw.yaml \
	%/sraw.yaml \
	%/srlw.yaml \
	%/mulw.yaml \
	%/divw.yaml \
	%/divuw.yaml \
	%/remw.yaml \
	%/remuw.yaml

# Final YAML file list selected for the configured ISA.
ifeq ($(XLEN),XLEN32)
ISA_YAML_FILES = $(sort $(filter-out $(RV64_ONLY_YAML_PATTERNS),$(strip $(ISA_YAML_FILES_RAW))))
else
ISA_YAML_FILES = $(sort $(strip $(ISA_YAML_FILES_RAW)))
endif

####################################                         ####################################


# Display help for ISA-related targets and variables
.PHONY: isa_help
isa_help:
	@echo
	@echo "riscv-core-harness — ISA Makefile helper"
	@echo "Usage: make <target> [variables]"
	@echo
	@printf "Targets:\n"
	@printf "  %-35s %s\n" "print_isa_config" "Print the decoded ISA configuration and selected YAML files."
	@echo
	@printf "Key variables:\n"
	@printf "  %-35s %s\n" "ISA"          "GCC-compatible RISC-V ISA string. Default: rv32i_zicntr."
	@echo
	@echo "Examples:"
	@echo "  make print_isa_config"
	@echo "  make print_isa_config ISA=rv32imac_zicntr"
	@echo "  make print_isa_config ISA=rv32gc ABI=ilp32d"
	@echo "  make print_isa_config ISA=rv64gc ABI=lp64d"
	@echo

# Print the decoded ISA configuration and selected YAML files.
.PHONY: print_isa_config
print_isa_config:
	@echo "ISA                   = $(ISA)"
	@echo "ISA_PARTS             = $(ISA_PARTS)"
	@echo "RISCV_BASE_ARCH       = $(RISCV_BASE_ARCH)"
	@echo "RISCV_BASE_EXTS_RAW   = $(RISCV_BASE_EXTS_RAW)"
	@echo "RISCV_BASE_EXTS_SPLIT = $(RISCV_BASE_EXTS_SPLIT)"
	@echo "RISCV_EXTRA_EXTS      = $(RISCV_EXTRA_EXTS)"
	@echo "RISCV_G_EXTENSIONS    = $(RISCV_G_EXTENSIONS)"
	@echo "ISA_EXTENSIONS        = $(ISA_EXTENSIONS)"
	@echo "XLEN                  = $(XLEN)"
	@echo "CPU_XLEN              = $(CPU_XLEN)"
	@echo "ABI                   = $(ABI)"
	@echo "ISA_YAML_DIR          = $(ISA_YAML_DIR)"
	@echo ""
	@echo "ISA_YAML_FILES:"
	@printf '%s\n' $(ISA_YAML_FILES)
