# apercel Mesa component

The apercel userspace driver is the Imagination Vulkan driver from Mesa,
maintained here as an MIT-licensed patch on top of the vanilla mesa-26.1.8
tree, plus a port of the same changes to mesa-26.3.0-rc2. This directory
holds the patches, their checksums and the manifest of the modified files.

License: MIT (this directory). Upstream Mesa code carries its own MIT/X11
notices; the patches contain only changes made by the apercel project.

Files:
  LICENSE                               - MIT license for the apercel Mesa component
  manifest.txt                          - modified files with a one-line note per file
  apercel-mesa.patch                    - unified diff (vanilla mesa-26.1.8 -> apercel)
  apercel-mesa.patch.sha256             - sha256 checksum of the patch
  apercel-mesa-26.3.0-rc2.patch         - the same changes on vanilla mesa-26.3.0-rc2
  apercel-mesa-26.3.0-rc2.patch.sha256  - sha256 checksum of that patch

Which one:

  mesa-26.1.8     zink exposes OpenGL 2.1 / OpenGL ES 2.0 only: the PowerVR
                  Vulkan driver has no VK_EXT_transform_feedback, which zink
                  needs for ES 3.0 / GL 3.x. Chromium and Electron apps then
                  fall back to software rendering (or need --use-angle=vulkan).
  mesa-26.3.0-rc2 adds VK_EXT_transform_feedback for PowerVR (Mesa MR !44385):
                  zink exposes OpenGL 3.2 core / OpenGL ES 3.1, Chromium and
                  Electron get GPU acceleration without flags. Tested on an
                  Orange Pi Zero 3W (Vulkan compute, vkcube on Wayland, sway,
                  Vesktop). It is a release candidate: rebase when 26.3.0 is out.

Build (see the repository README for details):

  # get a clean vanilla tree: mesa-26.1.8 or mesa-26.3.0-rc2
  curl -fLO https://archive.mesa3d.org/mesa-26.3.0-rc2.tar.xz
  tar xf mesa-26.3.0-rc2.tar.xz && cd mesa-26.3.0-rc2
  patch -p1 < /path/to/apercel/mesa/apercel-mesa-26.3.0-rc2.patch
  # (for 26.1.8: git clone --branch mesa-26.1.8 --depth 1 \
  #    https://gitlab.freedesktop.org/mesa/mesa.git, then apercel-mesa.patch)

  meson setup b --prefix=/usr/local \
    -Dbuildtype=release \
    -Dvulkan-drivers=imagination \
    -Dgallium-drivers=zink \
    -Degl=enabled -Dgbm=enabled -Dopengl=true \
    -Dgles1=disabled -Dgles2=enabled \
    -Dplatforms=x11,wayland -Dglx=dri -Dxlib-lease=disabled \
    -Dllvm=disabled \
    -Dmesa-clc=system -Dshader-cache=enabled -Dbuild-tests=false

  ninja -C b
  sudo ninja -C b install
  sudo ldconfig

Distributions without a system mesa_clc (Debian trixie, for one) build the
compiler in-tree instead: -Dllvm=enabled -Dmesa-clc=enabled, with one LLVM
major throughout (LLVM 19 on trixie), see the repository README.

How the 26.3 port was made: a three-way merge (vanilla 26.1.8 -> apercel,
cherry-picked onto vanilla 26.3.0-rc2). Eight files conflicted; Vulkan
features are the union of upstream's and apercel's, descriptor limits are
apercel's, upstream's new function signatures are kept with apercel's logic
moved into them. Two follow-ups: DRM_PVR_BO_CPU_CACHED is defined as 0 in
include/drm-uapi/pvr_drm.h (see the 26.1.8 patch), and the PVR_API_TRACE code
uses the three-argument vk_foreach_struct_const() of 26.3.
