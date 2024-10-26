#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo -e "\e[31m[ERROR]\e[0m This script must be run as root."
  exit 1
fi

# Set up logging
LOG_FILE="arch_install_$(date + %Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Detect boot mode
if [[ -d /sys/firmware/efi/efivars ]]; then
  BOOT_MODE="UEFI"
  echo -e "\e[32m[INFO]\e[0m Boot mode detected: UEFI"
else
  BOOT_MODE="BIOS"
  echo -e "\e[32m[INFO]\e[0m Boot mode detected: BIOS"
fi

if ! command -v dialog &>/dev/null; then
  echo -e "\e[33m[WARN]\e[0m 'dialog' not found. Installing..."
  pacman -Sy --noconfirm dialog
fi   

