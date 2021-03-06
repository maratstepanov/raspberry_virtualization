#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: launch_virtual_rasp.sh <virtual_rasp_name>"
    exit;
fi

name=$1
echo "Creating virtual rasp "$name"!"

lxc launch ubuntu:16.04 $name

MYUID=`sudo ls -l /var/lib/lxd/containers/"$name"/rootfs/ | grep root | awk '{}{print $3}{}'`

lxc exec "$name" -- addgroup gpio
lxc exec "$name" -- usermod -a -G gpio ubuntu
MYGID=$(($MYUID + `lxc exec "$name" -- sed -nr "s/^gpio:x:([0-9]+):.*/\1/p" /etc/group`))

sudo mkdir -p /gpio_mnt/"$name"
sudo chmod 777 -R /gpio_mnt/

sudo mkdir -p /gpio_mnt/"$name"/sys/devices/platform/soc/3f200000.gpio
sudo mkdir -p /gpio_mnt/"$name"/sys/class/gpio
sudo chown "$MYUID"."$MYGID" -R /gpio_mnt/"$name"/sys/

lxc exec "$name" -- mkdir -p /gpio_mnt/sys/class/gpio
lxc exec "$name" -- mkdir -p /gpio_mnt/sys/devices/platform/soc/3f200000.gpio

lxc config device add "$name" gpio disk source=/gpio_mnt/"$name"/sys/class/gpio path=/gpio_mnt/sys/class/gpio
lxc config device add "$name" devices disk source=/gpio_mnt/"$name"/sys/devices/platform/soc/3f200000.gpio path=/gpio_mnt/sys/devices/platform/soc/3f200000.gpio

cd /home/ubuntu/test_gpio_mirroring/
sudo node node-folder-mirroring.js /sys/devices/platform/soc/3f200000.gpio /gpio_mnt/"$name"/sys/devices/platform/soc/3f200000.gpio -o uid=$MYUID -o gid=$MYGID -o allow_other &> log_devices_"$name" &
echo $! > log_devices_pid_"$name"
sudo node node-folder-mirroring.js /sys/class/gpio /gpio_mnt/"$name"/sys/class/gpio -o uid=$MYUID -o gid=$MYGID -o allow_other &> log_gpio_"$name" &
echo $! > log_gpio_pid_"$name"
