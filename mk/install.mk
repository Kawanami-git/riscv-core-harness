#!/bin/sh
# SPDX-License-Identifier: MIT
# /*!
# ********************************************************************************
# \file       install.mk
# \brief      Makefile targets to install environments
# \author     Kawanami
# \version    1.0
# \date       30/04/2026
#
# \details
#   Run the installers using 'make install_sim_env',
#	'make install_microchip_env' or 'make install_xilinx_env'.
#
# \remarks
#
# \section makefile_version_history Version history
# | Version | Date       | Author     | Description      |
# |:-------:|:----------:|:-----------|:-----------------|
# | 1.0     | 30/04/2026 | Kawanami   | Initial version. |
# ********************************************************************************
# */

#################################### Install Directories ####################################

# Directory containing environment installation scripts.
INSTALL_DIR := $(RISCV_CORE_HARNESS_DIR)install/

####################################                     ####################################

.default: install_help

.PHONY: install_help
install_help:
	@echo
	@echo "riscv-core-harness — install Makefile helper"
	@echo "Usage: make <target>"
	@echo
	@printf "Targets:\n"
	@printf "  %-35s %s\n" "install_sim_env"       "Install simulation tools."
	@printf "  %-35s %s\n" "install_microchip_env" "Install Microchip tool support."
	@printf "  %-35s %s\n" "install_xilinx_env"    "Install AMD/Xilinx tool support."
	@echo

.PHONY: install_sim_env
install_sim_env:
	@chmod +x "$(INSTALL_DIR)sim/install_sim_env.sh"
	@cd "$(RISCV_CORE_HARNESS_DIR)" && ./install/sim/install_sim_env.sh

.PHONY: install_microchip_env
install_microchip_env:
	@chmod +x "$(INSTALL_DIR)mpfs-discovery-kit/install_microchip_env.sh"
	@cd "$(RISCV_CORE_HARNESS_DIR)" && ./install/mpfs-discovery-kit/install_microchip_env.sh

.PHONY: install_xilinx_env
install_xilinx_env:
	@chmod +x "$(INSTALL_DIR)cora-z7-07s/install_xilinx_env.sh"
	@cd "$(RISCV_CORE_HARNESS_DIR)" && ./install/cora-z7-07s/install_xilinx_env.sh
