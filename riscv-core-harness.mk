# SPDX-License-Identifier: MIT
# /*!
# ********************************************************************************
# \file       Makefile
# \brief      Top-level build orchestration for riscv-core-harness.
# \author     Kawanami
# \version    1.0
# \date       28/04/2026
#
# \details
#   This Makefile is the main entry point of the riscv-core-harness project.
#   It keeps the top-level flow intentionally small and delegates most logic to
#   dedicated Makefile fragments.
#
#   It provides:
#     - project Makefile path definitions,
#     - inclusion of ISA configuration variables,
#     - inclusion of common build and utility targets,
#     - inclusion of simulation targets,
#     - optional inclusion of supported board targets,
#     - global help and clean entry points.
#
# \remarks
#   - Requires the Makefile fragments located in the `mk` directory.
#   - Board-specific Makefiles are included conditionally when available.
#   - See `make riscv_core_harness_help` for the available target groups.
#
# \section makefile_toplevel_version_history Version history
# | Version | Date       | Author   | Description      |
# |:-------:|:----------:|:---------|:-----------------|
# | 1.0     | 28/04/2026 | Kawanami | Initial version. |
# ********************************************************************************
# */


#################################### Directories ####################################
# Project Makefiles directory
MK_DIR      := $(RISCV_CORE_HARNESS_DIR)mk/
####################################             ####################################

#################################### Included Makefiles ####################################
# Install Makefile
INSTALL_MK  := $(MK_DIR)install.mk

# ISA Makefile
ISA_MK      := $(MK_DIR)isa.mk

# Common Makefile
COMMON_MK   := $(MK_DIR)common.mk

# Simulation Makefile
SIM_MK      := $(MK_DIR)sim.mk

# MPFS Discovery Kit Makefile
MPFS_MK     := $(RISCV_CORE_HARNESS_DIR)mpfs-discovery-kit/mpfs_disco_kit.mk

# Cora z7-07s Makefile
CORA_MK     := $(RISCV_CORE_HARNESS_DIR)cora-z7-07s/cora_z7_07s.mk

# Include ISA variables
include $(INSTALL_MK)

# Include ISA variables
include $(ISA_MK)

# Include common targets
include $(COMMON_MK)

# Include simulation targets
include $(SIM_MK)

# Include MPFS Discovery Kit targets
-include $(MPFS_MK)

# Include Cora Z7-07S targets
-include $(CORA_MK)

# Makefiles helper
HELPERS := install_help isa_help common_help sim_help

# Add MPFS Discovery Kit Makefile helper if the Makefile exist
ifneq ($(wildcard $(MPFS_MK)),)
HELPERS += mpfs_disco_kit_help
endif

# Add Cora z7-07s Makefile helper if the Makefile exist
ifneq ($(wildcard $(CORA_MK)),)
HELPERS += cora_z7_07s_help
endif
####################################                    ####################################

# Default target
.DEFAULT_GOAL := help

# Global help
.PHONY: riscv_core_harness_help
riscv_core_harness_help: $(HELPERS)

# Global clean
.PHONY: clean_all
clean_all:
	@rm -rf $(WORK_DIR)
