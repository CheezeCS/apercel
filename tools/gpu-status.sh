#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# apercel live status
#
# Prints the current state of the GPU stack: kernel driver, GPU clock, GPU
# temperature, memory bus state and the renderer used by EGL. Dry text.
#
# Usage: ./gpu-status.sh
#
# Root (sudo) is ONLY required for the GPU clock rate read (clk debugfs).

set -u

# Pick the easiest root helper: doas (configured passwordless here),
# then passwordless sudo, else plain sudo (works in interactive sessions).
if command -v doas >/dev/null 2>&1 && doas true 2>/dev/null; then
    SUDO="doas"
elif [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif sudo -n true 2>/dev/null; then
    SUDO="sudo"
else
    SUDO="sudo"
fi

printf 'driver: '
if U="$(lsmod | awk '$1 == "apercel" {print $1, $2}')"; [ -n "$U" ]; then
    printf 'apercel %s (loaded)\n' "$U"
else
    printf 'apercel NOT loaded\n'
fi

printf 'GPU dev: '
for D in /sys/bus/platform/drivers/powevr /sys/bus/platform/drivers/apercel; do
    [ -e "$D/1800000.gpu" ] && printf '%s\n' "$D/1800000.gpu" && break
done

printf 'gpu clock: '
$SUDO grep -E '(^|[[:space:]])(gpu0|pll-gpu)([[:space:]]|$)' /sys/kernel/debug/clk/clk_summary 2>/dev/null

printf 'gpu temp: '
for d in /sys/class/thermal/thermal_zone*; do
    type="$(cat "$d/type" 2>/dev/null)"
    if [ "$type" = "gpu_thermal_zone" ]; then
        printf '%s mC\n' "$(cat "$d/temp")"
        break
    fi
done

printf 'renderer: '
timeout 30 "$HOME/.local/share/gpu-tools/glbench" 2>/dev/null | head -2 | grep RENDERER || printf 'glbench not available\n'
