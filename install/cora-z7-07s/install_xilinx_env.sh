#!/bin/sh
# SPDX-License-Identifier: MIT
# /*!
# ********************************************************************************
# \file       install_xilinx_env.sh
# \brief      Automated AMD Vivado/Vitis and Linux dependency installer.
# \author     Kawanami
# \version    1.3
# \date       14/04/2026
#
# \details
#   Installs the Linux host dependencies required by the SCHOLAR RISC-V board
#   support environment, then downloads and runs the AMD 2025.2 batch installer
#   for Vivado and Vitis.
#
#   The script:
#     1) installs Linux host dependencies
#     2) prepares the installation directory under /opt/Xilinx
#     3) downloads the AMD installer wrapper
#     4) extracts the installer in batch mode
#     5) applies the provided installation configuration
#     6) installs the additional OS libraries required by the AMD tools
#
# \remarks
#   - Requires sudo privileges for package installation and writes under /opt/Xilinx.
#   - Requires network access for both the GitHub download and the AMD web installer.
#   - Authentication token generation is interactive and requires a valid AMD account.
#   - Adjust filenames, versions, and configuration files below as needed.
#   - The script intentionally keeps /bin/sh for portability.
#
# \section install_xilinx_env_sh_version_history Version history
# | Version | Date       | Author   | Description      |
# |:-------:|:----------:|:---------|:-----------------|
# | 1.0     | 12/04/2026 | Kawanami | Initial version. |
# | 1.1     | 13/04/2026 | Kawanami | Add minicom package. |
# | 1.2     | 13/04/2026 | Kawanami | Update AMD/Xilinx installer link. |
# | 1.3     | 14/04/2026 | Kawanami | Fix AMD/Xilinx installer link and missing dependencies. |
# ********************************************************************************
# */

set -e

# Base installation directory for AMD tools.
XILINX_DIR=/opt/Xilinx

# Installer filename retrieved from the project release.
VIVADO_INSTALL_SCRIPT=FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1114_2157_Lin64.bin

# Final AMD tools installation directory.
VIVADO_INSTALL_DIR=$XILINX_DIR

# Temporary extraction directory for the AMD installer.
VIVADO_EXTRACT_DIR=/tmp/Xilinx

# Batch installation configuration file.
VIVADO_CONFIG_FILE=install_config_cora.txt

# Post-install dependency script provided by AMD.
AMD_INSTALL_LIBS_SCRIPT=$VIVADO_INSTALL_DIR/2025.2/Vitis/scripts/installLibs.sh

# Linux host packages required for Yocto builds and board utilities.
sudo apt update
sudo apt install -y \
    gawk \
    wget \
    git \
    git-core \
    git-lfs \
    diffstat \
    unzip \
    texinfo \
    gcc-multilib \
    build-essential \
    chrpath \
    socat \
    cpio \
    python3 \
    python3-pip \
    python3-pexpect \
    xz-utils \
    lz4 \
    debianutils \
    iputils-ping \
    python3-git \
    python3-jinja2 \
    libegl1 \
    libsdl1.2-dev \
    pylint \
    xterm \
    repo \
    coreutils \
    ssh \
    minicom

# Create the installation directory and grant ownership to the current user.
sudo mkdir -p "$VIVADO_INSTALL_DIR"
sudo chown -R "$USER:$USER" "$VIVADO_INSTALL_DIR"

# Download the AMD installer wrapper from the project release page.
wget "https://github.com/Kawanami-git/CORA_Z7_07S/releases/download/Install-13-04-2026/$VIVADO_INSTALL_SCRIPT"

# Extract the AMD installer without executing the GUI flow.
chmod +x "$VIVADO_INSTALL_SCRIPT"
./"$VIVADO_INSTALL_SCRIPT" --keep --noexec --target "$VIVADO_EXTRACT_DIR"

# Copy the batch configuration file into the extracted installer directory.
cp "$VIVADO_CONFIG_FILE" "$VIVADO_EXTRACT_DIR"

# Generate the AMD authentication token required by the web installer.
cd "$VIVADO_EXTRACT_DIR" && ./xsetup -b AuthTokenGen

# Run the batch installation.
cd "$VIVADO_EXTRACT_DIR" && ./xsetup \
  --agree XilinxEULA,3rdPartyEULA \
  --batch Install \
  --config "$VIVADO_CONFIG_FILE"

# Install additional OS libraries required by the installed AMD tools.
chmod +x "$AMD_INSTALL_LIBS_SCRIPT"
sudo "$AMD_INSTALL_LIBS_SCRIPT"

git clone https://github.com/Digilent/vivado-boards.git /opt/Xilinx/board_files/digilent