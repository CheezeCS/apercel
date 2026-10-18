# SPDX-License-Identifier: GPL-2.0-only
# Copyright (c) 2026 Apercel Project
#
# Out-of-tree build:
#   make -C <kernel-build-tree> M=$PWD modules
#
# The kernel side depends on three standalone DRM helper modules which are
# built from the same kernel tree on this platform:
#   drivers/gpu/drm/scheduler   (gpu-sched.ko)
#   drivers/gpu/drm             (drm_shmem_helper.ko, drm_exec.ko)
# Their Module.symvers file must be passed via DRM_SYMVERS so that modpost
# can resolve the drm_sched_*/drm_gem_shmem_*/drm_exec_* imports.
#
# Vendored shims: some BSP kernels do not build drm_gpuvm (and a few do not
# build drm_exec) in-tree. DRV_SYMVERS is scanned for the drm_gpuva_* and
# drm_exec_* symbols; a vendored implementation is compiled only when the
# symbol set is missing from the kernel tree, so the same Makefile builds
# against BSP trees both with and without those helpers in-tree.

DRM_SYMVERS ?= $(patsubst %/driver/Makefile,%,$(abspath $(lastword $(MAKEFILE_LIST))))/../work/opi-kernel/drivers/gpu/drm/Module.symvers

KBUILD_EXTRA_SYMBOLS := $(DRM_SYMVERS)
export KBUILD_EXTRA_SYMBOLS

KERNEL_SYMS := $(shell sed 's/\t/ /g' "$(DRM_SYMVERS)" 2>/dev/null | awk '{print $$2}')

ifeq ($(filter drm_gpuva_find_first drm_gpuva_insert drm_gpuvm_prepare_range,$(KERNEL_SYMS)),)
PVR_VENDOR_GPUVM := y
else
PVR_VENDOR_GPUVM := n
endif

ifeq ($(filter drm_exec_init drm_exec_cleanup drm_exec_prepare,$(KERNEL_SYMS)),)
PVR_VENDOR_EXEC := y
else
PVR_VENDOR_EXEC := n
endif

obj-m += apercel.o

apercel-y := \
	src/pvr_ccb.o \
	src/pvr_cccb.o \
	src/pvr_context.o \
	src/pvr_device.o \
	src/pvr_device_info.o \
	src/pvr_drv.o \
	src/pvr_free_list.o \
	src/pvr_fw.o \
	src/pvr_fw_meta.o \
	src/pvr_fw_mips.o \
	src/pvr_fw_riscv.o \
	src/pvr_fw_startstop.o \
	src/pvr_fw_trace.o \
	src/pvr_fw_util.o \
	src/pvr_gem.o \
	src/pvr_hwrt.o \
	src/pvr_job.o \
	src/pvr_mmu.o \
	src/pvr_params.o \
	src/pvr_power.o \
	src/pvr_queue.o \
	src/pvr_stream.o \
	src/pvr_stream_defs.o \
	src/pvr_sync.o \
	src/pvr_vm.o \
	src/pvr_vm_mips.o

apercel-y += $(if $(PVR_VENDOR_GPUVM),src/drm_gpuvm.o,)
apercel-y += $(if $(PVR_VENDOR_EXEC),src/pvr_drm_exec.o,)

ccflags-y += -I$(src)/src -I$(src)/src/include -I$(src)/src/include/uapi

apercel-$(CONFIG_DEBUG_FS) += src/pvr_debugfs.o
