# apercel Mesa component

The apercel userspace driver is the Imagination Vulkan driver from Mesa,
maintained here as an MIT-licensed patch on top of the vanilla mesa-26.1.8
tree. This directory holds the patch, its checksum and the manifest of the
modified files.

License: MIT (this directory). Upstream Mesa code carries its own MIT/X11
notices; the patch contains only changes made by the apercel project.

Files:
  LICENSE                   - MIT license for the apercel Mesa component
  manifest.txt              - modified files with a one-line note per file
  apercel-mesa.patch        - unified diff (vanilla mesa-26.1.8 -> apercel)
  apercel-mesa.patch.sha256 - sha256 checksum of the patch

Build (see the repository README for details):

  # get a clean vanilla mesa-26.1.8 tree
  git clone --branch 26.1.8 --depth 1 https://gitlab.freedesktop.org/mesa/mesa.git
  cd mesa
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
  sudo ninja -C b-2618 install
  sudo ldconfig
