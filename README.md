# apercel

Open-source GPU support for the Orange Pi 4 Pro (Allwinner A733, Imagination
BXM-4-64, BVNC 36.56.104.183) on Gentoo aarch64.

The name comes from Latin *aperio* ("to open") plus *celer* ("fast"): an
open driver with the clock raised.

What this provides:

- An open-source kernel DRM driver ("apercel") built from the Mesa PowerVR
  kernel driver. No vendor `pvrsrvkm` binary module; the vendor graphics stack
  is not required on the system.
- A Mesa userspace stack covering Vulkan (the `imagination` Vulkan driver)
  with zink for OpenGL, patched and maintained in this repository
  (`mesa/apercel-mesa.patch` against vanilla mesa-26.1.8).
- Frequency/thermal handling for the GPU: the driver brings the GPU to its
  maximum documented clock (1.008 GHz from the device tree OPP table) on
  every power-up and throttles to 600 MHz at high temperature.
- Verification and installation tooling.

Current results on this hardware: GPU settles at 1008 MHz (previously the
bootloader left it at 840 MHz and nothing ever raised it), the desktop
benchmark reaches ~96 fps (was ~83 fps on 840 MHz and ~15 fps with the
software renderer stack this project replaced), and Mindustry runs a stable
43 fps in a live game.

## Repository layout

    driver/               kernel driver, out-of-tree kbuild, module "apercel"
      src/                sources (upstream files keep their SPDX headers)
      src/include/        support headers (pwrseq consumer, drm_gpuvm, drm_exec, uapi)
      Makefile            out-of-tree build, GPL v2
      README-license.txt  license statement
    mesa/                 userspace component
      LICENSE             MIT
      manifest.txt        per-file notes on the changes
      apercel-mesa.patch  unified diff: vanilla mesa-26.1.8 -> apercel tree
      apercel-mesa.patch.sha256
      README.txt
    tools/
      verify-after-reboot.sh   full post-boot check (module, binding, clock,
                               governor, thermal zone, EGL renderer)
      gpu-status.sh            short live status (clock, temperature, renderer)
    conf/99-apercel.conf  modprobe.d configuration to install
    install.sh            install everything and ask to reboot
    uninstall.sh          restore the previous state from backup/

`backup/` is created locally by `install.sh` and is not part of the
repository.

## Kernel driver build

Prerequisites: a configured kernel tree for this platform (`orange-pi-6.6-sun60iw2`
bsp) with an out-of-tree build directory (`kernelbuild/` below, produced by
`make O=kernelbuild` from the kernel source), plus the three helper modules
built from the same tree:

    cd kernelbuild
    make M={work/opi-kernel/drivers/gpu/drm/scheduler} modules   # gpu-sched
    make M={work/opi-kernel/drivers/gpu/drm} modules             # drm_shmem_helper, drm_exec
    sudo cp */?.png /lib/modules/$(uname -r)/extra/ 2>/dev/null
    sudo depmod -a

Then build apercel:

    make -C kernelbuild M=$(pwd)/driver modules -j6

The Makefile resolves the `drm_sched_*`/`drm_gem_shmem_*`/`drm_exec_*`
symbols via `KBUILD_EXTRA_SYMBOLS` pointing into the kernel tree
(`work/opi-kernel/drivers/gpu/drm/Module.symvers`) and self-locates the
repository directory.

Then install:

    sudo cp driver/apercel.ko /lib/modules/$(uname -r)/extra/
    sudo depmod -a

## Firmware

The module loads `/lib/firmware/apercel/rogue_<BVNC>_v1.fw`. For this GPU
(BVNC 36.56.104.183) the file comes from the Allwinner BSP ("rogue
36.56.104.183"); a copy is expected at:

    /lib/firmware/apercel/rogue_36.56.104.183_v1.fw

Upstream linux-firmware currently ships the BVNC 36.52.104.182 image; when
a matching binary becomes available it covers the same family. The firmware
binary itself is not redistributed in this repository.

## Mesa userspace build

From a clean vanilla mesa-26.1.8 source tree:

    cd mesa-26.1.8
    git checkout 26.1.8 || tar -xf mesa-26.1.8.tar.xz
    patch -p1 -u < ../apercel/mesa/apercel-mesa.patch
    meson setup b-2618 --prefix=/usr/local \
      -Dbuildtype=release \
      -Dvulkan-drivers=imagination \
      -Dgallium-drivers=zink \
      -Degl=enabled -Dgbm=enabled -Dopengl=true \
      -Dgles1=disabled -Dgles2=enabled \
      -Dplatforms=x11,wayland -Dglx=dri -Dxlib-lease=disabled \
      -Dllvm=disabled \
      -Dmesa-clc=system -Dshader-cache=enabled -Dbuild-tests=false
    ninja -C b-2618
    sudo ninja -C b-2618 install
    sudo ldconfig

The build is warning-free (0 warnings for the `imagination` directory).
Installed into `/usr/local/lib64` (EGL, GLX, GBM, dri, gbm,
`libvulkan_powervr_mesa`) plus
`/usr/local/share/vulkan/icd.d/powervr_mesa_icd.aarch64.json`.

## What the GPU governor does (driver/src/pvr_power.c)

  - On every power-up the PLL (`clk_parent`, pll-gpu) is set to 1.008 GHz,
    the maximum rate listed in the `gpu-opp-table` in the device tree.
    Previously the bootloader's 840 MHz was never reprogrammed.
  - A delayed work runs every 500 ms and reads `gpu_thermal_zone`.
  - At 85 °C or hotter the clock is clamped to 600 MHz; at 75 °C or cooler
    it is raised back to 1.008 GHz (hysteresis stops boundary oscillation).
  - GPU can never be slower than 600 MHz while throttled.

## The CPU governor fix

Screen-update stalls were traced to the schedutil CPU governor, which
hopped between ~400 MHz and the max rates while the compositor ran. Both
CPU clusters are switched to the `performance` governor at boot by
`/etc/local.d/gpu-cpu-perf.start` (OpenRC `local` service):

    #!/bin/bash
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        echo performance > "$policy/scaling_governor" 2>/dev/null
    done

Revert with `echo schedutil > .../scaling_governor` and
`rc-update del local` if you want battery-oriented behavior instead.

## How to install / roll back

    ./install.sh           # interactive, asks to reboot at the end
    ./install.sh --reboot  # install and reboot without asking

Both scripts prefer `doas` (as configured on the reference system) and
fall back to `sudo`. `uninstall.sh` restores the previous module from
`backup/*.ko`, restores the previous modprobe.d configuration, and regenerates
the module dependency database.

After a reboot, verify with:

    ./tools/verify-after-reboot.sh
    ./tools/gpu-status.sh

## Licensing

  kernel driver : GPL v2 (component level; upstream per-file headers are
                  "GPL-2.0 OR MIT" — compatible with this choice)
  Mesa changes  : MIT (mesa/LICENSE; upstream files carry their own MIT/X11)
  install scripts/tools: GPL-2.0 (see LICENSE at the repository root)

The Imagination and Linaro copyright notices inside the driver sources are
retained untouched.

## Acknowledgments

This project builds on:

- the open-source PowerVR kernel driver maintained in Mesa
  (Imagination Technologies Ltd., Linaro Ltd.);
- Mesa (anything.org) — the Vulkan driver and zink pipeline;
- the Orange Pi 4 Pro BSP kernel (orange-pi-6.6-sun60iw2) for SoC integration;
- linux-firmware for the open firmware image build.
