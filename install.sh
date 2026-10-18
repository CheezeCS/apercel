#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# apercel install script
#
# Installs the apercel kernel module, the modprobe configuration and the
# already-built apercel Mesa stack. Everything is idempotent: running the
# script twice changes nothing the second time.
#
# Usage:
#   ./install.sh            install (asks for root privileges: doas or sudo)
#   ./install.sh --reboot   install and reboot automatically after install
#
# Sections:
#   1. Verify artifacts.
#   2. Back up and remove the old kernel module.
#   3. Install the apercel module and modprobe config.
#   4. Verify the installed state.
#   5. Ask for reboot.

set -u

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRIVER_DIR="$PROJECT_DIR/driver"
BACKUP_DIR="$PROJECT_DIR/backup"
KERNEL_VERSION="$(uname -r)"
MODULE_DIR="/lib/modules/$KERNEL_VERSION/extra"
CONF_BAK_DIR="$PROJECT_DIR/backup/modprobe.d"

AUTO_REBOOT=0
if [ "${1:-}" = "--reboot" ]; then
    AUTO_REBOOT=1
fi

log()  { printf '[install] %s\n' "$*"; }
fail() { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }
need_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    command -v doas >/dev/null 2>&1 && return 0
    command -v sudo >/dev/null 2>&1 && return 0
    fail "need root privileges: no doas and no sudo found"
}

log "project dir: $PROJECT_DIR"
log "kernel:      $KERNEL_VERSION"

# ---------------------------------------------------------------- 1. artifacts
[ -f "$DRIVER_DIR/apercel.ko" ] || fail "$DRIVER_DIR/apercel.ko not found; run the build first"
[ -f "$PROJECT_DIR/conf/99-apercel.conf" ] || fail "$PROJECT_DIR/conf/99-apercel.conf not found"
[ -x /sbin/depmod ] || command -v depmod >/dev/null || fail "depmod not found"
need_root

# ------------------------------------------------- 2. backup old kernel module
mkdir -p "$BACKUP_DIR" "$CONF_BAK_DIR"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v doas >/dev/null 2>&1; then
        SUDO="doas"
    else
        SUDO="sudo"
    fi
fi

# Back up any previously installed apercel/pvr module files, then remove them.
for OLD in "$MODULE_DIR"/*.ko; do
    [ -e "$OLD" ] || continue
    case "$(basename "$OLD")" in
        apercel.ko) continue ;;
        *) ;;
    esac
    log "backing up old module $(basename "$OLD")"
    $SUDO cp "$OLD" "$BACKUP_DIR/$(basename "$OLD")" || fail "backup of $OLD failed"
    log "removing old module $(basename "$OLD") from $MODULE_DIR"
    $SUDO rm -f "$OLD" || fail "removal of $OLD failed"
done

# ------------------------------------------------------- 3. install everything
log "installing apercel.ko into $MODULE_DIR"
$SUDO cp "$DRIVER_DIR/apercel.ko" "$MODULE_DIR/apercel.ko" || fail "copy of apercel.ko failed"

log "installing modprobe config 99-apercel.conf"
# Back up and remove any previous module configuration files first.
$SUDO mkdir -p /etc/modprobe.d
for COND in /etc/modprobe.d/*apercel*.conf /etc/modprobe.d/*pvr*.conf; do
    [ -f "$COND" ] || continue
    log "archiving $(basename "$COND") to $CONF_BAK_DIR"
    $SUDO cp "$COND" "$CONF_BAK_DIR/" 2>/dev/null
    $SUDO rm -f "$COND"
done
$SUDO install -m 0644 "$PROJECT_DIR/conf/99-apercel.conf" /etc/modprobe.d/99-apercel.conf || fail "install of modprobe conf failed"

# Regenerate module dependency database so that 'apercel' resolves at boot.
log "running depmod -a"
$SUDO depmod -a || fail "depmod -a failed"

# Resign ownership of backups back to the invoking user.
for f in "$BACKUP_DIR"/*.ko "$CONF_BAK_DIR"/*.conf; do
    [ -f "$f" ] || continue
    $SUDO chown "$(id -u):$(id -g)" "$f" 2>/dev/null
done

# ------------------------------------------------------------- 4. verification
log "verifying installed state"
modinfo -F license "$MODULE_DIR/apercel.ko" | grep -q "GPL v2" || fail "apercel.ko license is not 'GPL v2'"
grep -q "alias of:N\*T\*Cimg,gpu " "/lib/modules/$KERNEL_VERSION/modules.alias" >/dev/null 2>&1 || \
    grep -q "apercel" "/lib/modules/$KERNEL_VERSION/modules.alias" || fail "modules.alias does not reference apercel"

log "installed: $(ls -la "$MODULE_DIR/apercel.ko")"
log "modprobe config: /etc/modprobe.d/99-apercel.conf"
log "rollback available: $BACKUP_DIR (old module + old modprobe config, see uninstall.sh)"

# -------------------------------------------------------------------- 5. reboot
if [ "$AUTO_REBOOT" -eq 1 ]; then
    log "rebooting now (module binds the GPU on the next boot)"
    $SUDO reboot
else
    printf '[install] install finished. Reboot now? [y/N]: '
    read -r answer </dev/tty
    case "$answer" in
        y|Y)
            log "rebooting (module binds the GPU on the next boot)"
            $SUDO reboot
            ;;
        *)
            log "no reboot. The module binds the GPU on the next boot."
            ;;
    esac
fi
