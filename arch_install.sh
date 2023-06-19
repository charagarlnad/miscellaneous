# curl -sSL https://raw.githubusercontent.com/charagarlnad/miscellaneous/master/arch_install.sh | tr -d '\r' | bash
# use nmtui to setup wifi in new install
# yay -S xorg-server xorg-xinit mesa xfce4 ark-gtk-theme chromium pulseaudio
# yay -S tlp tlp-rdw acpi_call

# possibly optimize pulseaudio? https://wiki.archlinux.org/index.php/PulseAudio/Troubleshooting#Setting_the_default_fragment_number_and_buffer_size_in_PulseAudio
# arch defaults to mq-deadline which is optimal btw
# if cup rly old or ryzen you can use haveged instead of random.trust_cpu=on

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
mkfs.ext4 /dev/sda2

echo 'Mounting partitions...'
mount -o noatime /dev/sda2 /mnt
mkdir -p /mnt/boot
mount -o noatime /dev/sda1 /mnt/boot

root_uuid=$(blkid -o value -s PARTUUID /dev/sda2)

echo 'Installing core packages...'
# xfsprogs
pacstrap /mnt base linux linux-firmware e2fsprogs fakeroot make gcc binutils patch dialog nano efibootmgr git sudo dropbear dropbear-scp

bootstrapper_dialog --title "WiFi" --yesno "Does this system need packages for WiFi support?\n"
[[ $DIALOG_RESULT -eq 0 ]] && wifi=1 || wifi=0

if (( $wifi == 1 )); then
    pacstrap /mnt iwd networkmanager
fi

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

echo 'Setting the clock...'
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
timedatectl set-ntp true
hwclock --systohc

echo 'Adding user...'
useradd -m -G wheel,systemd-journal -s /bin/bash "${user_name}"
echo "${user_name}:${user_password}" | chpasswd

echo 'Installing Yay...'
git clone https://aur.archlinux.org/yay-bin.git
chmod 777 yay-bin
cd yay-bin
sudo -u "${user_name}" makepkg
find . -name "*.pkg.tar.xz" -exec pacman --noconfirm -U {} \;
cd ..
rm -rf yay-bin
sed -i 's/#Color/Color/' /etc/pacman.conf

echo 'Setting up the network...'
systemctl enable NetworkManager.service
echo "${hostname}" > /etc/hostname
echo \
"127.0.0.1	localhost
::1		localhost
127.0.1.1	${hostname}.localdomain	${hostname}" \
> /etc/hosts

echo 'Enabling SSH...'
systemctl enable dropbear.service

# usually targets before sysinit which can cause this to delay boot
echo 'Optimizing systemd-backlight.service...'
echo \
'[Unit]
Before=graphical.target shutdown.target' \
> '/etc/systemd/system/systemd-backlight@.service'

echo 'Enabling TRIM...'
systemctl enable fstrim.timer

# yeah xfs fsck does nothing and breaks a silent boot
# fsck hook only does root FS so this is safe to disable if you are using xfs
# probably wanna disable fsck in the fstab too doe
# echo 'Disabling fsck'
# sed -i 's/\ fsck)/)/g' /etc/mkinitcpio.conf
mkinitcpio -p linux

# vga=current i915.fastboot=1
echo 'Installing EFISTUB...'
efibootmgr --disk /dev/sda --part 1 --create --label 'Arch' --loader /vmlinuz-linux --unicode "root=PARTUUID=${root_uuid} rootfstype=ext4 rw random.trust_cpu=on mitigations=off quiet loglevel=3 rd.systemd.show_status=auto rd.udev.log_priority=3 initrd=\initramfs-linux.img"
EOF

umount -R /mnt
sync

bootstrapper_dialog --title "Done" --msgbox "Installation complete! The system will now reboot into your new arch install :3\n"
reboot 0
