# this is my own script
# curl -sSL https://raw.githubusercontent.com/charagarlnad/miscellaneous/master/arch_install.sh | bash

bootstrapper_dialog() {
    DIALOG_RESULT=$(dialog --clear --stdout --backtitle "Chara's Arch Installer" --no-shadow "$@" 0 0 2>/dev/null)
}

if [ ! -d '/sys/firmware/efi/efivars' ]; then
    bootstrapper_dialog --title "Error" --msgbox "EFIVARS not detected, please reboot into UEFI.\n"
    clear
    exit 0
fi

if ! ping -c 1 8.8.8.8 > /dev/null; then
    bootstrapper_dialog --title "Error" --msgbox "Network connection not detected, please connect an ethernet cable or use wifi-menu to connect to wifi.\n"
    clear
    exit 0
fi

# ensure clock is correct
timedatectl set-ntp true

echo 'Wiping existing partition tables on /dev/sda...'
sgdisk -Z /dev/sda
sgdisk -o /dev/sda

echo 'Partitioning /dev/sda...'
sgdisk -n 1:0:+250M /dev/sda
sgdisk -n 2:0:0 /dev/sda

echo 'Setting partition types...'
sgdisk -t 1:ef00 /dev/sda
sgdisk -t 2:8300 /dev/sda

echo 'Formatting partitions...'
mkfs.fat -F 32 /dev/sda1
mkfs.xfs -f /dev/sda2

echo 'Mounting partitions...'
mount /dev/sda2 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot

echo 'Installing packages...'
pacstrap /mnt base fakeroot make gcc binutils patch dialog nano efibootmgr git sudo wpa_supplicant networkmanager

echo 'Adding fstab...'
genfstab -U -p /mnt > /mnt/etc/fstab

bootstrapper_dialog --title 'User Name' --inputbox "Please enter a username.\n"
user_name="$DIALOG_RESULT"

bootstrapper_dialog --title "User Password" --passwordbox "Please enter a strong password.\n"
user_password="$DIALOG_RESULT"

bootstrapper_dialog --title "Hostname" --inputbox "Please enter a hostname.\n"
hostname="$DIALOG_RESULT"

arch-chroot /mnt /bin/bash <<EOF
echo 'Setting locale...'
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
locale-gen

echo 'Enabling sudo...'
echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers
chmod 0440 /etc/sudoers

ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
timedatectl set-ntp true
hwclock --systohc

echo 'Adding user...'
useradd -m -G wheel,systemd-journal -s /bin/bash "${user}"
echo "${user_name}:${user_password}" | chpasswd

echo 'Installing Yay...'
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
sudo -u "${user_name}" makepkg -si
cd ..
rm -rf yay-bin
sudo sed -i 's/#Color/Color/' /etc/pacman.conf

systemctl enable NetworkManager

echo "${hostname}" > /etc/hostname
echo \
"127.0.0.1	localhost
::1		localhost
127.0.1.1	${hostname}.localdomain	${hostname}" \
> /etc/hosts

echo 'Installing EFISTUB...'
efibootmgr --disk /dev/sda --part 1 --create --label 'Arch' --loader /vmlinuz-linux --unicode 'root=/dev/sda rw mitigations=off initrd=\initramfs-linux.img'
EOF

umount -R /mnt
sync

bootstrapper_dialog --title "Done" --msgbox "Installation complete! Reboot into your new arch install :3\n"
