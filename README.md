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

Also tested on an **Orange Pi Zero 3W** (4 GB, Armbian trixie, vendor kernel
6.6.98-sun60iw2, open firmware 1.1.OS@6976702, Mesa 26.3 patch): the driver
probes and clocks the GPU at 1008 MHz, Vulkan compute and WSI work, sway
composites on the GPU, and Electron/Vesktop run with GPU acceleration. An
Armbian integration for that board (kernel config, image build) lives in
https://github.com/CheezeCS/a733-opengpu.

What this provides:

- An open-source kernel DRM driver ("apercel") built from the Mesa PowerVR
  kernel driver. No vendor `pvrsrvkm` binary module; the vendor graphics
  stack is not required on the system.
- A Mesa userspace stack covering Vulkan (the `imagination` Vulkan driver)
  with zink for OpenGL, maintained in this repository as a patch against
  vanilla mesa-26.1.8, plus a port to mesa-26.3.0-rc2 that brings
  VK_EXT_transform_feedback and with it OpenGL 3.2 / OpenGL ES 3.1 via zink.
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
| Factorio Space Age               | runs                      | ~55 fps windowed (half-res data textures, see below)  |
| Vesktop (Electron, Discord)      | works with Mesa 26.3      | see troubleshooting (Mesa 26.1.8: no GPU, see below)  |

Factorio performance notes (all measured with `--benchmark-graphics`):

- `streamed-atlas-physical-vram-size=32` is required (see troubleshooting:
  black squares otherwise); `texture-streaming` must stay enabled — with
  `false` the whole atlas is resident (~1.3 GB) and the process OOMs on a
  6 GiB board;
- the frame is capped by a fixed ~40 ms present/sync cost of the GPU
  submission path (measured identical at 128x128 and 1024x600 window),
  texture resolution and window size change it little;
- **half-resolution game textures**: all `data/**.png` game assets were
  downscaled to 50% in each dimension with nearest-neighbor (Pillow;
  ImageMagick is not installed; the `core/graphics/color_luts/`,
  `space-age/graphics/lut/` 16x16 3D LUTs and one unreadable
  `core/graphics/arrows/tip-arrow.png` are kept at original size — the
  LUTs must stay 16x16). Data files shrank 4.3 GB -> 2.5 GB and Factorio
  went from ~22 fps windowed to **~55 fps** (~3.5x). Prototype declares
  still match (no load errors except two harmless `sprite rectangle`
  warnings). To revert: `cp -a ~/factorio-data-original-backup/. ~/factorio/data/`.
- `mesa_gl_thread=true` (drirc option, enabled by the install via
  `~/.config/drirc`/`$XDG_CONFIG_HOME/drirc` or a per-game env var)
  moves GL submission off the main thread: +5 fps (16 → ~22); it also
  speeds up other CPU-bound GL applications;
- windowed mode (~22 fps) renders faster than fullscreen (~16 fps) on
  this GPU (fullscreen fence path is slower).

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

Debian 13 (trixie) has no system `mesa_clc` and no unversioned `libclc-dev`;
build the compiler in-tree with LLVM 19 instead (`-Dllvm=enabled
-Dmesa-clc=enabled` in step 4, and `PATH=/usr/lib/llvm-19/bin:$PATH`):

    sudo apt install build-essential meson ninja-build python3 python3-mako \
        python3-yaml flex bison pkg-config zlib1g-dev libzstd-dev libexpat1-dev \
        libdrm-dev libvulkan-dev clang libclang-cpp-dev libclang-19-dev \
        llvm-19-dev libllvmspirvlib-19-dev spirv-tools \
        libwayland-dev libwayland-egl-backend-dev wayland-protocols libudev-dev \
        libx11-dev libxext-dev libxfixes-dev libx11-xcb-dev libxcb1-dev \
        libxrandr-dev libxcb-glx0-dev libxcb-dri3-dev libxcb-present-dev \
        libxcb-shm0-dev libxcb-randr0-dev libxcb-sync-dev libxshmfence-dev \
        libxxf86vm-dev

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
required. Without them, build the bundled compiler with
`-Dllvm=enabled -Dmesa-clc=enabled` as shown for Debian trixie; Mesa 26.1.8
accepts only `enabled`, `system` or `auto` for `mesa-clc`. The PowerVR driver
always needs mesa-clc: it compiles its load-op shaders at build time.)

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

In the Orange Pi vendor tree `DRM_SCHED`, `DRM_EXEC` and
`DRM_GEM_SHMEM_HELPER` are tristates without a prompt, so setting them to `m`
in `.config` does not stick (`olddefconfig` drops the value) and the apercel
link fails with undefined `drm_sched_*` / `drm_exec_*` / `drm_gem_shmem_*`
symbols. Give them a prompt in `drivers/gpu/drm/Kconfig` first (a
`tristate "..."` line and `default m`), as done by kernel patch 0011 in
https://github.com/CheezeCS/a733-opengpu. When building apercel against a
tree whose `Module.symvers` is already read by kbuild, pass
`KBUILD_EXTRA_SYMBOLS=` (empty) on the make command line, or modpost sees
every exported symbol twice.

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

The firmware binary is not redistributed in this repository. Imagination
publishes an open-source build for this exact BVNC in its firmware repository
(branch `powervr`), linked from https://docs.mesa3d.org/drivers/powervr.html:

    doas install -d /lib/firmware/apercel
    doas curl -fL -o /lib/firmware/apercel/rogue_36.56.104.183_v1.fw \
      https://gitlab.freedesktop.org/imagination/linux-firmware/-/raw/8a58f81883f7be458daa34e418cc4079f995b279/powervr/rogue_36.56.104.183_v1.fw
    echo "1db1c399c17401d1f79d46c880db81c724d748c784d4639433b076aba2f9c0d2  /lib/firmware/apercel/rogue_36.56.104.183_v1.fw" | sha256sum -c

(firmware version 1.1.OS@6976702; the default branch of that repository is
`powervr`, not `main`). Do not use the `rgx.fw.36.56.104.183` blob from the
vendor BSP packages: it is a `pvrsrvkm` build (fw_info version 2, no
open-source flag) and the driver rejects it with
`Unsupported fw info version 2`.

### 4. Mesa userspace

Two patches are provided: `mesa/apercel-mesa.patch` for mesa-26.1.8 and
`mesa/apercel-mesa-26.3.0-rc2.patch` for mesa-26.3.0-rc2 (recommended: it
adds VK_EXT_transform_feedback, so zink reaches OpenGL 3.2 / ES 3.1; see
`mesa/README.txt`). The commands are the same apart from the tree and the
patch file. On Debian trixie replace `-Dllvm=disabled -Dmesa-clc=system`
with `-Dllvm=enabled -Dmesa-clc=enabled` (see step 0).

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

**Factorio with texture streaming shows black squares / silhouettes**
- The GPU's GL limit here is `GL_MAX_TEXTURE_SIZE = 4096` (the Vulkan
  device reports `maxImageDimension2D = 4096`; zink mirrors it), while
  Factorio's streamed atlas defaults to a physical page of `8192x4096`.
  Every streamed-page allocation then fails with
  `[OpenGL]: Error INVALID_VALUE`, each frame afterwards logs
  `INVALID_OPERATION`, and un-streamed sprites render as black shapes.
- Fix: cap the streamed page budget to the 32 MB variant, which Factorio
  lays out as a single `4096x4096` texture. In
  `~/factorio/config/config.ini` under `[graphics]` set
  `streamed-atlas-physical-vram-size=32`.
- Alternative (more RAM, zero artifacts): `texture-streaming=false`.

**`cma_alloc timeout` messages on the console**
- They come from the display subsystem (sunxi DE), not from the GPU stack;
  known and harmless in the tested configuration.

**Vesktop / Electron / Chromium has no GPU acceleration (Mesa 26.1.8)**
- Chromium's GPU process (Electron 45 / Chromium 152) requires an OpenGL ES
  3.0 context and no longer falls back to ES 2.0. With Mesa 26.1.8 zink only
  reaches ES 2.0 (no VK_EXT_transform_feedback in the PowerVR driver), so the
  GPU process exits ("ES version fallback is disabled", then "GPU access is
  disabled due to frequent crashes") and the app renders in software.
- Fix: the Mesa 26.3 patch (zink reaches ES 3.1; Vesktop 1.6.8 tested under
  sway on an Orange Pi Zero 3W). With 26.1.8, start the app with
  `--use-angle=vulkan` instead: ANGLE then renders on the PowerVR Vulkan
  driver directly and emulates transform feedback itself.

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
