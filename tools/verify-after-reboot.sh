#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# apercel post-boot verification script
#
# Verifies that after a reboot the apercel kernel driver is bound to the GPU,
# the modprobe configuration has been applied, the GPU clock is at its maximum
# rate, and the thermal governor is wired to the gpu_thermal_zone.
#
set -u

FAIL_TOTAL=0

fail() {
    FAIL_TOTAL=$((FAIL_TOTAL + 1))
    printf 'FAIL: %s\n' "$*"
}

ok() {
    printf 'PASS: %s\n' "$*"
}

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

# 1. Module bindings: apercel must be loaded and bound to the GPU device.
MODNAME="$(lsmod | awk '$1 == "apercel" {print $1}')"
if [ "$MODNAME" = "apercel" ]; then
    ok "apercel module is loaded"
else
    fail "apercel module is not loaded (lsmod)"
fi

# The platform driver name string inside the driver is 'powevr'; the MODULE
# (lsmod) name is 'apercel'. Accept both sysfs spellings.
BOUND=""
for D in /sys/bus/platform/drivers/powevr /sys/bus/platform/drivers/apercel; do
    if [ -e "$D/1800000.gpu" ]; then
        BOUND="$D/1800000.gpu"
        break
    fi
done
if [ -n "$BOUND" ]; then
    ok "GPU device bound: $BOUND"
else
    fail "no GPU device bound under /sys/bus/platform/drivers/{powevr,apercel}"
fi

# 2. modprobe.d configuration applied: no_autosuspend must be set.
if lsmod | awk '$1 == "apercel" {found=1} END {exit !found}'; then
    NOAS="$(cat /sys/module/apercel/parameters/no_autosuspend 2>/dev/null)"
    case "$NOAS" in
        1|Y) ok "no_autosuspend applied ($NOAS)" ;;
        "") fail "no /sys/module/apercel/parameters/no_autosuspend (module not loaded?)";;
        *) fail "no_autosuspend applied as '$NOAS' (expected 1 or Y)";;
    esac
fi

# 3. GPU clock rate must be at its maximum (1.008 GHz).
PGPU_CLK="$($SUDO grep -E '(^|[[:space:]])(gpu0|pll-gpu)([[:space:]]|$)' /sys/kernel/debug/clk/clk_summary 2>/dev/null)"
if printf '%s\n' "$PGPU_CLK" | grep -qE '[[:space:]]1008000000[[:space:]]'; then
    ok "GPU clock at maximum"
    printf '%s\n' "$PGPU_CLK"
else
    fail "GPU clock not at 1.008 GHz (clock summary: $PGPU_CLK)"
fi

# 4. Thermal governor bind: check the dmesg for the governor.
DMESG="$($SUDO dmesg 2>/dev/null)"
if printf '%s' "$DMESG" | grep -q 'apercel-governor'; then
    ok "apercel-governor active in dmesg:"
    printf '%s\n' "$DMESG" | grep 'apercel-governor'
else
    fail "no apercel-governor messages in dmesg"
fi

# 5. GPU thermal zone present with a valid temperature.
TZ="$(for d in /sys/class/thermal/thermal_zone*; do
        [ "$(cat "$d/type" 2>/dev/null)" = "gpu_thermal_zone" ] && cat "$d/temp" 2>/dev/null && break
      done)"
if [ -n "$TZ" ] && [ "$TZ" -gt 0 ]; then
    ok "gpu_thermal_zone reading $((TZ / 1000)) C"
else
    fail "gpu_thermal_zone not readable"
fi

# 6. GPU achieves real 3D work: zink opensung driver reports the device.
RENDERER="$(timeout 30 "$HOME/.local/share/gpu-tools/glbench" 2>/dev/null | head -2)"
if printf '%s' "$RENDERER" | grep -q 'PowerVR B-Series'; then
    ok "EGL reports real GPU: $(printf '%s' "$RENDERER" | head -2 | tail -1)"
else
    fail "EGL did not report a PowerVR B-Series renderer (got: $RENDERER)"
fi

if [ "$FAIL_TOTAL" -eq 0 ]; then
    printf 'Everything OK\n'
    exit 0
fi
printf 'Failures: %s\n' "$FAIL_TOTAL"
exit 1
