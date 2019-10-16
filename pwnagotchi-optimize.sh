#!/bin/bash
# this is my personal pwnagotchi script to push out as much battery life as possible, do note that some functionality will be unavailable
# notably bluetooth, video out, and sound will all be unavailable

if (( $EUID != 0 )); then
   echo "This script must be run as root" 
   exit 1
fi

# disable bluetooth
echo "dtoverlay=pi3-disable-bt" >> /boot/config.txt

# disable unneeded services
systemctl disable avahi-daemon.service
systemctl disable keyboard-setup.service
systemctl disable hciuart.service

# disable activity LEDs
echo "dtparam=act_led_trigger=none" >> /boot/config.txt
echo "dtparam=act_led_activelow=on" >> /boot/config.txt

# disable audio if it isn't already
sed -i '/dtparam=audio=on/ s/^#*/#/' /boot/config.txt

# disable i2c/spi if it isn't already
# uncomment spi if you are not using an attached e-ink display
# https://pinout.xyz/pinout/213_inch_e_paper_phat
#sed -i '/dtparam=spi=on/ s/^#*/#/' /boot/config.txt
#sed -i '/dtoverlay=spi1-3cs/ s/^#*/#/' /boot/config.txt
sed -i '/dtoverlay=i2c_arm=on/ s/^#*/#/' /boot/config.txt
sed -i '/dtoverlay=i2c1=on/ s/^#*/#/' /boot/config.txt

# disable uart console
# https://pinout.xyz/pinout/uart
sed -i 's/console=serial0,115200 //g' /boot/cmdline.txt

# remove rainbow splash screen that delays boot
echo "disable_splash=1" >> /boot/config.txt

# remove a 1 second delay at boot
echo "boot_delay=0" >> /boot/config.txt

# give the gpu the minimum amount of memory so there is more system ram available
echo "gpu_mem=16" >> /boot/config.txt

# create novhiq overlay
echo \
'/dts-v1/;
/plugin/;

/ {
        compatible = "brcm,bcm2835";

        fragment@0 {
                target-path = "/soc/mailbox@7e00b840";
                __overlay__ {
                        status = "disabled";
                };
        };

        fragment@1 {
                target-path = "/soc/fb";
                __overlay__ {
                        status = "disabled";
                };
        };
};' \
| dtc -@ -I dts -O dtb -o /boot/overlays/novchiq.dtbo
echo "dtoverlay=novchiq" >> /boot/config.txt

#reboot to apply changes
reboot 0
