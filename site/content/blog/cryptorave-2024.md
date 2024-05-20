+++
title = "Attending CryptoRave 2024"
date = "2024-05-15"
description = "My experience volunteering and giving a talk at CryptoRave 2024."
draft = false
tags = [
    "conference",
    "linux",
    "fpga",
]
+++

## The conference

Last weekend I attended an annual conference called [CryptoRave](https://2024.cryptorave.org/)
in São Paulo, Brazil. The event has a strong focus on security/privacy, cryptography, cyberactivism and
software freedom, being part of a global movement that started with Edward Snowden's leak of
classified NSA documents in 2013.

There's another fun twist: the conference is jam-packed with workshops and talks happening
during the entire 24-hour duration of the event. There was a pretty wild variety of topics, ranging
from things like IoT hacking and computer systems hardening for digital privacy, to the ethics
of AI, transfeminist digital activism and the use of free software in national elections.

## My experience as a volunteer

Even though it was my first year attending CryptoRave, a bunch of my friends from
[LKCAMP](https://lkcamp.dev/) (my university's FOSS research student group, which I'm a part of)
were also volunteering, so I decided to sign up as well.

I worked at the event's Linux Install Fest,
where we were helping people install Linux on their computers, freeing them from the
evil influence of Windows. :-) Surprisingly, this Install Fest wasn't as eventful as the one that
LKCAMP organized earlier this year at our university -- which had many interesting ~~cryptids~~ machines,
such as an Acer laptop with buggy PCIe power management firmware that completely broke NVMe on
Linux, and a 32-bit laptop with broken Wi-Fi card drivers (on top of being incredibly slow).
Nevertheless, it was still very fun and I got to meet many interesting people.

The most interesting machine I got my hands on was a Samsung Chromebook with
a Samsung Exynos (32-bit ARM) CPU. Installing Debian on it was surprisingly easy, and I kind of
fell in love with the thing -- it is surprisingly neat (if a little small), and the build quality
is very good. I was kind of sad to see it go, but the owner was super friendly and an overall chill
guy, so it is in good hands now -- and most importantly, running a free operating system. :-)

I also helped run one of the conference rooms late at night; all rooms were named after important figures
in the context of CS/Cryptography/Free Software, and I worked at the one named Ian Murdock (the founder
of the Debian project -- what an honor, as well as a funny coincidence).
One of the talks there really caught my attention; it was titled
"The Cultural Logic of Computing: How the Ideology of Computationalism Strengthens the Status Quo",
and the speaker went over some very interesting philosophical/sociological considerations about how
certain aspects of virtual spaces, even though inherent to the digital medium, start seeping into the
real world and having an impact
on the workings of society due to the pervasiveness of computing in our
contemporary lifestyles. I really wish I could have taken notes during this one. :')

## My experience as a speaker

This year I also gave a talk (slides in Portuguese
[here](https://docs.google.com/presentation/d/12ft6MD5B0QVANmR0b4MrmGkHxeF8I2Ri5ars6l8ha8k/edit#slide=id.g202b817d59f_6_18))
with some friends from LKCAMP; you can find their socials here:

- Julio Avelar ([github](https://github.com/JN513)), our local hardware wizard, who also runs a
really cool blog at https://bzoide.dev/, in Portuguese-only for now :-)
- Carlos Barbosa ([github](https://github.com/carlosecb)), our local free software expert

We talked about Open Hardware (as well as Free Software), going over its history,
the different licensing models and the current ecosystem for developing Open Hardware.
I took it as a personal challenge to present a demo of Linux running on an open-source RISC-V processor,
using an open source toolchain from end-to-end. Here's a picture of our battle station at the
Computer Systems Laboratory (LSC), in Unicamp:

![The battle station used in our demo.](/images/cryptorave-2024-battlestation.jpg)

The little board on the right is an Arty S7 FPGA board from Digilent that we used for the demo.
My initial plan was to use a Lattice board (Colorlight i9) in order to be able to use an open-source
bitstream generator
([prjtrellis](https://github.com/YosysHQ/prjtrellis)) to achieve a fully end-to-end open source toolchain,
but I ran into issues getting the Linux + rootfs images to fit in the board's 8MB of SDRAM.
The (mostly) open-source stack we used goes as follows:

- We ran the [VexRiscv-SMP CPU](https://github.com/SpinalHDL/VexRiscv), a 32-bit RISC-V processor
with 2 cores
- On top of this, we used [Litex](https://github.com/enjoy-digital/litex) to generate a SoC design
to run on the FPGA alongside VexRiscv
- The FPGA toolchain we used consisted of:
  - [Yosys](https://github.com/YosysHQ/yosys) for synthesis
  - [nextpnr](https://github.com/YosysHQ/nextpnr) for placement and routing
  - Vivado for bitstream generation -- sadly there are no open-source bitstream generation
  tools for Xilinx boards yet :-(
  - [OpenFPGALoader](https://github.com/trabucayre/openFPGALoader) for loading the bitstream
  to the Arty S7 board
- [Buildroot](https://github.com/buildroot/buildroot) for generating a minimal rootfs and a
suitable Linux kernel image for the board

Even though this was my first time doing anything of this scale with FPGAs, we somehow succeeded in
getting Linux 6.1 running on the Arty S7, which was awesome. The presentation also went pretty
smoothly and there were lots of interesting questions from the audience, so I consider this a success.
I learned a lot from the experience. :-)
