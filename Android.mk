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
UBPORTS_PATH:=$(LOCAL_PATH)

# We use the commandline and kernel configuration varables from
# build/core/Makefile to be consistent. Support for boot/recovery
# image specific kernel COMMANDLINE vars is provided but whether it
# works or not is down to your bootloader.

UBPORTS_BOOTIMG_COMMANDLINE :=

# Find any fstab files for required partition information.
# in AOSP we could use TARGET_VENDOR
# TARGET_VENDOR := $(shell echo $(PRODUCT_MANUFACTURER) | tr '[:upper:]' '[:lower:]')
# but Cyanogenmod seems to use device/*/$(TARGET_DEVICE) in config.mk so we will too.
UBPORTS_FSTABS := $(shell find device/*/$(TARGET_DEVICE) -name *fstab* | grep -v goldfish)
# If fstab files were not found from primary device repo then they might be in
# some other device repo so try to search for them first in device/PRODUCT_MANUFACTURER. 
# In many cases PRODUCT_MANUFACTURER is the short vendor name used in folder names.
ifeq "$(UBPORTS_FSTABS)" ""
TARGET_VENDOR := "$(shell echo $(PRODUCT_MANUFACTURER) | tr '[:upper:]' '[:lower:]')"
UBPORTS_FSTABS := $(shell find device/$(TARGET_VENDOR) -name *fstab* | grep -v goldfish)
endif
# Some devices devices have the short vendor name in PRODUCT_BRAND so try to
# search from device/PRODUCT_BRAND if fstab files are still not found.
ifeq "$(UBPORTS_FSTABS)" ""
TARGET_VENDOR := "$(shell echo $(PRODUCT_BRAND) | tr '[:upper:]' '[:lower:]')"
UBPORTS_FSTABS := $(shell find device/$(TARGET_VENDOR) -name *fstab* | grep -v goldfish)
endif

# Get the unique /dev field(s) from the line(s) containing the fs mount point
# Note the perl one-liner uses double-$ as per Makefile syntax
UBPORTS_BOOT_PART := $(shell /usr/bin/perl -w -e '$$fs=shift; if ($$ARGV[0]) { while (<>) { next unless /^$$fs\s|\s$$fs\s/;for (split) {next unless m(^/dev); print "$$_\n"; }}} else { print "ERROR: *fstab* not found\n";}' /boot $(UBPORTS_FSTABS) | sort -u)
UBPORTS_DATA_PART := $(shell /usr/bin/perl -w -e '$$fs=shift; if ($$ARGV[0]) { while (<>) { next unless /^$$fs\s|\s$$fs\s/;for (split) {next unless m(^/dev); print "$$_\n"; }}} else { print "ERROR: *fstab* not found\n";}' /data $(UBPORTS_FSTABS) | sort -u)

$(warning ********************* /boot appears to live on $(UBPORTS_BOOT_PART))
$(warning ********************* /data appears to live on $(UBPORTS_DATA_PART))

ifneq ($(words $(UBPORTS_BOOT_PART))$(words $(UBPORTS_DATA_PART)),11)
$(error There should be a one and only one device entry for UBPORTS_BOOT_PART and UBPORTS_DATA_PART)
endif

UBPORTS_BOOTIMG_COMMANDLINE += datapart=$(UBPORTS_DATA_PART)


ifneq ($(strip $(TARGET_NO_KERNEL)),true)
  INSTALLED_KERNEL_TARGET := $(PRODUCT_OUT)/kernel
else
  INSTALLED_KERNEL_TARGET :=
endif

UBPORTS_BOOTIMAGE_ARGS := \
	$(addprefix --second ,$(INSTALLED_2NDBOOTLOADER_TARGET)) \
	--kernel $(INSTALLED_KERNEL_TARGET)

ifeq ($(BOARD_KERNEL_SEPARATED_DT),true)
  INSTALLED_DTIMAGE_TARGET := $(PRODUCT_OUT)/dt.img
  UBPORTS_BOOTIMAGE_ARGS += --dt $(INSTALLED_DTIMAGE_TARGET)
  BOOTIMAGE_EXTRA_DEPS := $(INSTALLED_DTIMAGE_TARGET)
endif

ifdef BOARD_KERNEL_BASE
  UBPORTS_BOOTIMAGE_ARGS += --base $(BOARD_KERNEL_BASE)
endif

ifdef BOARD_KERNEL_PAGESIZE
  UBPORTS_BOOTIMAGE_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
endif

# Strip lead/trail " from broken BOARD_KERNEL_CMDLINEs :(
UBPORTS_BOARD_KERNEL_CMDLINE := $(shell echo '$(BOARD_KERNEL_CMDLINE)' | sed -e 's/^"//' -e 's/"$$//')

ifneq "" "$(strip $(UBPORTS_BOARD_KERNEL_CMDLINE) $(UBPORTS_BOOTIMG_COMMANDLINE))"
  UBPORTS_BOOTIMAGE_ARGS += --cmdline "$(strip $(UBPORTS_BOARD_KERNEL_CMDLINE) $(UBPORTS_BOOTIMG_COMMANDLINE))"
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

#UBPORTS_BOOT_RAMDISK := $(BOOT_INTERMEDIATE)/ubports-initramfs.gz
UBPORTS_BOOT_RAMDISK := $(LOCAL_PATH)/ubports-initramfs.gz
UBPORTS_BOOT_RAMDISK_SRC := $(LOCAL_PATH)/initramfs
UBPORTS_BOOT_RAMDISK_FILES := $(shell find $(UBPORTS_BOOT_RAMDISK_SRC) -type f)

$(LOCAL_BUILT_MODULE): $(INSTALLED_KERNEL_TARGET) $(UBPORTS_BOOT_RAMDISK) $(BOOTIMAGE_EXTRA_DEPS)
	@echo "Making ubports-boot.img in $(dir $@) using $(INSTALLED_KERNEL_TARGET) $(UBPORTS_BOOT_RAMDISK)"
	@mkdir -p $(dir $@)
	@rm -rf $@
ifeq ($(BOARD_CUSTOM_MKBOOTIMG),pack_intel)
	$(MKBOOTIMG) $(DEVICE_BASE_BOOT_IMAGE) $(INSTALLED_KERNEL_TARGET) $(UBPORTS_BOOT_RAMDISK) $(cmdline) $@
else
	@mkbootimg --ramdisk $(BOOT_RAMDISK) $(UBPORTS_BOOTIMAGE_ARGS) $(BOARD_MKBOOTIMG_ARGS) --output $@
endif

$(UBPORTS_BOOT_RAMDISK): $(UBPORTS_BOOT_RAMDISK_FILES)
	@echo "Making initramfs : $@"
	@rm -rf $(BOOT_INTERMEDIATE)/initramfs
	@mkdir -p $(BOOT_INTERMEDIATE)/initramfs
	@cp -a $(UBPORTS_BOOT_RAMDISK_SRC)/*  $(BOOT_INTERMEDIATE)/initramfs
ifeq ($(BOARD_CUSTOM_MKBOOTIMG),pack_intel)
	@(cd $(BOOT_INTERMEDIATE)/initramfs && find . | cpio -H newc -o ) | $(MINIGZIP) > $(UBPORTS_BOOT_RAMDISK)
else
	@(cd $(BOOT_INTERMEDIATE)/initramfs && find . | cpio -H newc -o ) | gzip -9 > $@
endif

.PHONY: ubports-common

ubports-common: bootimage ubports-boot
