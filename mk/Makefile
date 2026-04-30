# SPDX-License-Identifier: MIT
# /*!
# ********************************************************************************
# \file       Makefile
# \brief      Generic top-level Makefile for using riscv-core-harness.
# \author     Kawanami
# \version    1.0
# \date       30/04/2026
#
# \details
#   This Makefile is a minimal integration template for projects that want to use
#   riscv-core-harness to validate a RISC-V core.
#
#   The user only needs to provide the path to the design under test through
#   `DUT_DIR`. The harness then provides the simulation, firmware, documentation,
#   formatting, linting, and supported board flows.
#
#   It provides:
#     - project root and work directory definitions,
#     - riscv-core-harness submodule path definition,
#     - design under test directory selection,
#     - default place-and-route exploration parameters,
#     - default RISC-V ISA selection,
#     - inclusion of the riscv-core-harness top-level Makefile,
#     - project-level help entry point.
#
# \remarks
#   - Requires the `riscv-core-harness` submodule to be present and initialized.
#   - Board support and simulation flows are provided by riscv-core-harness.
#   - Override `DUT_DIR` from the command line or directly in this file to point
#     to your RISC-V core RTL directory.
#   - See `make help` for the available target groups.
#
# \section Makefile_mk_version_history Version history
# | Version | Date       | Author   | Description      |
# |:-------:|:----------:|:---------|:-----------------|
# | 1.0     | 30/04/2026 | Kawanami | Initial version. |
# ********************************************************************************
# */


#################################### Directories ####################################

# Absolute path to the project root directory.
ROOT_DIR                := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))/

# Path to the riscv-core-harness submodule.
RISCV_CORE_HARNESS_DIR  := $(ROOT_DIR)riscv-core-harness/

# Path to the RISC-V core RTL directory to validate.
DUT_DIR                 ?= $(ROOT_DIR)risc-v/

# Path to the working directory used for generated and build files.
WORK_DIR                ?= $(ROOT_DIR)work/

####################################             ####################################


#################################### Microchip Build Configuration ####################################

# First Libero place-and-route seed used for timing exploration.
PNR_SEED                ?= 16

# Number of Libero place-and-route passes to run.
PNR_PASSES              ?= 1

####################################                               ####################################


#################################### RISC-V Configuration ####################################

# GCC-compatible RISC-V ISA string used by firmware and simulation flows.
ISA                     ?= rv32i_zicntr

####################################                      ####################################


#################################### Included Makefiles ####################################

# Top-level Makefile provided by the riscv-core-harness submodule.
RISCV_CORE_HARNESS_MK   := $(RISCV_CORE_HARNESS_DIR)riscv-core-harness.mk

# Stop early if the riscv-core-harness submodule is missing.
ifeq ($(wildcard $(RISCV_CORE_HARNESS_MK)),)
$(error Missing riscv-core-harness submodule.)
endif

# Include riscv-core-harness targets and variables.
include $(RISCV_CORE_HARNESS_MK)

####################################                    ####################################


#################################### Default Targets ####################################

# Default target displayed when running plain `make`.
.DEFAULT_GOAL := help

# Project-level help entry point.
.PHONY: help
help: riscv_core_harness_help

####################################                 ####################################
