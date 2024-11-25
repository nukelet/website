+++
title = "ARM64 QEMU setup for kernel development on Asahi Linux"
date = "2024-11-22"
description = "Running small, KVM-accelerated ARM64 virtual machines for kernel development on M1 hardware"
draft = false
tags = [
    "linux",
    "kernel",
]
+++

# TL;DR

For my fellow ADHD ~~goblins~~ people coming from a quick Google search:

```bash
$ wget http://cdimage.debian.org/cdimage/cloud/bookworm/daily/latest/debian-12-nocloud-arm64-daily.qcow2 -O debian-cloud.qcow2
```

```bash
$ qemu-system-aarch64 \
  -M virt -cpu max \
  -m 2G -smp 4 \
  -kernel $PATH_TO_KERNEL_IMAGE \
  -append "console=ttyAMA0 earlyconsole printk loglevel=8 root=/dev/vda1" \
  -device virtio-blk-pci,drive=hd \
  -drive if=none,file=./debian-cloud.qcow2,format=qcow2,id=hd \
  -nographic -enable-kvm
```

# Introduction

I recently got my hands on a Macbook Pro M1 Touchbar, which is
what I intend to use as my daily driver for the foreseeable future.
Owning an ARM64 machine has been kind of a dream of mine for a while
now, and I'm very pleased with the software support for the platform,
and the performance is on-par with my Ryzen 7 3700X desktop processor,
at least for kernel compilation (while using a fraction of the power).
Battery life is also great; there are still some rough edges in the
kernel support for M1, but I would like to contribute to the Asahi
kernel in the future as well.

I wanted to reproduce the lightweight VM setup from the
[LKCAMP wiki](https://docs.lkcamp.dev/intro_tutorials/boot/), which
allows you to quickly spin up small VMs with KVM acceleration for
kernel testing. The problem is we only tested it on x86_64 Linux
systems, and I wanted to test it on my ARM64 host.

Unfortunately one of the steps from that guide (generating a rootfs with
`debootstrap`) doesn't seem to work properly for ARM64, so I had to figure out
another way. Shout out to the [FLUSP](https://flusp.ime.usp.br/) folks
(the free software study group from the University of São Paulo) for
their excellent
[in-depth guide](https://flusp.ime.usp.br/kernel/qemu-libvirt-setup/)
covering much of the setup I'm presenting here.

# Dependencies

- `qemu`
    - Ubuntu: `qemu`
- `libguestfs`
    - Ubuntu: `libguestfs-tools`

# VM setup

We'll get a qcow2 Debian cloud image from here:
http://cdimage.debian.org/cdimage/cloud/bookworm/daily/latest

```bash
$ wget http://cdimage.debian.org/cdimage/cloud/bookworm/daily/latest/debian-12-nocloud-arm64-daily.qcow2 -O debian-cloud.qcow2
```

We can use `libguestfs` to inspect the contents of the qcow2 image (note:
you might need to run as sudo):

```bash
$ sudo virt-filesystems --long -h --all -a debian-cloud.qcow2
```

The output should look similar to this:

```
Name        Type        VFS   Label  MBR  Size  Parent
/dev/sda1   filesystem  ext4  -      -    1.8G  -
/dev/sda15  filesystem  vfat  -      -    127M  -
/dev/sda1   partition   -     -      -    1.9G  /dev/sda
/dev/sda15  partition   -     -      -    127M  /dev/sda
/dev/sda    device      -     -      -    2.0G  -
```

Note that the root partition here is located in `/dev/sda1`
(whereas `/dev/sda15` contains the EFI partition).
We can use another tool from `libguestfs` to peek into the
contents of each partition, e.g.:

```bash
$ sudo virt-ls -a debian-cloud.qcow2 -m /dev/sda1 /boot
```

```
System.map-6.1.0-27-arm64
config-6.1.0-27-arm64
efi
grub
initrd.img-6.1.0-27-arm64
vmlinuz-6.1.0-27-arm64
```

For a quick sanity check, we can extract the kernel/initrd
from the image's boot partition:


```bash
$ sudo virt-copy-out -a debian-cloud.qcow2 /boot .
```

And then try to boot using them:

```bash
$ qemu-system-aarch64 \
  -M virt -cpu max \
  -m 2G -smp 4 \
  -kernel ./boot/vmlinuz-* \
  -initrd ./boot/initrd* \
  -append "console=ttyAMA0 earlyconsole printk loglevel=8 root=/dev/vda1" \
  -device virtio-blk-pci,drive=hd \
  -drive if=none,file=./debian-cloud.qcow2,format=qcow2,id=hd \
  -nographic -enable-kvm
```

You should be able to login as `root` without the need for
a password. Note that we use `console=ttyAMA0` instead of
the usual `console=ttyS0` (on `qemu-system-x86_64`).

We can then boot from our own freshly compiled kernel,
passing the path to the image (inside `arch/arm64/boot/Image`
within the kernel source tree) with the `-kernel` flag (you
can probably drop the initrd as well).
- Tip: you can use the `virtconfig` target, which is a trimmed
version of arm64's `defconfig`, for somewhat faster
compilation times.

## TODO:

- Set up networking and SSH
- Test sharing a folder between host and guest
