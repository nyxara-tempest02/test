#!/bin/bash

##############################################
##                                          ##
## Author: nyxara                           ##
## Github: www.github.com/nyxara-tempest02  ##
##############################################

# Simple log function for formatted messages
log() {
  local LEVEL="$1"
  shift
  local MESSAGE="$@"

  case "$LEVEL" in 
    INFO)
      echo -e "\e[32m[INFO]\e[0m $MESSAGE"
      ;;
    WARN)
      echo -e "\e[33m[WARN]\e[0m $MESSAGE"
      ;;
    ERROR)
      echo -e "\e[31m[ERROR]\e[0m $MESSAGE"
      ;;
    *)
      echo -e "\e[34m[LOG]\e[0m $MESSAGE"
      ;;
  esac
}

partition_disks(){
  log INFO "Starting disk partitioning."

  dialog --backtitle "Arch Linux Installation" \
  --title "Confirm Disk Partitioning" \
  --yesno "WARNING: All data on $INSTALL_DISK will be erased. Continue?" 7 60 \
  3>&1 1>&2 2>&3 3>&-

  if [[ $? -ne 0 ]]; then
    log ERROR "Disk partitioning aborted by user."
    exit 1
  fi

  # Wipe the disk
  sgdisk -Z $INSTALL_DISK
  
  # Create partitions
  if [[ "$BOOT_MODE" == "UEFI" ]]; then
    # Partition 1: EFI System Partition
    sgdisk -n 1:0+512M -t 1:ef00 $INSTALL_DISK
  else
    # Partition 1: BIOS Boot partition
    sgdisk -n 1:0:+1G -t 1:8300 $INSTALL_DISK
  fi

  # Initialize partition number
  PARTITION_NUMBER=2

  # Create swap and root (and home if selected)
  if [[ "$USE_LVM" == "no" && "$USE_ENCRYPTION" == "no" ]]; then
    # Partition for swap
    sgdisk -n ${PARTITION_NUMBER}:0:0 -t ${PARTITION_NUMBER}:8200 $INSTALL_DISK
    SWAP_PART="${INSTALL_DISK}${PARTITION_NUMBER}"
    PARTITION_NUMBER=$((PARTITION_NUMBER + 1))

    # Partition for root
    if [[ "$PART_SCHEME" == "1" ]]; then
      sgdisk -n ${PARTITION_NUMBER}:0:0 -t ${PARTITION_NUMBER}:8300 $INSTALL_DISK
      ROOT_PART="${INSTALL_DISK}${PARTITION_NUMBER}"
    elif [["$PART_SCHEME" == "2"]]; then
      sgdisk -n ${PARTITION_NUMBER}:0:+20G -t ${PARTITION_NUMBER}:8300 $INSTALL_DISK
      ROOT_PART="${INSTALL_DISK}${PARTITION_NUMBER}"
      PARTITION_NUMBER=$((PARTITION_NUMBER + 1))
      
      # Partition for home 
      sgdisk -n ${PARTITION_NUMBER}:0:0 -t ${PARTITION_NUMBER}:8300 $INSTALL_DISK
      HOME_PART="${INSTALL_DISK}${PARTITION_NUMBER}"
    fi
  else
    # Create a partition for LVM or LUKS container
    sgdisk -n ${PARTITION_NUMBER}:0:0 -t ${PARTITION_NUMBER}:8300 $INSTALL_DISK
    LVM_PART="${INSTALL_DISK}${PARTITION_NUMBER}"
  fi

  # Inform the kernel of partition changes
  partprobe $INSTALL_DISK

  # Format the EFI or boot partition
  if [[ "$BOOT_MODE" == "UEFI" ]]; then
    mkfs.fat -F32 ${INSTALL_DISK}
  else
    mkfs.ext4 ${INSTALL_DISK}
  fi

  # Format and mount partitions
  if [[ "$USE_LVM" == "no" && "$USE_ENCRYPTION" == "no" ]]; then
    # Format root partition
    mkfs.$FS_TYPE $ROOT_PART
   
    log INFO "Function worked correctly until here"
  }


# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  log ERROR "This script must be run as root."
  exit 1
fi


# Detect boot mode
if [[ -d /sys/firmware/efi/efivars ]]; then
  BOOT_MODE="UEFI"
  log INFO"Boot mode detected: UEFI"
else
  BOOT_MODE="BIOS"
  log INFO "Boot mode detected: BIOS"
fi

# Install 'dialog' if not in the system for an enhanced user experience
if ! command -v dialog &>/dev/null; then
  log WARN "'dialog' not found. Installing..."
  pacman -Sy --noconfirm dialog
else
  echo -e "\e[32m[INFO]\e[0m 'dialog' is already installed in the system."
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
  log ERROR "No template selected. Exiting."
  exit 1
fi

log INFO "Template selected: $TEMPLATE"

# Get list of disks
mapfile -t disks < <(lsblk -dn -o NAME,SIZE)

# Check if any disks were found
if [[ ${#disks[@]} -eq 0 ]]; then
  log ERROR "No disks found. Exiting."
  exit 1
fi

# Prepare the array for the dialog menu
DISK_LISTS=()
for disk_info in "${disks[@]}"; do 
  DEV_NAME=$(echo "$disk_info" | awk '{print $1}')
  DEV_SIZE=$(echo "$disk_info" | awk '{print $2}')
  DISK_LIST+=("$DEV_NAME" "$DEV_NAME - $DEV_SIZE")
done

# Disk selection menu
DISK_CHOICE=$(dialog --backtitle "Arch Linux Installation" \
--title "Disk Selection" \
--menu "Select the disk to install Arch Linux on:" 15 60 10 \
"${DISK_LIST[@]}" \
3>&1 1>&2 2>&3 3>&-)

# Check if the user cancelled the dialog
if [[ $? -ne 0 ]]; then
  log ERROR "Disk selection cancelled. Exiting."
  exit 1
fi

if [[ -z $DISK_CHOICE ]]; then
  log ERROR "No disk selected. Exiting."
fi

INSTALL_DISK="/dev/$DISK_CHOICE"
log INFO "Disk selected: $INSTALL_DISK"

# Partitioning scheme menu
PART_SCHEME=$(dialog --backtitle "Arch Linux Installation" \
--title "Partitioning Scheme" \
--menu "Choose a partitioning scheme:" 15 60 4 \
"1" "Root, Swap, and Boot" \
"2" "Root, Swap, Boot, and separate Home partition" \
3>&1 1>&2 2>&3 3>&-)

# Check if the user cancelled the dialog
if [[ $? -ne 0 ]]; then
  log ERROR "Partitioning scheme selection cancelled. Exiting."
  exit 1
fi

log INFO "Partitioning scheme selected: $PART_SCHEME"

# Ask if the user wants to use LVM
dialog --backtitle "Arch Linux Installation" \
--title "Set LVM" \
--yesno "Do you want to use LVM (Logical Volume Manager)?" 7 60 \
3>&1 1>&2 2>&3 3>&-

if [[ $? -eq 0 ]]; then
  USE_LVM="yes"
  log INFO "User chose to use LVM."
else
  USE_LVM="no"
  log INFO "User chose not to use LVM."
fi

# Ask if the user wants to encrypt the partitions
dialog --backtitle "Arch Linux Installation" \
--title "Set Encryption" \
--yesno "Do you want to encrypt your partitions?" 7 60 \
3>&1 1>&2 2>&3 3>&-

if [[ $? -eq 0 ]]; then
  USE_ENCRYPTION="yes"
  log INFO "User chose to encrypt partitions."

  # Ask whether to encrypt root only or root and swap
  ENCRYPT_SWAP_CHOICE=$(dialog --backtitle "Arch Linux Installation" \
  --title "Encrypt Swap" \
  --menu "Which partitions do you want to encrypt?" 15 60 2 \
  "1" "Encrypt root partition only" \
  "2" "Encrypt both root and swap partitions" \
  3>&1 1>&2 2>&3 3>&-)

  if [[ $? -ne 0 ]]; then
    log ERROR "Encryption selection canceled. Exiting."
    exit 1
  fi

  case $ENCRYPT_SWAP_CHOICE in
    1)
      ENCRYPT_SWAP="no"
      log INFO "User chose to encrypt root partition only."
      ;;
    2)
      ENCRYPT_SWAP="yes"
      log INFO "User chose t o encrypt both root and swap partitions."
      ;;
    *)
      log ERROR "Invalid selection for encryption. Exiting."
      exit 1
      ;;
    esac
  else
    USE_ENCRYPTION="no"
    log INFO "User chose not to encrypt partitions."
  fi

  # Export variables to chroot environment

  

  # PENDING:
  # Create function to partition the disk
  # Choose hostname
  # Create a common user (optional)
  # Root passwd (optional)
  # username passwd (optional)
  # autoconfigure /etc/hosts
  # Set time zone
  # Set locale
  # Set filesystem types
  # Packages for the chroot environment
