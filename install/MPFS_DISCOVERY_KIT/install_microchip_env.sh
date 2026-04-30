#!/bin/sh
# SPDX-License-Identifier: MIT
# /*!
# ********************************************************************************
# \file       install_microchip_env.sh
# \brief      Automated installer for Microchip Libero/SoftConsole + Yocto deps.
# \author     Kawanami
# \version    1.4
# \date       13/04/2026
#
# \details
#   Installs system dependencies and runs the unattended installers for:
#     - Libero SoC 2025.1 (and selected components)
#     - SoftConsole v2022.2 (RISC-V toolchain)
#   Also prepares Yocto build prerequisites and auxiliary tooling (UART/XMODEM),
#   configures certificates symlink expected by Libero, and installs FlashPro6
#   drivers. Includes a compatibility branch for Ubuntu 20.04 vs newer releases.
#
# \remarks
#   - Requires sudo privileges (apt install, driver install).
#   - Adjust paths/filenames below to your local installers and versions.
#   - The script intentionally keeps /bin/sh for portability (no pipefail).
#
# \section install_microchip_tools_sh_version_history Version history
# | Version | Date       | Author     | Description      |
# |:-------:|:----------:|:-----------|:-----------------|
# | 1.0     | 11/11/2025 | Kawanami   | Initial version. |
# | 1.1     | 16/11/2025 | Kawanami   | Add missing librairies to drive usb (libusb).<br> Add missing chmod to be able to execute Libero_SoC_2025.1_online_lin.bin. |
# | 1.2     | 24/12/2025 | Kawanami   | Update libero install with 2025.2. |
# | 1.3     | 13/04/2026 | Kawanami   | Add lz4 package install. |
# | 1.4     | 13/04/2026 | Kawanami | Add minicom package. |
# ********************************************************************************
# */

# --- Detect OS version (Ubuntu/Debian derive VERSION_ID here) -------------------
. /etc/os-release
version="${VERSION_ID:-unknown}"

# --- Base install prefix for Microchip tools -----------------------------------
MICROCHIP_DIR=/opt/microchip

# --- Libero installer & layout -------------------------------------------------
LIBERO_INSTALL_SCRIPT=Libero_SoC_2025.2_online_lin.sh
LIBERO_INSTALL_DIR=$MICROCHIP_DIR/Libero_SoC_2025.2
LIBERO_INSTALL_COMMON_DIR=$HOME/.local/share/microchip/common
# Pick only the components you need; these match Libero’s internal IDs
LIBERO_COMPONENTS="Libero_SoC Program_Debug MegaVault PFSoC_MSS_Configurator"

# --- SoftConsole installer & layout --------------------------------------------
SOFTCONSOLE_INSTALL_SCRIPT=./Microchip-SoftConsole-v2022.2-RISC-V-747-linux-x64-installer.run
SOFTCONSOLE_INSTALL_DIR=/opt/microchip/SoftConsole-v2022.2-RISC-V-747

# --- Refresh package lists ------------------------------------------------------
sudo apt update

# --- Libero package/runtime prerequisites (general) -----------------------------
sudo apt install -y \
      desktop-file-utils \
      udev \
      ca-certificates \
      zip \
      file \
      curl \
      xdg-utils \
      build-essential \
      lsb-release \
      libusb-1.0-0 \
      libusb-1.0-0-dev \
      libusb-0.1-4 \
      usbutils

# Locales (Libero GUIs sometimes expect en_US.UTF-8)
sudo apt install -y locales && \
      locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8

# --- Libero GUI/OpenGL/X11 dependencies (64-bit) --------------------------------
sudo apt install -y \
      libegl1 \
      libgl1 \
      libopengl0 \
      libgles2 \
      libglx-mesa0 \
      libgbm1 \
      libdrm2 \
      libx11-6 \
      libxext6 \
      libxrender1 \
      libxi6 \
      libxtst6 \
      libsm6 \
      libice6 \
      libexpat1 \
      libfontconfig1 \
      libfreetype6 \
      libglib2.0-0 \
      libuuid1 \
      libxcb1 \
      libxfixes3 \
      libkeyutils1 \
      zlib1g \
      libstdc++6 \
      libxslt1.1 \
      libgraphite2-3

# --- Linux prerequisites ---------------------------------------------
sudo apt install -y \
    gawk \
    wget \
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

# --- Create target directory and set ownership ----------------------------------
sudo mkdir -p "$MICROCHIP_DIR"
sudo chown -R "$USER":"$USER" "$MICROCHIP_DIR"

# --- Retreive installers -------------------------------------------------------
wget https://github.com/Kawanami-git/MPFS_DISCOVERY_KIT/releases/download/2025-11-04/Libero_SoC_2025.2_online_lin.sh
wget https://github.com/Kawanami-git/MPFS_DISCOVERY_KIT/releases/download/2025-11-04/Libero_SoC_2025.2_online_lin.bin

# --- Run Libero unattended installer -------------------------------------------
chmod +x "$LIBERO_INSTALL_SCRIPT"
chmod +x Libero_SoC_2025.2_online_lin.bin
./"$LIBERO_INSTALL_SCRIPT" \
      --verbose \
      --accept-licenses \
      --accept-messages \
      --confirm-command install \
      --root "$LIBERO_INSTALL_DIR" \
      $LIBERO_COMPONENTS \
      TargetDir="/$LIBERO_INSTALL_DIR" \
      CommonDir="$LIBERO_INSTALL_COMMON_DIR"

# --- Post-install runtime deps: Ubuntu 20.04 has vendor script ------------------
if [ "$version" = 20.04* ]; then
      if [ -e "$LIBERO_INSTALL_DIR/req_to_install.sh" ]; then
            # Installs vendor-curated runtime packages for 20.04
            sudo sh "$LIBERO_INSTALL_DIR/req_to_install.sh"
      fi
# --- On newer releases, install 32-bit compatibility libs explicitly -----------
else
      # Enable i386 architecture and install 32-bit libs needed by legacy tools
      sudo dpkg --add-architecture i386
      sudo apt update && sudo apt install -y \
            libc6:i386 \
            libstdc++6:i386 \
            libdrm2:i386 \
            libexpat1:i386 \
            libfontconfig1:i386 \
            libfreetype6:i386 \
            libglapi-mesa:i386 \
            libglib2.0-0t64:i386 \
            libgl1:i386 \
            libice6:i386 \
            libsm6:i386 \
            libuuid1:i386 \
            libx11-6:i386 \
            libx11-xcb1:i386 \
            libxau6:i386 \
            libxcb-dri2-0:i386 \
            libxcb-glx0:i386 \
            libxcb1:i386 \
            libxdamage1:i386 \
            libxext6:i386 \
            libxfixes3:i386 \
            libxrender1:i386 \
            libxxf86vm1:i386 \
            zlib1g:i386 \
            libflac12t64 \
            libpcre3 \
            libxcb-xinerama0 \
            libxcb-xinput0 \
            xfonts-intl-asian \
            xfonts-intl-chinese \
            xfonts-intl-chinese-big \
            xfonts-intl-japanese \
            xfonts-intl-japanese-big \
            ksh \
            libxft2:i386 \
            libgtk2.0-0t64:i386 \
            libcanberra-gtk-module:i386 \
            libfreetype-dev \
            libharfbuzz-dev

      # Remove bundled libstdc++/libgcc if shipped by vendor to avoid GLIBC mismatches
      find "$LIBERO_INSTALL_DIR" -name "libstdc++.so.6" -type f -delete
      find "$LIBERO_INSTALL_DIR" -name "libgcc_s.so.1" -type f -delete
fi


# --- UART/XMODEM helpers for board transfer over serial -------------------------
sudo apt install -y \
      lrzsz \
      python3-serial \
      python3-xmodem

# --- FlashPro6 driver/environment setup (required to program the FPGA) ----------
sudo "$LIBERO_INSTALL_DIR/Libero_SoC/Designer/bin/fp6_env_install"

# --- CA bundle path expected by Libero downloaders (symlink if missing) --------
sudo mkdir -p /etc/pki/tls/certs
if [ ! -e "/etc/pki/tls/certs/ca-bundle.crt" ]; then
      sudo ln -s /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt
fi

# --- FlexLM temp directory used by license manager -----------------------------
sudo mkdir -p /usr/tmp/.flexlm

# --- Retreive SoftConsole installer --------------------------------------------
wget https://github.com/Kawanami-git/MPFS_DISCOVERY_KIT/releases/download/2025-11-04/Microchip-SoftConsole-v2022.2-RISC-V-747-linux-x64-installer.run

# --- Install SoftConsole unattended --------------------------------------------
chmod +x "$SOFTCONSOLE_INSTALL_SCRIPT"
sudo "$SOFTCONSOLE_INSTALL_SCRIPT" \
  --mode unattended \
  --unattendedmodeui none \
  --prefix "$SOFTCONSOLE_INSTALL_DIR"
