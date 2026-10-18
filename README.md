# apercel

Open-source GPU support for the Imagination BXM-4-64 GPU (PowerVR Rogue
family, BVNC 36.56.104.183) built into the Allwinner A733 SoC. Written on
Gentoo aarch64; the instructions below cover Debian, Fedora, Arch, Void
and Gentoo alike.

The name comes from Latin *aperio* ("to open") plus *celer* ("fast"): an
open driver with the clock raised.

## Tested hardware

The stack is tested live only on the Orange Pi 4 Pro. The A733 SoC and the
BXM-4-64 GPU are used in many other boards (Orange Pi Zero 3W, Radxa Cubie
A7 series, and others); nothing in this repository is specific to the
Orange Pi 4 Pro — the driver binds by the `img,gpu` device tree compatible,
and everything else is stock — so it is expected to work on other A733
boards, but this is not proven yet.

**Testers are welcome: if you have another A733 board, please try it and
report your results.**

What this provides:

- An open-source kernel DRM driver ("apercel") built from the Mesa PowerVR
  kernel driver. No vendor `pvrsrvkm` binary module; the vendor graphics
  stack is not required on the system.
- A Mesa userspace stack covering Vulkan (the `imagination` Vulkan driver)
  with zink for OpenGL, maintained in this repository as a patch against
  vanilla mesa-26.1.8.
- Frequency/thermal handling for the GPU: the driver brings the GPU to its
  maximum documented clock (1.008 GHz from the device tree OPP table) on
  every power-up and throttles to 600 MHz at high temperature.
- Installation and verification tooling.

Current results on the Orange Pi 4 Pro: the GPU settles at 1008 MHz
(previously the bootloader left it at 840 MHz and nothing ever raised it),
the desktop benchmark reaches ~96 fps, and a stable 45–50 fps is achievable
in a live Mindustry game.

## What runs

Programs tested on the Orange Pi 4 Pro (the stack itself is distro-agnostic;
the reference install ran on Gentoo aarch64, sway compositor):

| Program                          | Status                    | Notes                                                |
|----------------------------------|---------------------------|------------------------------------------------------|
| sway (compositor)                | works                     | compositing on the GPU via zink                      |
| alacritty                        | works                     | terminal, smooth                                     |
| foot                             | works                     | terminal, smooth                                     |
| waybar                           | works                     | status bar                                           |
| Helium browser (Chromium-based)  | works                     | GPU accelerated                                      |
| Mindustry                        | works                     | 45–50 fps in a live game                             |
| Factorio Space Age               | runs                      | roughly 10–19 fps, playable-ish                      |
| Vesktop (Electron, Discord)      | does not start            | no workaround found yet                              |

Everything else that is not listed has not been tried.

## Repository layout

    driver/               kernel driver, out-of-tree kbuild, module "apercel"
      src/                sources (upstream files keep their SPDX headers)
      src/include/        support headers (pwrseq consumer, drm_gpuvm, drm_exec, uapi)
      Makefile            out-of-tree build; licensed GPLv2 (see LICENSE)
      README-license.txt  license statement
    mesa/                 userspace component
      LICENSE             MIT license (full text)
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

## Licensing

- Kernel driver (driver/): **GPLv2** — full text in the root [LICENSE](LICENSE).
  Upstream per-file headers are "GPL-2.0 OR MIT" (Imagination Technologies
  Ltd., Linaro Ltd.); the upstream copyright headers are retained untouched.
- Mesa changes (mesa/): **MIT** — full text in [mesa/LICENSE](mesa/LICENSE).
- Install scripts and tools (install.sh, uninstall.sh, tools/): GPL-2.0.

## Install

The instructions below are distro-agnostic and were tested on the
reference system: Gentoo aarch64 on the Orange Pi 4 Pro, kernel
6.6.98-sun60iw2 (the "orange-pi-6.6-sun60iw2" BSP tree with an
out-of-tree build directory `kernelbuild/` inside the kernel source root),
OpenRC init, and a sway compositor. On Debian, Fedora, Arch, Void or any
other distribution everything works the same — the only distro-specific
parts are the package manager commands (below), the boot-time persistence
of the CPU governor snippet, and whether `doas` or `sudo` is your root
helper. Adjust paths to your system where needed.

### 0. Build dependencies

Both components are built from source; you need a compiler toolchain,
meson/ninja and a few development libraries. Everything installs as
regular packages, nothing is distro-specific beyond the package names.
Run only the block for your distribution:

Debian / Ubuntu (names may vary slightly between releases):

    sudo apt install build-essential meson ninja-build python3 python3-mako \
        flex bison pkg-config zlib1g-dev libdrm-dev libglslang-dev \
        libclc-dev libvulkan-dev

Fedora:

    sudo dnf install -y gcc make meson ninja-build python3 python3-mako \
        flex bison pkgconf zlib-devel libdrm-devel glslang-devel \
        libclc-devel vulkan-headers

Arch / Artix:

    sudo pacman -S --needed base-devel meson ninja python-mako \
        libdrm glslang libclc vulkan-headers zlib

Void:

    sudo xbps-install -S base-devel meson ninja python3-Mako \
        libdrm-devel glslang libclc zlib-devel

Gentoo:

    sudo emerge --ask sys-devel/gcc sys-devel/make dev-util/meson \
        dev-util/ninja dev-python/mako sys-devel/flex sys-devel/bison \
        dev-util/pkgconf media-libs/libdrm dev-util/glslang \
        llvm-runtimes/libclc media-libs/vulkan-headers

(For `-Dmesa-clc=system` a recent system `glslang` and `libclc` are
required; on older releases either upgrade them, or configure Mesa with
`-Dmesa-clc=builtin` instead, which builds the bundled compiler and needs
no extra system dependency.)

### 1. Kernel and helpers

Prerequisites: a configured kernel tree for your A733 board with an
out-of-tree build directory (called `kernelbuild/` below, produced by
`make O=kernelbuild` from the kernel source). Note: a stock distro kernel
does not contain the A733 SoC support — you need the Allwinner BSP kernel
for your board anyway. The examples below use `doas`; substitute `sudo`
on distributions where that is the default root helper. The three
helper modules are built from the same tree:

    cd kernelbuild
    make M=../drivers/gpu/drm/scheduler modules        # gpu-sched.ko
    make M=../drivers/gpu/drm modules                  # drm_shmem_helper.ko, drm_exec.ko
    doas cp gpu-sched.ko drm-shmem-helper.ko drm-exec.ko \
        /lib/modules/$(uname -r)/extra/ 2>/dev/null
    doas depmod -a

(If your distro ships these helpers as `gpu_sched`, `drm_shmem_helper` and
`drm_exec` package modules, you can skip the build and use those instead;
they must expose `drm_sched_*`, `drm_gem_shmem_*` and `drm_exec_*`
exported symbols.)

### 2. The apercel module

    cd /path/to/apercel            # this repository
    make -C /path/to/kernelbuild M=$(pwd)/driver modules -j6
    doas cp driver/apercel.ko /lib/modules/$(uname -r)/extra/
    doas depmod -a

Or, end-to-end (after building the module):

    ./install.sh           # interactive, asks to reboot at the end
    ./install.sh --reboot  # install and reboot without asking

The install scripts detect `doas`/`sudo` automatically: `doas` is used
when present, otherwise `sudo`.

### 3. Firmware

The module loads `/lib/firmware/apercel/rogue_<BVNC>_v1.fw`. For a BXM-4-64
with BVNC 36.56.104.183 the expected file is:

    /lib/firmware/apercel/rogue_36.56.104.183_v1.fw

The firmware binary is not redistributed in this repository (proprietary
distribution terms). Current sources:

- Bespoke images for 36.56.104.183 ship with the Allwinner BSP:
  copy the file from the vendor firmware directory.
- Upstream `linux-firmware` already carries a BXM-4-64 image but for
  a different BVNC (36.52.104.182); it is useful for cross-checks but is
  not a drop-in replacement for 36.56.104.183. When a matching binary
  lands upstream, copy it into `/lib/firmware/apercel/` under the name
  above and everything just works.

### 4. Mesa userspace

From a clean vanilla mesa-26.1.8 source tree:

    cd mesa-26.1.8
    patch -p1 -u < /path/to/apercel/mesa/apercel-mesa.patch
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
    doas ninja -C b-2618 install
    doas ldconfig

The build is warning-free (0 warnings for the `imagination` directory).
Installed into `/usr/local/lib64` (EGL, GLX, GBM, dri, gbm,
`libvulkan_powervr_mesa`) plus
`/usr/local/share/vulkan/icd.d/powervr_mesa_icd.aarch64.json`.

### 5. Verify

After a reboot:

    ./tools/verify-after-reboot.sh
    ./tools/gpu-status.sh

The bench used in both (EGL 1.5 / zink over the opensource Vulkan driver,
desktop-like workload) reached 83.3 fps on the previous 840 MHz clock and
96 fps at 1.008 GHz; Mindustry reports 45–50 fps in a live game.

### 6. Remove

    ./uninstall.sh

It restores the previous kernel module (backup/*.ko), the previous modprobe.d
configuration, and regenerates the module dependency database.

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
CPU clusters are switched to the `performance` governor at boot. The same
one-liner applies everywhere; only the persistence differs per init
system:

The snippet:

    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        echo performance > "$policy/scaling_governor" 2>/dev/null
    done

systemd (Debian, Fedora, Arch, most others) — save as
`/etc/systemd/system/gpu-cpu-perf.service` (root), then
`systemctl daemon-reload && systemctl enable --now gpu-cpu-perf`:

    [Unit]
    Description=Set the CPU performance governor for the compositor

    [Service]
    Type=oneshot
    ExecStart=/bin/bash -c 'for p in /sys/devices/system/cpu/cpufreq/policy*; do echo performance > "$p/scaling_governor"; done'

    [Install]
    WantedBy=multi-user.target

OpenRC (Gentoo, Artix) — write the loop into
`/etc/local.d/gpu-cpu-perf.start` (remember
`chmod +x /etc/local.d/gpu-cpu-perf.start`) and ensure the `local` service
is enabled (`rc-update add local default`).

runit (Void) — put the loop into `/etc/rc.local`; Void runs it from its
runit rc-local job at boot.

The hook (written by `install.sh`) does two things at boot:

1. pins both CPU clusters to the `performance` governor (compositor
   latency after frequency hops measured ~1 s);
2. routes the GPU IRQ line (`IRQGPU` in `/proc/interrupts`) to the last
   (biggest) cores of the big.LITTLE layout — submit latency improves
   measurably (`grep IRQGPU /proc/interrupts` to verify afterwards).

To revert at runtime: `echo schedutil > .../scaling_governor` for each
policy, and disable/remove the persistence piece above if you want
battery-oriented behavior instead.

## Memory tuning for big games

Boards with 6-8 GiB RAM hit the OOM killer quickly when a heavy native
title (Factorio Space Age ~6 GiB of anonymous memory) runs next to a
compositor. The helper `/usr/local/sbin/apercel-memory-tune` (written by
`install.sh`) sets this up at boot:

1. **zram swap, 8 GiB, zstd compression, priority 5** — anonymous pages
   go to compressed RAM first (compression is ~5x here for the game's
   working set, so 6 GiB of application data costs ~1.5-3 GiB of
   resident memory);
2. **an existing file/network swap is left untouched with a lower
   priority** — it only fills if zram is exhausted;
3. `vm.swappiness=100`, `vm.page-cluster=0`, `vm.watermark_scale_factor=125`
   so reclaim prefers swap-out instead of stalling.

Measured under load (~7 GiB anonymous churn): zram filled steadily,
the system stayed interactive, no OOM.

To clean up: run each value back (`swapoff /dev/zram0 && zramctl -r
/dev/zram0`, remove the helper and persistence hook from
`uninstall.sh`).

## Troubleshooting

Common problems and fixes, in the order they typically appear:

**The module does not load (`modprobe: ERROR: could not insert apercel`)**
- `dmesg` right after the attempt tells the exact reason. The common ones:
  `Unknown symbol drm_sched_*` / `drm_gem_shmem_*` / `drm_exec_*` — the
  three helper modules are not loaded. Check
  `/lib/modules/$(uname -r)/extra/` and `/etc/modprobe.d/99-apercel.conf`
  (it force-loads them ahead of `apercel`).
- `apercel: exports duplicate symbol ... ` — a leftover vendor `pvrsrvkm`
  module is loaded or installed. `rmmod pvrsrvkm` (must be unused), or
  uninstall the vendor module files, and reboot.
- Nothing binds at all — check `/sys/bus/platform/drivers/apercel/` after
  boot: the device node `1800000.gpu` must be listed there. If not, the
  device tree does not carry an `img,gpu` compatible node (mostly seen on
  A733 vendors that only enable the vendor path).
- System boots slowly and then fails — look for
  `firmware: failed to load apercel/rogue_*.fw` in dmesg: the firmware file
  is missing or misnamed (see the firmware section above).

**The module loads but EGL/Vulkan reports nothing**
- zink surface empty with `vkEnumeratePhysicalDevices` failing: the Mesa
  build in use does not carry `PVR_DRM_DRIVER_NAME "apercel"`. Rebuild the
  Mesa stack from this repository's patch (see the install section), then
  restart the compositor.
- Both `llvmpipe (software)` and the PowerVR renderer should be visible:
  `eglinfo` shows zink (performance) and llvmpipe (fallback). If only
  llvmpipe appears, the ICD json
  `/usr/local/share/vulkan/icd.d/powervr_mesa_icd.aarch64.json` is missing
  or the build was done with `-Dvulkan-drivers=imagination` absent.

**Screen updates freeze for roughly a second**
- CPU-side `schedutil` governor clock drop. Set `performance` (see the CPU
  governor fix above) — this is compositor latency caused by CPU frequency
  hops, not the GPU.

**`cma_alloc timeout` messages on the console**
- They come from the display subsystem (sunxi DE), not from the GPU stack;
  known and harmless in the tested configuration.

**Vesktop does not start**
- Not solved yet; Electron on this configuration refuses to run on the
  PowerVR/zink stack. Progress/debugging notes welcome.

**A desktop GL application complains about OpenGL features/renderers**
- Desktop OpenGL on this hardware is provided by zink (GL translated to
  Vulkan on the fly). `glGetString(GL_RENDERER)` will show PowerVR in the
  renderer through zink. If an application requires specific desktop GL
  versions/features, check its requirement list — zink covers desktop GL
  functionality-wise, subject to device capabilities, and
  `MESA_GL_VERSION_OVERRIDE` can be used to present a higher version
  string when an app over-reports what it needs.

**Anything unexpected**
- Re-run `./tools/verify-after-reboot.sh` and `./tools/gpu-status.sh` and
  inspect `dmesg | grep -iE "apercel|bxm|pvr"`. For real bugs open a
  GitHub issue with those outputs.

## Acknowledgments

This project builds on:

- the open-source PowerVR kernel driver maintained in Mesa
  (Imagination Technologies Ltd., Linaro Ltd.);
- Mesa and its zink pipeline;
- the Orange Pi 4 Pro BSP kernel (orange-pi-6.6-sun60iw2) for SoC
  integration;
- linux-firmware for the open firmware image build.

## Credits

This project was inspired by the repository
[8borane8/retrorangepi4pro](https://github.com/8borane8/retrorangepi4pro)
— seeing that the community behind this hardware was alive is what made me
start working on the driver.
