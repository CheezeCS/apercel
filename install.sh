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

# ---------------------------------------------- 3a. CPU governor persistence
# Screen-update stalls trace back to the schedutil CPU governor hopping
# between ~400 MHz and max rates; keep both clusters pinned to 'performance'
# at boot. Init system is detected; the setup is idempotent.
cpu_perf_hook() {
    cat >"$1" <<'APEX_EOF'
#!/bin/bash
# apercel CPU governor fix: pin the compositor CPUs to the performance OPP.
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    echo performance > "$policy/scaling_governor" 2>/dev/null
done
APEX_EOF
}

if [ "${APERCEL_SKIP_CPU_PERF:-0}" = "1" ]; then
    log "APERCEL_SKIP_CPU_PERF=1: skipping the CPU governor persistence setup"
elif [ ! -d /run/openrc ] && [ ! -d /run/systemd/system ]; then
    log "init system not detected: skipping CPU governor persistence setup"
    log "(see README 'The CPU governor fix' and add the hook manually)"
elif [ -d /run/systemd/system ]; then
    # systemd is running (Debian, Fedora, Arch, and most others)
    if [ "$($SUDO systemctl is-enabled gpu-cpu-perf 2>/dev/null)" != "enabled" ]; then
        log "installing CPU governor unit: /etc/systemd/system/gpu-cpu-perf.service"
        $SUDO tee /etc/systemd/system/gpu-cpu-perf.service >/dev/null <<'APEX_UNIT'
[Unit]
Description=apercel: pin the CPU performance governor for the compositor

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for p in /sys/devices/system/cpu/cpufreq/policy*; do echo performance > "$p/scaling_governor"; done'

[Install]
WantedBy=multi-user.target
APEX_UNIT
        $SUDO systemctl daemon-reload || fail "systemctl daemon-reload failed"
        $SUDO systemctl enable gpu-cpu-perf || fail "systemctl enable gpu-cpu-perf failed"
    else
        log "CPU governor unit already installed and enabled, nothing to do"
    fi
elif [ -d /run/openrc ]; then
    # OpenRC (Gentoo, Artix)
    if [ -x /etc/local.d/gpu-cpu-perf.start ]; then
        log "/etc/local.d/gpu-cpu-perf.start already present, nothing to do"
    else
        log "installing CPU governor hook: /etc/local.d/gpu-cpu-perf.start"
        cpu_perf_hook /tmp/gpu-cpu-perf.start.$$
        $SUDO cp /tmp/gpu-cpu-perf.start.$$ /etc/local.d/gpu-cpu-perf.start || fail "install of gpu-cpu-perf.start failed"
        rm -f /tmp/gpu-cpu-perf.start.$$
        $SUDO chmod +x /etc/local.d/gpu-cpu-perf.start || fail "chmod of gpu-cpu-perf.start failed"
    fi
    $SUDO rc-update add local default 2>/dev/null || true   # enable 'local' service
elif [ -f /etc/rc.local ] || [ -d /etc/runit ]; then
    # runit / Void (also general rc.local path)
    if [ -f /etc/rc.local ] && grep -q "apercel cpu-governor" /etc/rc.local; then
        log "/etc/rc.local already hooks the CPU governor, nothing to do"
    else
        log "appending CPU governor hook to /etc/rc.local (marker-guarded)"
        {
            printf '\n# >>> apercel cpu-governor <<<\n'
            printf 'for policy in /sys/devices/system/cpu/cpufreq/policy*; do\n'
            printf '    echo performance > "$policy/scaling_governor" 2>/dev/null\n'
            printf 'done\n'
            printf '# <<< apercel cpu-governor <<<\n'
        } > /tmp/apercel-rclocal.append.$$
        $SUDO sh -c "cat /tmp/apercel-rclocal.append.$$ >> /etc/rc.local" || fail "append to /etc/rc.local failed"
        rm -f /tmp/apercel-rclocal.append.$$
    fi
else
    log "no supported init system found for CPU governor persistence"
fi

# ------------------------------------------------------------------- 4. verification
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
    answer=""
    read -r answer </dev/tty 2>/dev/null || read -r answer 2>/dev/null || true
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
