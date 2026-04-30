# SPDX-License-Identifier: MIT
# /*!
# ********************************************************************************
# \file       common.mk
# \brief      Common variables and helper targets for riscv-core-harness
# \author     Kawanami
# \version    1.0
# \date       28/04/2026
#
# \details
#   This Makefile fragment contains the variables, file lists, and helper targets
#   shared across the different riscv-core-harness flows.
#
#   It provides:
#     - architecture-related parameters
#     - common project directories
#     - shared RTL, firmware, and platform file lists
#     - firmware build helper targets
#     - generic utility targets such as firmware build, UART transfer,
#       minicom, documentation, formatting, and linting
#
#   This file is intended to be included by the riscv-core-harness Makefile and by
#   platform-specific Makefile fragments.
#
# \remarks
#   - Requires Python 3 and a RISC-V cross-compilation toolchain.
#   - Some helper targets additionally require Doxygen, minicom, and the
#     repository utility scripts.
#   - Relies on variables defined by the including Makefile, such as `ROOT_DIR`.
#   - See `make help` for a summary of available targets and variables.
#
# \section common_mk_version_history Version history
# | Version | Date       | Author   | Description                                |
# |:-------:|:----------:|:---------|:-------------------------------------------|
# | 1.0     | 28/04/2026 | Kawanami | Initial version.                           |
# ********************************************************************************
# */

#################################### Architecture parameters ###################################
# Select whether the simulation/model uses a perfect memory
PERFECT_MEMORY					        ?= YES
ifeq ($(PERFECT_MEMORY),YES)
NOT_PERFECT_MEMORY				      = "1'b0"
else
NOT_PERFECT_MEMORY				      = "1'b1"
endif
####################################						###################################

#################################### Directories ####################################
# Hardware directory
HW_DIR 							            = $(RISCV_CORE_HARNESS_DIR)hardware/

# Design under test environment directory
DUT_DIR		        	            ?= $(ROOT_DIR)core/

# Design under test harness directory
HARNESS_FILES_DIR				        = $(HW_DIR)harness/

# Software directory (contains platform & firmware directories)
SOFTWARE_DIR				            = $(RISCV_CORE_HARNESS_DIR)software/

# Firmware directory
FIRMWARE_DIR 				            = $(SOFTWARE_DIR)firmware/

# ISA YAML directory
ISA_YAML_DIR   			            = $(FIRMWARE_DIR)isa/

# LOADER firmware directory
LOADER_DIR   				            = $(FIRMWARE_DIR)loader/

# ECHO firmware directory
ECHO_DIR   					            = $(FIRMWARE_DIR)echo/

# CYCLEMARK firmware directory
CYCLEMARK_DIR   		            = $(FIRMWARE_DIR)cyclemark/

# Platform directory shared between simulation and hardware board flows.
PLATFORM_DIR 				            = $(SOFTWARE_DIR)/platform/

# Firmware working directory
FIRMWARE_WORK_DIR		            = $(WORK_DIR)firmware/

# Firmware build directory
FIRMWARE_BUILD_DIR 	            = $(FIRMWARE_WORK_DIR)build/

# Firmware build log directory
FIRMWARE_LOG_DIR 		            = $(FIRMWARE_WORK_DIR)log/
#################################### 			 ####################################

#################################### Hardware Files ####################################
# Common RTL files shared across the different build flows
COMMON_RTL_FILES					      = $(HW_DIR)common/target_pkg.sv \
                                  $(HW_DIR)common/axi_if.sv

# SystemVerilog and Verilog source files of the RISC-V core.
DUT_SRC_FILES                   ?= $(shell find "$(DUT_DIR)" -type f \( -name "*.sv" -o -name "*.v" \) | sort)

# SystemVerilog header/include files of the RISC-V core.
DUT_INC_FILES                   ?= $(shell find "$(DUT_DIR)" -type f -name "*.svh" | sort)

# RTL files passed as compilation units.
DUT_FILES                       = $(DUT_SRC_FILES)

# Directories containing SystemVerilog header/include files.
DUT_INC_DIRS                    = $(sort $(dir $(DUT_INC_FILES)))

# Verilator/SystemVerilog include path flags generated from DUT include directories.
DUT_INC_FLAGS                   = $(addprefix -I,$(DUT_INC_DIRS))

# Design under test environment files
HARNESS_FILES 						      = $(HARNESS_FILES_DIR)axi2ram.sv \
                                  $(HARNESS_FILES_DIR)async_fifo.sv \
                                  $(HARNESS_FILES_DIR)dpram.sv \
						    	                $(HARNESS_FILES_DIR)sys_reset.sv \
						    	                $(HARNESS_FILES_DIR)xbar.sv \
						    	                $(HARNESS_FILES_DIR)riscv_core_harness.sv

# Top-level module used for simulation
TOP								              = riscv_core_harness
#################################### 	   ####################################

#################################### Software Files ####################################
# Common firmware source files
COMMON_FILES			              = $(FIRMWARE_DIR)common/eprintf.c \
						                      $(FIRMWARE_DIR)common/memory.c \
						                      $(FIRMWARE_DIR)common/start.S

# Loader firmware source files
LOADER_FILES 					          = $(LOADER_DIR)main.c

# Echo firmware source files
ECHO_FILES 						          = $(ECHO_DIR)main.c

# Cyclemark firmware source files
CYCLEMARK_FILES 				        = $(CYCLEMARK_DIR)core_list_join.c \
								                  $(CYCLEMARK_DIR)core_main.c \
								                  $(CYCLEMARK_DIR)core_matrix.c \
								                  $(CYCLEMARK_DIR)core_portme.c \
								                  $(CYCLEMARK_DIR)core_state.c \
								                  $(CYCLEMARK_DIR)core_util.c

# Firmware linker script
LINKER                          = $(FIRMWARE_DIR)linker/linker.ld

# Common platform-side C++ source files
PLATFORM_FILES					        = $(PLATFORM_DIR)args_parser.cpp \
								                  $(PLATFORM_DIR)axi4.cpp \
								                  $(PLATFORM_DIR)log.cpp \
								                  $(PLATFORM_DIR)memory.cpp \
								                  $(PLATFORM_DIR)load.cpp \
								                  $(PLATFORM_DIR)platform.cpp
#################################### 	   ####################################

#################################### Firmware Toolchain ###################################
# Path to the RISC-V GCC binary directory
EGCC_DIR		  	                ?= /opt/riscv-gnu-toolchain/multilib/bin/

# RISC-V bare-metal toolchain prefix.
RISCV_TOOLCHAIN_PREFIX          ?= riscv64-unknown-elf

# RISC-V C compiler
ECC 					                  ?= $(EGCC_DIR)$(RISCV_TOOLCHAIN_PREFIX)-gcc

# RISC-V linker
ELD						                  ?= $(EGCC_DIR)$(RISCV_TOOLCHAIN_PREFIX)-ld

# RISC-V objdump
EOBJDUMP				                ?= $(EGCC_DIR)$(RISCV_TOOLCHAIN_PREFIX)-objdump

# RISC-V objcopy
EOBJCOPY				                ?= $(EGCC_DIR)$(RISCV_TOOLCHAIN_PREFIX)-objcopy

# Static libgcc archive
ELGCC					                  ?= $(shell $(ECC) -march=$(ISA) -mabi=$(ABI) -print-libgcc-file-name)

# Directory containing firmware helper scripts
TOOLS_DIR  			                ?= $(RISCV_CORE_HARNESS_DIR)scripts/

# ELF-to-HEX conversion script
MAKE_HEX				                ?= $(TOOLS_DIR)makehex.py

# Select whether Spike-specific firmware options are enabled
WITH_SPIKE			                ?= NO_SPIKE

# Number of iterations used by generated tests and benchmark firmware
ITERATIONS          			      ?= 1

# Firmware compiler flags
ECFLAGS  				                ?= -I$(FIRMWARE_DIR)common/ -I$(SOFTWARE_DIR) \
						                       -DITERATIONS=$(ITERATIONS) -D$(XLEN) -D$(WITH_SPIKE) \
                                   -march=$(ISA) -mabi=$(ABI) -Wall -nostdlib \
						                       -ffreestanding -O3 -ffunction-sections -fdata-sections

# Firmware linker flag
ELDFLAGS 				                ?= -T $(LINKER) -march=$(ISA) -mabi=$(ABI) -nostdlib -static -Wl,--gc-sections
#################################### 	 				####################################

# Display help for common-related targets
.PHONY: common_help
common_help:
	@echo
	@echo "riscv-core-harness — common Makefile helper"
	@echo "Usage: make <target>"
	@echo
	@printf "Targets:\n"
	@printf "  %-35s %s\n" "clean_firmware"       "Clean the firmware working directory."
	@printf "  %-35s %s\n" "documentation" 			  "Build the doxygen documentation."
	@printf "  %-35s %s\n" "clean_documentation"  "Clean the doxygen documentation."
	@printf "  %-35s %s\n" "format"    		        "Format HDL and software source files."
	@printf "  %-35s %s\n" "lint"    		          "Lint HDL files."
	@echo
	@printf "Key variables:\n"
	@echo
	@echo "Examples:"
	@echo "  make documentation"
	@echo "  make clean_firmware"
	@echo
	@echo

# Create the firmware working directories
.PHONY: firmware_work
firmware_work:
	@echo "➡️  Creating firmware working environment..."
	@mkdir -p $(FIRMWARE_BUILD_DIR)
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@echo "✅ Done."
	@echo

# Build the selected firmware and generate ELF/BIN/DUMP/HEX outputs
.PHONY: firmware
firmware: firmware_work

	@echo "➡️  Building $(FIRMWARE) firmware..."

	@rm -f "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).elf"
	@rm -f "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).bin"
	@rm -f "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).dump"
	@rm -f "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).hex"

	@firmware_objects=""; \
	for source in $(FIRMWARE_FILES); do \
		obj="$(FIRMWARE_BUILD_DIR)$$(basename "$$source").o"; \
		echo "$(ECC) $(ECFLAGS) -c $$source -o $$obj" >> "$(FIRMWARE_LOG_DIR)log.txt"; \
		$(ECC) $(ECFLAGS) -c "$$source" -o "$$obj"; \
		firmware_objects="$$firmware_objects $$obj"; \
	done; \
	common_objects=""; \
	for source in $(COMMON_FILES); do \
		if [ -n "$$source" ]; then \
			obj="$(FIRMWARE_BUILD_DIR)$$(basename "$$source").o"; \
			echo "$(ECC) $(ECFLAGS) -c $$source -o $$obj" >> "$(FIRMWARE_LOG_DIR)log.txt"; \
			$(ECC) $(ECFLAGS) -c "$$source" -o "$$obj"; \
			common_objects="$$common_objects $$obj"; \
		fi; \
	done; \
	echo "$(ECC) $(ELDFLAGS) $$firmware_objects $$common_objects $(ELGCC) -o $(FIRMWARE_BUILD_DIR)$(FIRMWARE).elf" >> "$(FIRMWARE_LOG_DIR)log.txt"; \
	$(ECC) $(ELDFLAGS) $$firmware_objects $$common_objects $(ELGCC) -o "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).elf"; \
	rm -f $$firmware_objects $$common_objects

	@echo "$(EOBJCOPY) -O binary $(FIRMWARE_BUILD_DIR)$(FIRMWARE).elf $(FIRMWARE_BUILD_DIR)$(FIRMWARE).bin" >> "$(FIRMWARE_LOG_DIR)log.txt"
	@$(EOBJCOPY) -O binary "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).elf" "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).bin"

	@echo "$(EOBJDUMP) -D $(FIRMWARE_BUILD_DIR)$(FIRMWARE).elf > $(FIRMWARE_BUILD_DIR)$(FIRMWARE).dump" >> "$(FIRMWARE_LOG_DIR)log.txt"
	@$(EOBJDUMP) -D "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).elf" > "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).dump"

	@echo "python3 $(MAKE_HEX) $(FIRMWARE_BUILD_DIR)$(FIRMWARE).elf > $(FIRMWARE_BUILD_DIR)$(FIRMWARE).hex" >> "$(FIRMWARE_LOG_DIR)log.txt"
	@python3 "$(MAKE_HEX)" "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).elf" > "$(FIRMWARE_BUILD_DIR)$(FIRMWARE).hex"

	@echo "" >> "$(FIRMWARE_LOG_DIR)log.txt"
	@echo "✅ Done."
	@echo

# Build the loader firmware
.PHONY: loader_firmware
loader_firmware: FIRMWARE_FILES=$(LOADER_FILES)
loader_firmware: FIRMWARE=loader
loader_firmware: firmware

# Build the echo firmware
.PHONY: echo_firmware
echo_firmware: FIRMWARE_FILES=$(ECHO_FILES)
echo_firmware: FIRMWARE=echo
echo_firmware: firmware

# Build the cyclemark firmware
.PHONY: cyclemark_firmware
cyclemark_firmware: FIRMWARE_FILES=$(CYCLEMARK_FILES)
cyclemark_firmware: FIRMWARE=cyclemark
cyclemark_firmware: firmware

# Clean the firmware directory
.PHONY: clean_firmware
clean_firmware:
	@echo "➡️  Cleaning firmware directory..."
	@rm -rf $(FIRMWARE_WORK_DIR)
	@echo "✅ Done."

# Send a file to the target through the serial link
.PHONY: uart_ft
uart_ft:
	@sudo python3 $(RISCV_CORE_HARNESS_DIR)scripts/uart_ft.py \
		--dev "$(TTY)" --baud $(TTY_BAUDRATE) \
		--login --user root \
		--dest-dir "$(UART_DEST_DIR)" \
		--file "$(UART_FILE)"

# Generate the code documentation
.PHONY: documentation
documentation:
	@doxygen $(RISCV_CORE_HARNESS_DIR)scripts/Doxyfile

# Clean the code documentation
.PHONY: clean_documentation
clean_documentation:
	@rm -rf $(RISCV_CORE_HARNESS_DIR)docs/doxygen/
	@rm -rf $(RISCV_CORE_HARNESS_DIR)docs/doxygen.warnings

# Format HDL and C/C++ source files
.PHONY: format
format:
	@bash -c "$(RISCV_CORE_HARNESS_DIR)sv-tools/format_hdl.sh $(RISCV_CORE_HARNESS_DIR)"
	@bash -c "$(RISCV_CORE_HARNESS_DIR)scripts/format_cxx.sh $(RISCV_CORE_HARNESS_DIR)"

# Lint HDL source files
.PHONY: lint
lint:
	@bash -c "$(RISCV_CORE_HARNESS_DIR)sv-tools/lint.sh $(RISCV_CORE_HARNESS_DIR)"
