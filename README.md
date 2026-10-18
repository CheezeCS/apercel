# apercel

Open-source GPU support for the Imagination BXM-4-64 GPU (PowerVR Rogue
family, BVNC 36.56.104.183) built into the Allwinner A733 SoC, on
Gentoo aarch64.

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

Programs tested on the Orange Pi 4 Pro (Gentoo aarch64, sway compositor):

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

Useful environment facts for the recipe below: the reference system is
Gentoo aarch64 on the Orange Pi 4 Pro, kernel 6.6.98-sun60iw2 (the
"orange-pi-6.6-sun60iw2" BSP tree with the out-of-tree build directory
`kernelbuild/` inside the kernel source root), OpenRC init, and any compositor
or display server. The steps assume a running Linux; adjust paths to your
system where needed.

### 1. Kernel and helpers

Prerequisites: a configured kernel tree for your A733 board with an
out-of-tree build directory (called `kernelbuild/` below, produced by
`make O=kernelbuild` from the kernel source). The three helper modules are
built from the same tree:

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

Both scripts prefer `doas` (as configured on the reference system) and
fall back to `sudo`.

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
CPU clusters are switched to the `performance` governor at boot by
`/etc/local.d/gpu-cpu-perf.start` (OpenRC `local` service):

    #!/bin/bash
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        echo performance > "$policy/scaling_governor" 2>/dev/null
    done

Revert with `echo schedutil > .../scaling_governor` and
`rc-update del local` if you want battery-oriented behavior instead.

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
