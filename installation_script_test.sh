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

# Template selection menu
TEMPLATE=$(dialog --clear --backtitle "Arch Linux Installation" \
--title "Template Selection" \
--menu "Choose an installation template:" 15 60 4 \
"1" "Minimal Install" \
"2" "Cybersecurity Oriented" \
"3" "Custom Installation" \
3>&1 1>&2 2>&3 3>&-)

if [[ -z $TEMPLATE ]]; then
  echo -e "\e[31m[ERROR]\e[0m No template selected. Exiting."
  exit 1
fi

echo -e "\e[32m[INFO]\e[0m Template selected: $TEMPLATE"

#Get list of disks
#mapfile -t DISKS < <(lsblk -d -o NAME,SIZE -n | awk '{print "/dev/"$1 " ("$2")"}')
#DISK_CHOICE=$(dialog --backtitle "Arch Linux Installation" \
#--title "Disk Selection" \
#--menu "Select the disk to install Arch Linux on:" 15 60 ${#DISKS[@]} \
#"${DISKS[@]}" \
#3>&1 1>&2 2>&3 3>&-)

#if [[ -z $DISK_CHOICE ]]; then
#  echo -e "\e[31m[ERROR]\e[0m No disk selected. Exiting."
#  exit 1
#fi

#INSTALL_DISK=$(echo $DISK_CHOICE | awk '{print $1}')
#echo -e "\e[32m[INFO]\e[0m Disk selected: $INSTALL_DISK"
