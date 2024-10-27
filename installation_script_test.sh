#!/bin/bash

##############################################
## Author: nyxara                           ##
## Github: www.github.com/nyxara-tempest02  ##
##############################################

# Define log function
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

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    log ERROR "This script must be run as root."
    exit 1
fi

log INFO "Starting Arch Linux Installation Script"

# Detect boot mode
if [[ -d /sys/firmware/efi/efivars ]]; then
    BOOT_MODE="UEFI"
    log INFO "Boot mode detected: UEFI"
else
    BOOT_MODE="BIOS"
    log INFO "Boot mode detected: BIOS"
fi

# Install dialog if not present
if ! command -v dialog &>/dev/null; then
    log WARN "'dialog' not found. Installing..."
    pacman -Sy --noconfirm dialog
fi

# Template selection menu
TEMPLATE=$(dialog --clear --backtitle "Arch Linux Installation" \
--title "Template Selection" \
--menu "Choose an installation template:" 15 60 4 \
"1" "Minimal Install" \
"2" "Cybersecurity Oriented" \
"3" "Cybersecurity with Dev Tools" \
"4" "Custom Installation" \
3>&1 1>&2 2>&3 3>&-)

if [[ $? -ne 0 ]]; then
    log ERROR "Template selection cancelled. Exiting."
    exit 1
fi

if [[ -z $TEMPLATE ]]; then
    log ERROR "No template selected. Exiting."
    exit 1
fi

log INFO "Template selected: $TEMPLATE"

# Disk Selection Section

# Get list of disks with models
mapfile -t disks < <(lsblk -dn -o NAME,SIZE,MODEL)

# Check if any disks were found
if [[ ${#disks[@]} -eq 0 ]]; then
    log ERROR "No disks found. Exiting."
    exit 1
fi

# Prepare the array for the dialog menu
DISKS_LIST=()
for disk_info in "${disks[@]}"; do
    DEV_NAME=$(echo "$disk_info" | awk '{print $1}')
    DEV_SIZE=$(echo "$disk_info" | awk '{print $2}')
    DEV_MODEL=$(echo "$disk_info" | cut -d' ' -f3-)
    DISKS_LIST+=("$DEV_NAME" "$DEV_NAME - $DEV_SIZE - $DEV_MODEL")
done

# Disk selection menu
DISK_CHOICE=$(dialog --backtitle "Arch Linux Installation" \
--title "Disk Selection" \
--menu "Select the disk to install Arch Linux on:" 15 60 10 \
"${DISKS_LIST[@]}" \
3>&1 1>&2 2>&3 3>&-)

# Check if the user cancelled the dialog
if [[ $? -ne 0 ]]; then
    log ERROR "Disk selection cancelled. Exiting."
    exit 1
fi

if [[ -z $DISK_CHOICE ]]; then
    log ERROR "No disk selected. Exiting."
    exit 1
fi

INSTALL_DISK="/dev/$DISK_CHOICE"
log INFO "Disk selected: $INSTALL_DISK"

# Partition scheme selection menu
PART_SCHEME=$(dialog --backtitle "Arch Linux Installation" \
--title "Partition Scheme Selection" \
--menu "Choose a partitioning scheme:" 15 60 2 \
"1" "Root, Swap, and Boot partitions" \
"2" "Root, Swap, Boot, and separate Home partition" \
3>&1 1>&2 2>&3 3>&-)

# Check if the user canceled the dialog
if [[ $? -ne 0 ]]; then
    log ERROR "Partition scheme selection canceled. Exiting."
    exit 1
fi

if [[ -z $PART_SCHEME ]]; then
    log ERROR "No partition scheme selected. Exiting."
    exit 1
fi

log INFO "Partition scheme selected: $PART_SCHEME"

# Ask if the user wants to use LVM
dialog --backtitle "Arch Linux Installation" \
--title "LVM Option" \
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
--title "Encryption Option" \
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
            log INFO "User chose to encrypt both root and swap partitions."
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

# Filesystem selection menu
FS_CHOICE=$(dialog --backtitle "Arch Linux Installation" \
--title "Filesystem Selection" \
--menu "Choose filesystem for the root partition:" 15 60 3 \
"1" "ext4" \
"2" "btrfs" \
"3" "xfs" \
3>&1 1>&2 2>&3 3>&-)

if [[ $? -ne 0 ]]; then
    log ERROR "Filesystem selection canceled. Exiting."
    exit 1
fi

case $FS_CHOICE in
    1) FS_TYPE="ext4" ;;
    2) FS_TYPE="btrfs" ;;
    3) FS_TYPE="xfs" ;;
    *)
        log ERROR "Invalid filesystem selection. Exiting."
        exit 1
        ;;
esac

log INFO "Filesystem selected: $FS_TYPE"

# Time zone input
TIMEZONE=$(dialog --backtitle "Arch Linux Installation" \
--title "Time Zone Configuration" \
--inputbox "Enter your time zone (e.g., 'America/New_York'):" 8 60 \
3>&1 1>&2 2>&3 3>&-)

if [[ $? -ne 0 ]]; then
    log ERROR "Time zone configuration canceled. Exiting."
    exit 1
fi

if [[ -z $TIMEZONE ]]; then
    log ERROR "No time zone entered. Exiting."
    exit 1
fi

log INFO "Time zone set to: $TIMEZONE"

# Locale input
LOCALE=$(dialog --backtitle "Arch Linux Installation" \
--title "Locale Configuration" \
--inputbox "Enter your locale (e.g., 'en_US.UTF-8'):" 8 60 \
3>&1 1>&2 2>&3 3>&-)

if [[ $? -ne 0 ]]; then
    log ERROR "Locale configuration canceled. Exiting."
    exit 1
fi

if [[ -z $LOCALE ]]; then
    log ERROR "No locale entered. Exiting."
    exit 1
fi

log INFO "Locale set to: $LOCALE"

# Hostname input
HOSTNAME=$(dialog --backtitle "Arch Linux Installation" \
--title "Hostname Configuration" \
--inputbox "Enter a hostname for your system:" 8 60 \
3>&1 1>&2 2>&3 3>&-)

if [[ $? -ne 0 ]]; then
    log ERROR "Hostname configuration canceled. Exiting."
    exit 1
fi

if [[ -z $HOSTNAME ]]; then
    log ERROR "No hostname entered. Exiting."
    exit 1
fi

log INFO "Hostname set to: $HOSTNAME"

# Username input
USERNAME=$(dialog --backtitle "Arch Linux Installation" \
--title "User Account Creation" \
--inputbox "Enter a username for the new user:" 8 60 \
3>&1 1>&2 2>&3 3>&-)

if [[ $? -ne 0 ]]; then
    log ERROR "User account creation canceled. Exiting."
    exit 1
fi

if [[ -z $USERNAME ]]; then
    log ERROR "No username entered. Exiting."
    exit 1
fi

# Administrative privileges confirmation
dialog --backtitle "Arch Linux Installation" \
--title "Administrative Privileges" \
--yesno "Should the user '$USERNAME' have administrative privileges?" 7 60 \
3>&1 1>&2 2>&3 3>&-

if [[ $? -eq 0 ]]; then
    IS_ADMIN="yes"
    log INFO "User '$USERNAME' will have administrative privileges."
else
    IS_ADMIN="no"
    log INFO "User '$USERNAME' will not have administrative privileges."
fi

# Set default swap size (you can adjust this or calculate based on RAM)
SWAP_SIZE="2G"

# Partitioning Function
partition_disk() {
    log INFO "Starting disk partitioning."

    # Confirm disk partitioning
    dialog --backtitle "Arch Linux Installation" \
    --title "Confirm Partitioning" \
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
        sgdisk -n 1:0:+512M -t 1:ef00 $INSTALL_DISK
    else
        # Partition 1: BIOS Boot Partition
        sgdisk -n 1:0:+1G -t 1:8300 $INSTALL_DISK
    fi

    # Initialize partition number
    PART_NUM=2

    # Create swap and root (and home if selected)
    if [[ "$USE_LVM" == "no" && "$USE_ENCRYPTION" == "no" ]]; then
        # Partition for Swap
        sgdisk -n ${PART_NUM}:0:+${SWAP_SIZE} -t ${PART_NUM}:8200 $INSTALL_DISK
        SWAP_PART="${INSTALL_DISK}${PART_NUM}"
        PART_NUM=$((PART_NUM + 1))

        # Partition for Root
        if [[ "$PART_SCHEME" == "1" ]]; then
            sgdisk -n ${PART_NUM}:0:0 -t ${PART_NUM}:8300 $INSTALL_DISK
            ROOT_PART="${INSTALL_DISK}${PART_NUM}"
        elif [[ "$PART_SCHEME" == "2" ]]; then
            sgdisk -n ${PART_NUM}:0:+20G -t ${PART_NUM}:8300 $INSTALL_DISK
            ROOT_PART="${INSTALL_DISK}${PART_NUM}"
            PART_NUM=$((PART_NUM + 1))
            # Partition for Home
            sgdisk -n ${PART_NUM}:0:0 -t ${PART_NUM}:8300 $INSTALL_DISK
            HOME_PART="${INSTALL_DISK}${PART_NUM}"
        fi
    else
        # Create a partition for LVM or LUKS container
        sgdisk -n ${PART_NUM}:0:0 -t ${PART_NUM}:8300 $INSTALL_DISK
        LVM_PART="${INSTALL_DISK}${PART_NUM}"
    fi

    # Inform the kernel of partition changes
    partprobe $INSTALL_DISK

    log INFO "Disk partitioning completed."

    # Format the EFI or boot partition
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        mkfs.fat -F32 ${INSTALL_DISK}1
    else
        mkfs.ext4 ${INSTALL_DISK}1
    fi

    # Format and mount partitions
    if [[ "$USE_LVM" == "no" && "$USE_ENCRYPTION" == "no" ]]; then
        # Format root partition
        mkfs.$FS_TYPE $ROOT_PART

        # Format home partition if selected
        if [[ "$PART_SCHEME" == "2" ]]; then
            mkfs.$FS_TYPE $HOME_PART
        fi

        # Format swap partition
        mkswap $SWAP_PART

        # Mount partitions
        mount $ROOT_PART /mnt

        if [[ "$PART_SCHEME" == "2" ]]; then
            mkdir -p /mnt/home
            mount $HOME_PART /mnt/home
        fi

        mkdir -p /mnt/boot
        mount ${INSTALL_DISK}1 /mnt/boot

        swapon $SWAP_PART

        log INFO "Partitions formatted and mounted."

    else
        # If using LVM or encryption
        if [[ "$USE_ENCRYPTION" == "yes" ]]; then
            # Set up encryption on LVM_PART
            log INFO "Setting up encryption on $LVM_PART."
            cryptsetup luksFormat $LVM_PART

            # Open the encrypted partition
            log INFO "Opening encrypted partition."
            cryptsetup open $LVM_PART cryptlvm

            PV_PART="/dev/mapper/cryptlvm"
        else
            PV_PART="$LVM_PART"
        fi

        # Set up LVM
        pvcreate $PV_PART
        vgcreate vg0 $PV_PART

        # Create logical volumes
        if [[ "$PART_SCHEME" == "1" ]]; then
            lvcreate -L $SWAP_SIZE vg0 -n lv_swap
            lvcreate -l 100%FREE vg0 -n lv_root
        elif [[ "$PART_SCHEME" == "2" ]]; then
            lvcreate -L $SWAP_SIZE vg0 -n lv_swap
            lvcreate -L 20G vg0 -n lv_root
            lvcreate -l 100%FREE vg0 -n lv_home
        fi

        # Encrypt swap if selected
        if [[ "$ENCRYPT_SWAP" == "yes" ]]; then
            log INFO "Encrypting swap partition."
            cryptsetup luksFormat /dev/vg0/lv_swap
            cryptsetup open /dev/vg0/lv_swap cryptswap
            SWAP_PART="/dev/mapper/cryptswap"
        else
            SWAP_PART="/dev/vg0/lv_swap"
        fi

        # Format logical volumes
        mkfs.$FS_TYPE /dev/vg0/lv_root

        if [[ "$PART_SCHEME" == "2" ]]; then
            mkfs.$FS_TYPE /dev/vg0/lv_home
        fi

        mkswap $SWAP_PART

        # Mount partitions
        mount /dev/vg0/lv_root /mnt

        if [[ "$PART_SCHEME" == "2" ]]; then
            mkdir -p /mnt/home
            mount /dev/vg0/lv_home /mnt/home
        fi

        mkdir -p /mnt/boot
        mount ${INSTALL_DISK}1 /mnt/boot

        swapon $SWAP_PART

        log INFO "LVM setup complete. Partitions formatted and mounted."
    fi
}

# Call the partitioning function
partition_disk

# Install base system
pacstrap -K /mnt base linux linux-firmware networkmanager nano

log INFO "Base system installed."

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

log INFO "fstab generated."

# Export variables for chroot
cat <<EOF > /mnt/root/vars.sh
TIMEZONE="$TIMEZONE"
LOCALE="$LOCALE"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
IS_ADMIN="$IS_ADMIN"
BOOT_MODE="$BOOT_MODE"
INSTALL_DISK="$INSTALL_DISK"
FS_TYPE="$FS_TYPE"
PART_SCHEME="$PART_SCHEME"
USE_LVM="$USE_LVM"
USE_ENCRYPTION="$USE_ENCRYPTION"
ENCRYPT_SWAP="$ENCRYPT_SWAP"
EOF

# Copy the chroot script into the new system
cat <<'EOL' > /mnt/root/install_chroot.sh
#!/bin/bash

# Define log function
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

if [[ $1 == "--configure" ]]; then
    # Source variables
    source /root/vars.sh

    # Set the time zone
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc

    # Generate the locales
    echo "$LOCALE UTF-8" >> /etc/locale.gen
    locale-gen

    echo "LANG=$LOCALE" > /etc/locale.conf

    # Set the hostname
    echo "$HOSTNAME" > /etc/hostname

    # Update hosts file
    cat <<EOF2 > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF2

    # Set root password
    log INFO "Setting root password."
    passwd

    # Create new user
    useradd -m $USERNAME
    log INFO "Setting password for user '$USERNAME'."
    passwd $USERNAME

    # Grant administrative privileges if selected
    if [[ "$IS_ADMIN" == "yes" ]]; then
        log INFO "Granting administrative privileges to '$USERNAME'."
        usermod -aG wheel $USERNAME
        # Uncomment wheel group in sudoers
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    fi

    # Install necessary packages
    pacman -Sy --noconfirm grub efibootmgr networkmanager sudo

    # Install LVM and encryption packages if needed
    if [[ "$USE_LVM" == "yes" ]]; then
        pacman -S --noconfirm lvm2
    fi

    if [[ "$USE_ENCRYPTION" == "yes" ]]; then
        pacman -S --noconfirm cryptsetup
    fi

    # Enable necessary services
    systemctl enable NetworkManager

    # Configure mkinitcpio hooks
    HOOKS="base udev autodetect modconf block"

    if [[ "$USE_ENCRYPTION" == "yes" ]]; then
        HOOKS="$HOOKS encrypt"
    fi

    if [[ "$USE_LVM" == "yes" ]]; then
        HOOKS="$HOOKS lvm2"
    fi

    HOOKS="$HOOKS filesystems keyboard fsck"

    sed -i "s/^HOOKS=.*/HOOKS=($HOOKS)/" /etc/mkinitcpio.conf

    # Regenerate initramfs
    mkinitcpio -P

    # Install GRUB
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    else
        grub-install --target=i386-pc $INSTALL_DISK
    fi

    # Configure GRUB for encrypted partitions
    if [[ "$USE_ENCRYPTION" == "yes" ]]; then
        # Get UUID of encrypted partition
        ENCRYPT_UUID=$(blkid -s UUID -o value $LVM_PART)
        sed -i "s/^GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$ENCRYPT_UUID:cryptlvm\"/" /etc/default/grub
    fi

    # Generate GRUB configuration
    grub-mkconfig -o /boot/grub/grub.cfg

    # Configure encrypted swap
    if [[ "$ENCRYPT_SWAP" == "yes" ]]; then
        echo "cryptswap /dev/vg0/lv_swap /dev/urandom swap,cipher=aes-xts-plain64,size=256" >> /etc/crypttab
        echo "/dev/mapper/cryptswap none swap defaults 0 0" >> /etc/fstab
    else
        echo "/dev/vg0/lv_swap none swap defaults 0 0" >> /etc/fstab
    fi

    log INFO "System configuration completed. You can now exit chroot and reboot."
    exit 0
fi
EOL

# Make the chroot script executable
chmod +x /mnt/root/install_chroot.sh

# Chroot into the new system and run the configuration script
arch-chroot /mnt /root/install_chroot.sh --configure

# Clean up
rm /mnt/root/install_chroot.sh
rm /mnt/root/vars.sh

log INFO "Installation completed successfully. You can now reboot the system."

