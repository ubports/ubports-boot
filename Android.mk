#
# Copyright (C) 2014 Jolla Oy
# Copyright (C) 2017 Marius Gripsgard <marius@ubports.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

LOCAL_PATH:= $(call my-dir)
HYBRIS_PATH:=$(LOCAL_PATH)

# We use the commandline and kernel configuration varables from
# build/core/Makefile to be consistent. Support for boot/recovery
# image specific kernel COMMANDLINE vars is provided but whether it
# works or not is down to your bootloader.

HYBRIS_BOOTIMG_COMMANDLINE :=

# Find any fstab files for required partition information.
# in AOSP we could use TARGET_VENDOR
# TARGET_VENDOR := $(shell echo $(PRODUCT_MANUFACTURER) | tr '[:upper:]' '[:lower:]')
# but Cyanogenmod seems to use device/*/$(TARGET_DEVICE) in config.mk so we will too.
HYBRIS_FSTABS := $(shell find device/*/$(TARGET_DEVICE) -name *fstab* | grep -v goldfish)
# If fstab files were not found from primary device repo then they might be in
# some other device repo so try to search for them first in device/PRODUCT_MANUFACTURER. 
# In many cases PRODUCT_MANUFACTURER is the short vendor name used in folder names.
ifeq "$(HYBRIS_FSTABS)" ""
TARGET_VENDOR := "$(shell echo $(PRODUCT_MANUFACTURER) | tr '[:upper:]' '[:lower:]')"
HYBRIS_FSTABS := $(shell find device/$(TARGET_VENDOR) -name *fstab* | grep -v goldfish)
endif
# Some devices devices have the short vendor name in PRODUCT_BRAND so try to
# search from device/PRODUCT_BRAND if fstab files are still not found.
ifeq "$(HYBRIS_FSTABS)" ""
TARGET_VENDOR := "$(shell echo $(PRODUCT_BRAND) | tr '[:upper:]' '[:lower:]')"
HYBRIS_FSTABS := $(shell find device/$(TARGET_VENDOR) -name *fstab* | grep -v goldfish)
endif

# Get the unique /dev field(s) from the line(s) containing the fs mount point
# Note the perl one-liner uses double-$ as per Makefile syntax
HYBRIS_BOOT_PART := $(shell /usr/bin/perl -w -e '$$fs=shift; if ($$ARGV[0]) { while (<>) { next unless /^$$fs\s|\s$$fs\s/;for (split) {next unless m(^/dev); print "$$_\n"; }}} else { print "ERROR: *fstab* not found\n";}' /boot $(HYBRIS_FSTABS) | sort -u)
HYBRIS_DATA_PART := $(shell /usr/bin/perl -w -e '$$fs=shift; if ($$ARGV[0]) { while (<>) { next unless /^$$fs\s|\s$$fs\s/;for (split) {next unless m(^/dev); print "$$_\n"; }}} else { print "ERROR: *fstab* not found\n";}' /data $(HYBRIS_FSTABS) | sort -u)

$(warning ********************* /boot appears to live on $(HYBRIS_BOOT_PART))
$(warning ********************* /data appears to live on $(HYBRIS_DATA_PART))

ifneq ($(words $(HYBRIS_BOOT_PART))$(words $(HYBRIS_DATA_PART)),11)
$(error There should be a one and only one device entry for HYBRIS_BOOT_PART and HYBRIS_DATA_PART)
endif

HYBRIS_BOOTIMG_COMMANDLINE += datapart=$(HYBRIS_DATA_PART)


ifneq ($(strip $(TARGET_NO_KERNEL)),true)
  INSTALLED_KERNEL_TARGET := $(PRODUCT_OUT)/kernel
else
  INSTALLED_KERNEL_TARGET :=
endif

HYBRIS_BOOTIMAGE_ARGS := \
	$(addprefix --second ,$(INSTALLED_2NDBOOTLOADER_TARGET)) \
	--kernel $(INSTALLED_KERNEL_TARGET)

ifeq ($(BOARD_KERNEL_SEPARATED_DT),true)
  INSTALLED_DTIMAGE_TARGET := $(PRODUCT_OUT)/dt.img
  HYBRIS_BOOTIMAGE_ARGS += --dt $(INSTALLED_DTIMAGE_TARGET)
  BOOTIMAGE_EXTRA_DEPS := $(INSTALLED_DTIMAGE_TARGET)
endif

ifdef BOARD_KERNEL_BASE
  HYBRIS_BOOTIMAGE_ARGS += --base $(BOARD_KERNEL_BASE)
endif

ifdef BOARD_KERNEL_PAGESIZE
  HYBRIS_BOOTIMAGE_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
endif

# Strip lead/trail " from broken BOARD_KERNEL_CMDLINEs :(
HYBRIS_BOARD_KERNEL_CMDLINE := $(shell echo '$(BOARD_KERNEL_CMDLINE)' | sed -e 's/^"//' -e 's/"$$//')

ifneq "" "$(strip $(HYBRIS_BOARD_KERNEL_CMDLINE) $(HYBRIS_BOOTIMG_COMMANDLINE))"
  HYBRIS_BOOTIMAGE_ARGS += --cmdline "$(strip $(HYBRIS_BOARD_KERNEL_CMDLINE) $(HYBRIS_BOOTIMG_COMMANDLINE))"
endif


include $(CLEAR_VARS)
LOCAL_MODULE:= ubports-boot
# Here we'd normally include $(BUILD_SHARED_LIBRARY) or something
# but nothing seems suitable for making an img like this
LOCAL_MODULE_CLASS := ROOT
LOCAL_MODULE_SUFFIX := .img
LOCAL_MODULE_PATH := $(PRODUCT_OUT)

include $(BUILD_SYSTEM)/base_rules.mk
BOOT_INTERMEDIATE := $(call intermediates-dir-for,ROOT,$(LOCAL_MODULE),)

BOOT_RAMDISK := $(BOOT_INTERMEDIATE)/boot-initramfs.gz
BOOT_RAMDISK_SRC := $(LOCAL_PATH)/initramfs
BOOT_RAMDISK_FILES := $(shell find $(BOOT_RAMDISK_SRC) -type f)

$(LOCAL_BUILT_MODULE): $(INSTALLED_KERNEL_TARGET) $(BOOT_RAMDISK) $(BOOTIMAGE_EXTRA_DEPS)
	@echo "Making ubports-boot.img in $(dir $@) using $(INSTALLED_KERNEL_TARGET) $(BOOT_RAMDISK)"
	@mkdir -p $(dir $@)
	@rm -rf $@
ifeq ($(BOARD_CUSTOM_MKBOOTIMG),pack_intel)
	$(MKBOOTIMG) $(DEVICE_BASE_BOOT_IMAGE) $(INSTALLED_KERNEL_TARGET) $(BOOT_RAMDISK) $(cmdline) $@
else
	@mkbootimg --ramdisk $(BOOT_RAMDISK) $(HYBRIS_BOOTIMAGE_ARGS) $(BOARD_MKBOOTIMG_ARGS) --output $@
endif

$(BOOT_RAMDISK): $(BOOT_RAMDISK_FILES)
	@echo "Making initramfs : $@"
	@rm -rf $(BOOT_INTERMEDIATE)/initramfs
	@mkdir -p $(BOOT_INTERMEDIATE)/initramfs
	@cp -a $(BOOT_RAMDISK_SRC)/*  $(BOOT_INTERMEDIATE)/initramfs
ifeq ($(BOARD_CUSTOM_MKBOOTIMG),pack_intel)
	@(cd $(BOOT_INTERMEDIATE)/initramfs && find . | cpio -H newc -o ) | $(MINIGZIP) > $(BOOT_RAMDISK)
else
	@(cd $(BOOT_INTERMEDIATE)/initramfs && find . | cpio -H newc -o ) | gzip -9 > $@
endif

.PHONY: hybris-common

hybris-common: bootimage ubports-boot
