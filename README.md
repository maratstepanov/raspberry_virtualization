# raspberry_virtualization
An approach to create multiple virtual Raspberry Pis on a single physical one.

This is a first version of Raspberry Pi virtualization: full pass-through of GPIO folder. It has been tested on a Raspberry Pi 2 with Ubuntu 16.04 LTS downloaded from https://wiki.ubuntu.com/ARM/RaspberryPi.

###Upgrade the system
```
sudo apt update
sudo apt upgrade
sudo reboot
```

###Install dependencies
```
sudo apt install fuse libfuse-dev pkg-config python2.7
curl -sL https://deb.nodesource.com/setup_7.x | sudo -E bash -
sudo apt install nodejs
```
###Create a folder for testing and setup the Node.js dependencies
```
mkdir /home/ubuntu/test_gpio_mirroring
cd /home/ubuntu/test_gpio_mirroring
npm config set python `which python2.7`
npm install fuse-bindings fs mknod path minimist
npm install https://github.com/PlayNetwork/node-statvfs/tarball/v3.0.0
wget https://raw.githubusercontent.com/flongo82/node-folder-mirroring/master/node-folder-mirroring.js
```

###Configure the system to allow gpio folder to be accessible from ubuntu user
```
sudo addgroup gpio
sudo usermod -a -G gpio ubuntu
cat<<EOF | sudo tee /etc/udev/rules.d/99-gpio.rules
SUBSYSTEM=="input", GROUP="input", MODE="0660"
SUBSYSTEM=="i2c-dev", GROUP="i2c", MODE="0660"
SUBSYSTEM=="spidev", GROUP="spi", MODE="0660"
SUBSYSTEM=="bcm2835-gpiomem", GROUP="gpio", MODE="0660"

SUBSYSTEM=="gpio*", PROGRAM="/bin/sh -c '\\
chown -R root:gpio /sys/class/gpio && chmod -R 770 /sys/class/gpio;\\
chown -R root:gpio /sys/devices/virtual/gpio && chmod -R 770 /sys/devices/virtual/gpio;\\
chown -R root:gpio /sys\$devpath && chmod -R 770 /sys\$devpath\\
'"

KERNEL=="ttyAMA[01]", PROGRAM="/bin/sh -c '\\
ALIASES=/proc/device-tree/aliases; \\
if cmp -s \$ALIASES/uart0 \$ALIASES/serial0; then \\
echo 0;\\
elif cmp -s \$ALIASES/uart0 \$ALIASES/serial1; then \\
echo 1; \\
else \\
exit 1; \\
fi\\
'", SYMLINK+="serial%c"

KERNEL=="ttyS0", PROGRAM="/bin/sh -c '\\
ALIASES=/proc/device-tree/aliases; \\
if cmp -s \$ALIASES/uart1 \$ALIASES/serial0; then \\
echo 0; \\
elif cmp -s \$ALIASES/uart1 \$ALIASES/serial1; then \\
echo 1; \\
else \\
exit 1; \\
fi \\
'", SYMLINK+="serial%c"
EOF
sudo reboot
```

###Install and configure LXD
```
sudo add-apt-repository ppa:ubuntu-lxc/lxd-stable
sudo apt-get update
sudo apt-get install lxd criu cgmanager
sudo apt-get install zfsutils-linux
sudo lxd init
lxd --version
```
###Launch two virtual Raspberry Pis
```
lxc launch ubuntu:16.04 test1
lxc launch ubuntu:16.04 test2

UID_TEST1=`sudo ls -l /var/lib/lxd/containers/test1/rootfs/ | grep root | awk '{}{print $3}{}'`
UID_TEST2=`sudo ls -l /var/lib/lxd/containers/test2/rootfs/ | grep root | awk '{}{print $3}{}'`

lxc exec test1 -- addgroup gpio
lxc exec test1 -- usermod -a -G gpio ubuntu
GID_TEST1=$(($UID_TEST1 + `lxc exec test1 -- sed -nr "s/^gpio:x:([0-9]+):.*/\1/p" /etc/group`))
lxc exec test2 -- addgroup gpio
lxc exec test2 -- usermod -a -G gpio ubuntu
GID_TEST2=$(($UID_TEST2 + `lxc exec test2 -- sed -nr "s/^gpio:x:([0-9]+):.*/\1/p" /etc/group`))

sudo mkdir -p /gpio_mnt/test1
sudo mkdir -p /gpio_mnt/test2
sudo chmod 777 -R /gpio_mnt/

sudo mkdir -p /gpio_mnt/test1/sys/devices/platform/soc/3f200000.gpio
sudo mkdir -p /gpio_mnt/test1/sys/class/gpio
sudo chown "$UID_TEST1"."$GID_TEST1" -R /gpio_mnt/test1/sys/
sudo mkdir -p /gpio_mnt/test2/sys/devices/platform/soc/3f200000.gpio
sudo mkdir -p /gpio_mnt/test2/sys/class/gpio
sudo chown "$UID_TEST2"."$GID_TEST2" -R /gpio_mnt/test2/sys/

lxc exec test1 -- mkdir -p /gpio_mnt/sys/class/gpio
lxc exec test1 -- mkdir -p /gpio_mnt/sys/devices/platform/soc/3f200000.gpio
lxc exec test2 -- mkdir -p /gpio_mnt/sys/class/gpio
lxc exec test2 -- mkdir -p /gpio_mnt/sys/devices/platform/soc/3f200000.gpio

lxc config device add test1 gpio disk source=/gpio_mnt/test1/sys/class/gpio path=/gpio_mnt/sys/class/gpio
lxc config device add test1 devices disk source=/gpio_mnt/test1/sys/devices/platform/soc/3f200000.gpio path=/gpio_mnt/sys/devices/platform/soc/3f200000.gpio
lxc config device add test2 gpio disk source=/gpio_mnt/test2/sys/class/gpio path=/gpio_mnt/sys/class/gpio
lxc config device add test2 devices disk source=/gpio_mnt/test2/sys/devices/platform/soc/3f200000.gpio path=/gpio_mnt/sys/devices/platform/soc/3f200000.gpio

cd test_gpio_mirroring/
sudo node node-folder-mirroring.js /sys/devices/platform/soc/3f200000.gpio /gpio_mnt/test1/sys/devices/platform/soc/3f200000.gpio -o uid=$UID_TEST1 -o gid=$GID_TEST1 -o allow_other &> log_devices_test1 &
sudo node node-folder-mirroring.js /sys/class/gpio /gpio_mnt/test1/sys/class/gpio -o uid=$UID_TEST1 -o gid=$GID_TEST1 -o allow_other &> log_gpio_test1 &
sudo node node-folder-mirroring.js /sys/devices/platform/soc/3f200000.gpio /gpio_mnt/test2/sys/devices/platform/soc/3f200000.gpio -o uid=$UID_TEST2 -o gid=$GID_TEST2 -o allow_other &> log_devices_test2 &
sudo node node-folder-mirroring.js /sys/class/gpio /gpio_mnt/test2/sys/class/gpio -o uid=$UID_TEST2 -o gid=$GID_TEST2 -o allow_other &> log_gpio_test2 &
```