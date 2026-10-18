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
# Their Module.symvers files must be passed via KBUILD_EXTRA_SYMBOLS so that
# modpost can resolve the drm_sched_*/drm_gem_shmem_*/drm_exec_* imports.

DRM_SYMVERS ?= $(patsubst %/driver/Makefile,%,$(abspath $(lastword $(MAKEFILE_LIST))))/../work/opi-kernel/drivers/gpu/drm/Module.symvers

KBUILD_EXTRA_SYMBOLS := $(DRM_SYMVERS)
export KBUILD_EXTRA_SYMBOLS

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
	src/drm_gpuvm.o \
	src/pvr_sync.o \
	src/pvr_vm.o \
	src/pvr_vm_mips.o

ccflags-y += -I$(src)/src -I$(src)/src/include -I$(src)/src/include/uapi

apercel-$(CONFIG_DEBUG_FS) += src/pvr_debugfs.o
apercel-$(CONFIG_AW_DRM_POWERVR) += src/pvr_drm_exec.o
