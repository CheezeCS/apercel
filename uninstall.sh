#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# apercel uninstall / rollback script
#
# Restores the previous state:
#   - removes apercel.ko
#   - removes the apercel modprobe configuration
#   - puts back the previously backed-up kernel module (backup/*.ko)
#   - puts back the previously archived modprobe.d configuration
#   - runs depmod -a
#
# Usage:
#   ./uninstall.sh
#
# A reboot is required for the change to take effect.

set -u

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$PROJECT_DIR/backup"
CONF_BAK_DIR="$BACKUP_DIR/modprobe.d"
KERNEL_VERSION="$(uname -r)"
MODULE_DIR="/lib/modules/$KERNEL_VERSION/extra"

log()  { printf '[uninstall] %s\n' "$*"; }
fail() { printf '[uninstall] ERROR: %s\n' "$*" >&2; exit 1; }
need_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    command -v doas >/dev/null 2>&1 && return 0
    command -v sudo >/dev/null 2>&1 && return 0
    fail "need root privileges: no doas and no sudo found"
}

need_root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v doas >/dev/null 2>&1; then
        SUDO="doas"
    else
        SUDO="sudo"
    fi
fi

# Remove the installed apercel module.
if [ -f "$MODULE_DIR/apercel.ko" ]; then
    log "removing $MODULE_DIR/apercel.ko"
    $SUDO rm -f "$MODULE_DIR/apercel.ko" || fail "removal of apercel.ko failed"
fi

# Remove our modprobe configuration.
if [ -f /etc/modprobe.d/99-apercel.conf ]; then
    log "removing /etc/modprobe.d/99-apercel.conf"
    $SUDO rm -f /etc/modprobe.d/99-apercel.conf
fi

# Restore the previous kernel module, using the backup directory.
RESTORED=0
for CANDIDATE in "$BACKUP_DIR"/*.ko; do
    [ -e "$CANDIDATE" ] || continue
    case "$(basename "$CANDIDATE")" in
        apercel.ko) continue ;;
    esac
    RESTORED=1
    log "restoring $(basename "$CANDIDATE")"
    $SUDO cp "$CANDIDATE" "$MODULE_DIR/$(basename "$CANDIDATE")" || fail "restore of $(basename "$CANDIDATE") failed"
    break
done
if [ "$RESTORED" -eq 0 ]; then
    log "WARNING: no backed-up kernel module found in $BACKUP_DIR; GPU will have no driver"
fi

# Restore any previously archived modprobe.d files.
if [ -d "$CONF_BAK_DIR" ]; then
    for f in "$CONF_BAK_DIR"/*.conf; do
        [ -f "$f" ] || continue
        log "restoring /etc/modprobe.d/$(basename "$f")"
        $SUDO cp "$f" "/etc/modprobe.d/$(basename "$f")" || fail "restore of $(basename "$f") failed"
    done
fi

$SUDO depmod -a || fail "depmod -a failed"

# --------------------------------------------------- remove CPU-governor hooks
# Only the files created by install.sh are touched.
if [ -d /run/systemd/system ] && [ -f /etc/systemd/system/gpu-cpu-perf.service ]; then
    log "removing CPU governor unit /etc/systemd/system/gpu-cpu-perf.service"
    $SUDO systemctl disable --now gpu-cpu-perf 2>/dev/null
    $SUDO rm -f /etc/systemd/system/gpu-cpu-perf.service
    $SUDO systemctl daemon-reload 2>/dev/null
fi
if [ -f /etc/local.d/gpu-cpu-perf.start ]; then
    log "removing CPU governor hook /etc/local.d/gpu-cpu-perf.start"
    $SUDO rm -f /etc/local.d/gpu-cpu-perf.start
fi
if [ -f /etc/rc.local ] && grep -q "apercel cpu-governor" /etc/rc.local; then
    log "removing CPU governor hook from /etc/rc.local"
    $SUDO sed -i '/# >>> apercel cpu-governor <<</,/apercel cpu-governor <<</d' /etc/rc.local
fi

log "uninstall finished. Reboot to apply."
printf '[uninstall] Reboot now? [y/N]: '
answer=""
read -r answer </dev/tty 2>/dev/null || read -r answer 2>/dev/null || true
case "$answer" in
    y|Y) $SUDO reboot ;;
    *)   log "no reboot. Applied on the next boot." ;;
esac
