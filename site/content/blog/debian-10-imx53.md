+++
title = "Installing Debian 10 on the i.MX53 devboard"
date = "2024-05-19"
description = "An in-depth guide for embedded-curious people."
draft = false
tags = [
    "linux",
    "debian",
    "embedded",
]
+++

Last week, one of my friends told me that we have a ton of
[i.MX53 Quick Start](https://www.nxp.com/design/design-center/development-boards-and-designs/i-mx-evaluation-and-development-boards/i-mx53-quick-start-board:IMX53QSB)
boards collecting dust in a storage room at our uni.

![One of the boxes we have at our department.](/images/imx53-box.jpg)
![The i.MX53 board.](/images/imx53-board.jpg)

I was thinking of maybe doing an Embedded Linux workshop of some kind with the board,
and also use it as an opportunity to learn about the Linux boot process on embedded
devices and the process of generating a Debian installation from scratch.


This guide walks through the process of installing Debian 10 on the board, and is
a modified version of the
 [InstallingDebianOn](https://wiki.debian.org/InstallingDebianOn/Freescale/i.MX53%20Quick%20Start%20board/debootstrap)
guide from the Debian wiki. I tried to add in-depth explanations (which I hope are helpful to someone out there).

### Partitioning the SD card
First we'll set up an MBR partition table (didn't test this on GPT yet, but it [should be possible](https://www.barebox.org/doc/latest/boards/imx.html#using-gpt-on-i-mx)) on a 4GiB SD card.
Also, we'll make sure to leave 2 MiB of free space **before** the first partition; `fdisk` does this by default.

We need **two** partitions: one for the boot files, and another one for the root filesystem (rootfs).

I like using an interactive `fdisk` session to partition the disk (you can find a detailed tutorial [here](https://tldp.org/HOWTO/Partition/fdisk_partitioning.html)):

**Note**: you'll have to change `/dev/sdd` to the appropriate device on your machine

TODO: maybe rewrite this with `parted` as a one-liner
```
$ sudo fdisk /dev/sdd  
  
Welcome to fdisk (util-linux 2.40).  
Changes will remain in memory only, until you decide to write them.  
Be careful before using the write command.  
  
  
Command (m for help): o  
Created a new DOS (MBR) disklabel with disk identifier 0x8d7f6430.  
  
Command (m for help): n  
Partition type  
  p   primary (0 primary, 0 extended, 4 free)  
  e   extended (container for logical partitions)  
Select (default p): p  
Partition number (1-4, default 1): 1  
First sector (2048-7716863, default 2048): 2048  
Last sector, +/-sectors or +/-size{K,M,G,T,P} (2048-7716863, default 7716863): +512M  
  
Created a new partition 1 of type 'Linux' and of size 512 MiB.  
  
Command (m for help): n  
Partition type  
  p   primary (1 primary, 0 extended, 3 free)  
  e   extended (container for logical partitions)  
Select (default p): p  
Partition number (2-4, default 2): 2  
First sector (1050624-7716863, default 1050624):    
Last sector, +/-sectors or +/-size{K,M,G,T,P} (1050624-7716863, default 7716863):    
  
Created a new partition 2 of type 'Linux' and of size 3.2 GiB.  
  
Command (m for help): w  
The partition table has been altered.  
Calling ioctl() to re-read partition table.  
Syncing disks.
```

This gives us the following:

```
$ sudo fdisk -l /dev/sdd  
Disk /dev/sdd: 3.68 GiB, 3951034368 bytes, 7716864 sectors  
Disk model: STORAGE DEVICE     
Units: sectors of 1 * 512 = 512 bytes  
Sector size (logical/physical): 512 bytes / 512 bytes  
I/O size (minimum/optimal): 512 bytes / 512 bytes  
Disklabel type: dos  
Disk identifier: 0x8d7f6430  
  
Device     Boot   Start     End Sectors  Size Id Type  
/dev/sdd1          2048 1050623 1048576  512M 83 Linux  
/dev/sdd2       1050624 7716863 6666240  3.2G 83 Linux
```

Notice that the units are given in terms of 512-byte sectors; our first partition, `dev/sdd1`, starts at an offset of 2048 * 512 = 1048576 (1 MiB).

We'll format the boot partition as `ext2` and the other one as `ext4`:
```
$ sudo mkfs.ext2 -L "MX53_BOOT" /dev/sdd1
$ sudo mkfs.ext4 -T small -L "MX53_ROOT" /dev/sdd2
```

(`-T small` is optional here).

### Installing u-boot

Now here comes something really cool: [u-boot](https://en.wikipedia.org/wiki/Das_U-Boot), aka the **U**niversal **B**oot **L**oader. Almost every embedded platform out there uses this as a bootloader. The i.MX53 is no exception.

Every platform has a different process of installation for u-boot (I don't understand it very well myself), but for the i.MX53 apparently you just need to place it somewhere between the beginning of the disk and the first partition (which is honestly pretty cool). We just have to make sure not to overwrite the MBR table in the process (which for our use case won't exceed 1 KiB).

In order to achieve this, we will fetch the u-boot image for the iMX53 board from the Debian repos, and write it to an offset of 2 * 512 bytes = 1 KiB into the SD card, before the first partition starts:

```bash
$ wget "http://ftp.us.debian.org/debian/dists/buster/main/installer-armhf/current/images/u-boot/MX53LOCO/u-boot.imx.gz"
$ zcat u-boot.imx.gz > u-boot.imx
$ sudo dd if=u-boot.imx of=/dev/sdd seek=2 bs=512
```

Let's quickly confirm we didn't mess up the MBR table by doing this:

```bash
$ sudo sfdisk --verify /dev/sdd
/dev/sdd:  
No errors detected.
```

The bootloader uses the serial (RS-232) port on the board, so in order to view the output and use the console you'll probably need an RS-232 to USB adapter. You can use `minicom` in order to view the serial output:

```bash
$ sudo minicom -D /dev/ttyUSB0
```

To save you from future headaches, you can press `Ctrl+A -> O` to open the configuration menu, then go into the `Serial port setup` window and press `F` in order to disable Hardware Flow Control and allow you to type characters into the console
(you need to disable it because your RS-232 adapter most likely doesn't support it, which makes you unable to
type into the console).

If all goes well, when you insert the SD card into the i.MX53 and reset the board, you should see something like the following on the serial port:

```
U-Boot 2019.01+dfsg-7 (May 14 2019 - 02:07:44 +0000)  
  
CPU:   Freescale i.MX53 rev2.1 at 800 MHz  
Reset cause: POR  
Board: MX53 LOCO  
I2C:   ready  
DRAM:  1 GiB  
MMC:   FSL_SDHC: 0, FSL_SDHC: 1  
Loading Environment from MMC... *** Warning - bad CRC, using default environment  
  
In:    serial  
Out:   serial  
Err:   serial                                                                   
Net:   FEC                                                                      
Hit any key to stop autoboot:  0                                                
switch to partitions #0, OK                                                     
mmc0 is current device                                                          
** File not found boot.scr **                                                   
** File not found zImage **
```

### Generating the rootfs

**Important**: this section assumes you're using a Debian-based system. This should probably work on other distros, but it is untested. Experiment at your own risk. :-)

We will need `debootstrap` -- one of the coolest tools ever in the embedded Linux world -- which will generate a Debian rootfs that we can use on the board. We will also need to use QEMU in order to emulate an `arm` host when building the rootfs:

```bash
$ sudo apt update
$ sudo apt install debootstrap qemu-user-static
```

Now let's mount the partitions we created earlier:

```bash
$ sudo mkdir -pv /mnt/debinst
$ sudo mount LABEL="MX53_ROOT" /mnt/debinst
$ sudo mkdir -pv /mnt/debinst/boot
$ sudo mount LABEL="MX53_BOOT" /mnt/debinst/boot
```

Then we can finally run the first stage of `debootstrap`:

```bash
$ sudo debootstrap --arch armhf --foreign buster /mnt/debinst http://ftp.us.debian.org/debian
```

After this is finished, we will `chroot` into the recently created rootfs to continue with the installation:

```bash
$ sudo cp -pv /usr/bin/qemu-arm-static /mnt/debinst/usr/bin/
$ sudo chroot /mnt/debinst qemu-arm-static /bin/bash
```

Notice how we copy the `qemu-arm-static` binary into the rootfs, and then immediately start bash inside a virtualized `arm` environment as we chroot (i.e., from now on we're running everything in a QEMU `arm` platform).

You should now be in a chroot shell withing the `debootstrap`-generated rootfs. We will then clean up our environment variables (which were inherited from the host -- we don't want them):

```bash
$ env -i bash     # Clear all env vars except for the indispensable ones
$ export TERM=xterm-color
$ export HOME=/root
$ export LANG=C.UTF-8
```

Next, we can run the second (and final) stage of `debootstrap`. This is only necessary when creating a Debian rootfs for a foreign architecture (hence the `--foreign` flag earlier) -- the first stage will download and unpack all the `.deb` files, while the second one runs all the package configuration scripts (which can only be done on the target architecture). When targeting the same arch as the host the two stages are merged.

Run the following and go grab some coffee, because this might take a seriously long time depending on how beefy your CPU is. :-) Also make sure to use an SD card with decent read/write speeds!

```bash
$ /debootstrap/debootstrap --second-stage
```

If you got this far, congratulations! 🎉 Hopefully the wait wasn't too long. Now it's time to do some basic housekeeping and configuration of the rootfs.

#### Installing a terminal editor
```bash
$ apt install ncurses-term
$ apt install vim nano    # choose your favorite editor
```

#### Setting up `/etc/fstab`
Here we will configure the automounting of partitions. The SD card for the i.MX53 should be in `/dev/mmcblk0`:

```/etc/fstab
/dev/mmcblk0p2    /        auto    errors=remount-ro    0 1
/dev/mmcblk0p1    /boot    auto    ro,nosuid,nodev      0 1 
```

#### Adjusting the timezone
```bash
$ dpkg-reconfigure tzdata
```

#### Network configuration
If we want ethernet to work "out of the box", we need to configure the `eth0` interface to use DHCP:
```
$ nano /etc/network/interfaces
```

```/etc/networks/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

auto eth0
iface eth0 inet dhcp
```

And don't forget to set the hostname (you can set this to anything you'd like):
```bash
$ echo imx53 > /etc/hostname
```

Also install `ssh` for later:

```bash
$ apt install ssh
```

#### Console configuration
This will avoid headaches later on:

```bash
$ apt install console-setup
```

#### Setting up accounts
Let's set up the password for the root account, and create a privileged user called `lkcamp`:

```bash
$ passwd
$ useradd -m -G users,audio,adm,sudo lkcamp
$ passwd lkcamp
```

### Installing the kernel and configuring u-boot

**Important**: make sure to follow these steps carefully or the board won't boot into Linux. :-)

Install the following packages:

```bash
$ apt install linux-image-armmp u-boot-imx init
```

The `linux-image-armmp` is of particular importance to us and will, among other things, place the kernel images in `/boot` and run a script to generate an `initramfs`, which will leave you with something like this:

```/boot
$ ls -lah /boot
total 26M
drwxr-xr-x.  3 root root 4.0K May 15 23:55 .
drwxr-xr-x. 18 root root 1.0K May 15 23:52 ..
-rw-r--r--.  1 root root 3.0M Jun 30  2022 System.map-4.19.0-21-armmp
-rw-r--r--.  1 root root 205K Jun 30  2022 config-4.19.0-21-armmp
-rw-r--r--.  1 root root  19M May 15 23:55 initrd.img-4.19.0-21-armmp
drwx------.  2 root root  16K May 15 23:31 lost+found
-rw-r--r--.  1 root root 4.0M Jun 30  2022 vmlinuz-4.19.0-21-armmp
```

Now we have to configure `flash-kernel`, which is responsible for setting up u-boot to load the kernel we just generated. Start by installing it:

```bash
$ apt install flash-kernel
```

We have to specify the string that defines our machine:

```bash
$ echo "Freescale i.MX53 Quick Start Board" > /etc/flash-kernel/machine
```

Now, all the supported `flash-kernel` targets are defined in `/usr/share/flash-kernel/db/all.db`. You might notice that there is already an entry for the `Freescale i.MX53 Quick Start Board`, but it is incomplete (for some reason) and we need to manually patch some things. First of all, find the entry for the board and change it to this:

```/usr/share/flash-kernel/db/all.db
Machine: Freescale i.MX53 Quick Start Board
Machine: Freescale MX53 LOCO Board
Kernel-Flavors: armmp mx5
DTB-Id: imx53-qsb.dtb
Boot-DTB-Path: /boot/board.dtb
U-Boot-Kernel-Address: 0x70008000
U-Boot-Initrd-Address: 0x72000000
Boot-Kernel-Path: /boot/uImage
Boot-Initrd-Path: /boot/uInitrd
Required-Packages: u-boot-tools
Bootloader-Sets-Incorrect-Root: no
U-Boot-Script-Name: bootscr.mx5-custom
Boot-Script-Path: /boot/boot.scr
```

We will need to write the custom script specified in `U-Boot-Script-Name`. In order to do that, we will start from a copy of the provided generic u-boot script:

```bash
$ cp -pv /etc/flash-kernel/bootscript/bootscr.uboot-generic /etc/flash-kernel/bootscript/bootscr.mx5-custom
```

Then we will edit `/etc/flash-kernel/bootscript/bootscr.mx5-custom` and add the following environment variables to the **beginning** of the script:

```bootscr.mx5-custom
setenv distro_bootpart ${mmcpart}
setenv boot_targets mmc
setenv fdtfile ${fdt_file}
setenv bootpart ${mmcpart}
setenv devnum ${mmcdev}
setenv console ttymxc0
setenv devtype mmc
setenv fdt_addr_r ${fdt_addr}
setenv ramdisk_addr_r ${loadaddr}
setenv kernel_addr_r 0x70008000
setenv prefix /
```

Finally, we need to set a kernel command so that Linux can mount our rootfs during boot. Add the following to `/etc/default/flash-kernel`:

```/etc/default/flash-kernel
LINUX_KERNEL_CMDLINE="root=/dev/mmcblk0p2 ro rootfstype=ext4 rootwait fixrtc"
```

Notice how we told it that our root partition is on `/dev/mmcblk0p2` and that it is an `ext4` filesystem. :-)

That's it! Now we only need to run `flash-kernel`:

```bash
$ flash-kernel
```

After it does its thing, you should have something like the following in your `/boot` folder:

```
$ ls -lah /boot
total 72M
drwxr-xr-x.  4 root root 4.0K May 16 00:29 .
drwxr-xr-x. 18 root root 1.0K May 16 00:09 ..
-rw-r--r--.  1 root root 3.0M Jun 30  2022 System.map-4.19.0-21-armmp
-rw-r--r--.  1 root root  21K May 16 00:29 board.dtb
-rw-r--r--.  1 root root 3.2K May 16 00:29 boot.scr
-rw-r--r--.  1 root root 205K Jun 30  2022 config-4.19.0-21-armmp
lrwxrwxrwx.  1 root root   36 May 16 00:29 dtb -> dtbs/4.19.0-21-armmp/./imx53-qsb.dtb
lrwxrwxrwx.  1 root root   36 May 16 00:29 dtb-4.19.0-21-armmp -> dtbs/4.19.0-21-armmp/./imx53-qsb.dtb
lrwxrwxrwx.  1 root root   36 May 16 00:08 dtb.bak -> dtbs/4.19.0-21-armmp/./imx53-qsb.dtb
drwxr-xr-x.  3 root root 4.0K May 16 00:08 dtbs
-rw-r--r--.  1 root root  19M May 15 23:55 initrd.img-4.19.0-21-armmp
drwx------.  2 root root  16K May 15 23:31 lost+found
-rw-r--r--.  1 root root 4.0M May 16 00:29 uImage
-rw-r--r--.  1 root root 4.1M May 16 00:08 uImage.bak
-rw-r--r--.  1 root root  19M May 16 00:29 uInitrd
-rw-r--r--.  1 root root  19M May 16 00:09 uInitrd.bak
-rw-r--r--.  1 root root 4.0M Jun 30  2022 vmlinuz-4.19.0-21-armmp
```

Now cross your fingers, insert the SD card on the board and press that reset button. If everything goes well, you should see Linux booting. Congrats! 🎉

## Next steps

- Figure out how to boot Debian 12 on this thing with the 6.1 kernel
- Investigate U-Boot in more depth; maybe generate a rootfs with Buildroot,
compile a custom kernel + initramfs and try to boot it by hand from the U-Boot console?
