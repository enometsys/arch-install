#!/bin/env bash

# TODO: use a file (as db) to mark finished processes for retrying
#    and caching user inputs (except password)

{ # this ensures the entire script is downloaded #

set -e

readonly COLOR_NC='\033[0m' # no color
readonly COLOR_BW='\033[37;1m' # bright white
readonly INSTALLER_VERSION="v0.1.0"
readonly DEVCE_MAIN=/dev/sda

# ------------------------- INSTALL ARCH -------------------------

# Verify boot mode
[[ -d /sys/firmware/efi/efivars ]] && echo "Error! Make sure UEFI mode is enabled" && exit 1

# Update system clock
timedatectl set-ntp true
# TODO: check timedatectl via timedatectl status

# Start parition manager
echo -ne "Partition? (y|${COLOR_BW}N$COLOR_NC) "; read PARTITION; [[ $PARTITION == y ]] || [[ $PARTITION == Y ]] && PARTITION=y || unset PARTITION
[[ $PARTITION ]] && gdisk $DEVCE_MAIN

# -------------------------- USER INPUT --------------------------

# Reads:
# TODO: set defaults
# - HOST_NAME   device name
# - ROOT_PASS   root account password
# - DUAL_BOOT   (y|n) if installation is dual boot
# - USER        first account's username
# - FULLNAME    first account's fullname
# - PASS        first account's password
# - TZ_REGION   timezone region = Asia
# - TZ_CITY     timezone city = Manila
# - LOCALE      system locale = "en_US.UTF-8 UTF-8"
# - PARTN_ESP   efs system partition = $DUAL_BOOT ? /dev/sda2 : /dev/sda1
# - PARTN_ROOT  root partition where archlinux will be installed = $DUAL_BOOT ? /dev/sda5 : /dev/sda2
# - PARTN_SWAP  swap partition $DUAL_BOOT ? /dev/sda6 : /dev/sda3

declare -A TEMP_VARS

# Retreive cached inputs/installation state
[[ -f .input_cache ]] && vars=$( cat .input_cache | grep -E =.+ ) && for row in $vars; do TEMP_VARS[${row%=*}]=${row#*=}; done;

HOST_NAME=
ROOT_PASS=
DUAL_BOOT=
USER=
FULLNAME=
PASS=
TZ_REGION=Asia
TZ_CITY=Manila
LOCALE=en_US.UTF-8\ UTF-8
PARTN_ROOT=
PARTN_ESP=

echo -e $COLOR_NC
echo -ne "Enter hostname $COLOR_BW${TEMP_VARS[HOST_NAME]}$COLOR_NC: "; read HOST_NAME; HOST_NAME=${HOST_NAME:-${TEMP_VARS[HOST_NAME]}}
read -sp "Enter root password: " ROOT_PASS; echo
read -sp "Enter root password again: " ROOT_PASS_2; echo
[[ $ROOT_PASS != $ROOT_PASS_2 ]] && echo "Root password didn't match" && exit 1
echo -ne "Dualboot? (y|${COLOR_BW}N$COLOR_NC) "; read DUAL_BOOT; [[ $DUAL_BOOT == y ]] || [[ $DUAL_BOOT == Y ]] && DUAL_BOOT=y || unset DUAL_BOOT
echo -ne "Enter username $COLOR_BW${TEMP_VARS[USER]}$COLOR_NC: "; read USER; USER=${USER:-${TEMP_VARS[USER]}}
echo -ne "Enter fullname $COLOR_BW${TEMP_VARS[FULLNAME]}$COLOR_NC: "; read FULLNAME; FULLNAME=${FULLNAME:-${TEMP_VARS[FULLNAME]}}
read -sp "Enter $USER's password: " PASS; echo
read -sp "Enter $USER's password again: " PASS_2; echo
[[ $PASS != $PASS_2 ]] && echo "$USER's password didn't match" && exit 1

[[ $DUAL_BOOT ]] && PARTN_ESP=/dev/sda2 || PARTN_ESP=/dev/sda1
[[ $DUAL_BOOT ]] && PARTN_ROOT=/dev/sda5 || PARTN_ROOT=/dev/sda2

# Cache input except passwords
cat << EOF > .input_cache
HOST_NAME=$HOST_NAME
DUAL_BOOT=$DUAL_BOOT
USER=$USER
FULLNAME=$FULLNAME
PASS=$PASS
TZ_REGION=$TZ_REGION
TZ_CITY=$TZ_CITY
LOCALE=$LOCALE
DEVCE_MAIN=$DEVCE_MAIN
PARTN_ESP=$PARTN_ESP
EOF

cp .input_cache /mnt

# =================================================================================
#                             INSTALLATION PART 2
# =================================================================================

cat << PART_2_EOF > /mnt/install2.sh
# ----------------------- CONFIGURE SYSTEM -----------------------

echo "Configuring system..."

# Set timezone
echo "Setting timezone..."
ln -sf $(echo "/usr/share/zoneinfo/$TZ_REGION/$TZ_CITY") /etc/localtime
hwclock --systohc

# Set locale
echo "Setting locale..."
sed -ir "s|# *$LOCALE|$LOCALE|" /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf

# Set hostname
echo "Setting hostname..."
echo $HOST_NAME > /etc/hostname
echo "127.0.0.1	localhost\n::1		localhost\n127.0.1.1	$HOST_NAME.localdomain	$HOST_NAME"

# Configure network
echo "Configuring network..."
pacman -Syu --noconfirm iw wpa_supplicant dialog

# Initramfs
echo "Creating initramsfs..."
mkinitcpio -p linux

# Install system apps
echo "Installing system utils..."
## file system
pacman -Syu --noconfirm ntfs-3g exfat-utils
## fonts
pacman -Syu --noconfirm ttf-dejavu noto-fonts-emoji
## text processing
pacman -Syu --noconfirm gedit vim
## cli
pacman -Syu --noconfirm unrar xclip wget curl git

# Display
echo "Configuring display..."
pacman -Syu --noconfirm bumblebee mesa nvidia mesa-demos
systemctl enable bumblebeed

# Bluetooth
echo "Configuring bluetooth..."
pacman -Syu --noconfirm bluez bluez-utils blueman
systemctl start bluetooth

# Apps
echo "Installing apps..."
## media
pacman -Syu --noconfirm vlc
## downloader
pacman -Syu --noconfirm aria2 uget
## reader
pacman -Syu --noconfirm fbreader

# Install DE
echo "Installing Desktop environment..."
pacman -Syu --noconfirm gnome gnome-tweaks
systemctl enable gdm
systemctl enable NetworkManager

# Configure sudoers
echo "Defaults insults" >> /etc/sudoers
visudo -c -f /etc/sudoers

# Set root password
echo "Setting passwords..."
echo -e "$ROOT_PASS\n$ROOT_PASS" | passwd

# Bootloader
echo "Installing bootloader..."
pacman -Syu --noconfirm efibootmgr grub intel-ucode
mkdir -p /boot/efi
mount $EFS /boot/efi
grub-install $DEVCE_MAIN
grub-mkconfig -o /boot/grub/grub.cfg

# ----------------------- CREATE FIRST USER -----------------------

echo "Creating user $USER..."

# Create user
pacman -Syu --noconfirm zsh zsh-completions
useradd -m -g wheel -s /bin/zsh -c "$FULL_NAME" $USER
echo -e "$PASS\n$PASS" | passwd $USER

# Configure sudoers
echo "$USER   ALL=(ALL) ALL" >> /etc/sudoers
visudo -c -f /etc/sudoers

# Configure userspace
echo "Configuring userspace of $USER..."
cd /home/metsys

# Yaourt
echo "Installing yaourt..."
rm -rf package-query yaourt
sudo -u $USER git clone https://aur.archlinux.org/package-query.git
cd package-query
sudo -u $USER makepkg -si --noconfirm
cd ..
sudo -u $USER git clone https://aur.archlinux.org/yaourt.git
cd yaourt
sudo -u $USER makepkg -si --noconfirm
cd ..
rm -rf package-query yaourt

# Zsh
echo "Configuring zsh..."
sudo -u $USER yaourt -Syu --aur --noconfirm antigen-git
sudo -u $USER curl -o .zshrc "https://raw.githubusercontent.com/enometsys/arch-install/$INSTALLER_VERSION/.zshrc"
cat .zshrc | sudo -u $USER zsh

# Devtools
echo "Installing devtools..."
# node
pacman -Syu --noconfirm yarn
nvm install --lts
nvm install node
## browser
sudo -u $USER yaourt -Syu --aur --noconfirm google-chrome
## ide
sudo -u $USER yaourt -Syu --aur --noconfirm otf-fira-code visual-studio-code-bin
cat << EOF | while read ext; do sudo -u $USER code --install-extension $ext; done;
mikestead.dotenv
EditorConfig.editorconfig
donjayamanne.githistory
chenxsan.vscode-standardjs
christian-kohler.npm-intellisense
roblourens.npm-link-status
christian-kohler.path-intellisense
wayou.vscode-todo-highlight
octref.vetur
robertohuertasm.vscode-icons
CoenraadS.bracket-pair-colorizer
EOF
sudo -u $USER mkdir -p .config/Code/User
sudo -u $USER curl -o .config/Code/User/settings.json "https://raw.githubusercontent.com/enometsys/arch-install/$INSTALLER_VERSION/vs-code-user-settings.json"
## db
pacman -Syu --noconfirm mongodb mongodb-tools
systemctl enable  mongodb
sudo -u $USER yaourt -Syu --aur --noconfirm mongodb-compass
## platforms
sudo -u $USER yaourt -Syu --aur --noconfirm heroku-cli
## protocols
pacman -Syu --noconfirm openssh weechat
sudo -u $USER yaourt -Syu --aur --noconfirm postman
## runtime/devkit
pacman -Syu --noconfirm jdk9-openjdk texlive-core
## arduino
pacman -Syu --noconfirm arduino arduino-docs arduino-avr-core

# Permissions
echo "Configuring display..."
gpasswd -a $USER bumblebee
gpasswd -a $USER uucp
gpasswd -a $USER lock

# First login setup
# Scan other OS for dual booting
if [ $DUAL_BOOT ]
then
cat << EOF > /etc/profile.d/dual_boot_config.sh
echo "Configuring dual boot..."
pacman -Syu --noconfirm os-prober
grub-mkconfig -o /boot/grub/grub.cfg
rm -f /etc/profile.d/dual_boot_config.sh
reboot
EOF
fi

# Cleanup
rm -f /.input_cache
rm -f /install2.sh

exit # exit chroot
PART_2_EOF

# =================================================================================
#                           END OF INSTALLATION PART 2
# =================================================================================

# Mount partitions
# swap
mkswap $PARTN_SWAP
swapon $PARTN_SWAP
# root
mkfs.ext4 -q -L "OS-Arch" $PARTN_ROOT
mount $PARTN_ROOT /mnt

# TODO: modify /etc/pacman.d/mirrorlist to move philippine server to top

# install base packages
pacstrap /mnt base base-devel

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab
[[ -f /mnt/etc/fstab ]] && echo "Fstab exists" || echo "Error! Fstab does not exist" && exit 1

# Configure new system
arch-chroot /mnt /install2.sh

# Cleanup
rm -f .input_cache
umount -R /mnt
reboot

# Success
echo "Installation finished. reboot the machine"

} # this ensures the entire script is downloaded #
