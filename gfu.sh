#!/bin/bash
# title           :gfu.sh
# description     :Installing the GRUB loader on a USB device.
# author          :Alexander Zhirov
# date            :20241014
# version         :0.1.0
# usage           :bash gfu.sh
#===============================================================================

[ ${GFU_DEBUG} ] && set -x

SCRIPT_NAME="${0}"
SCRIPT_PATH=$(dirname $(realpath ${SCRIPT_NAME}))

GFU_PARTED=$(which parted 2>/dev/null)
GFU_GRUB=$(which grub-install 2>/dev/null)

[ -z "${GFU_PARTED}" ] && echo "The parted utility is not installed!" && exit 1
[ -z "${GFU_GRUB}" ] && echo "The grub-install utility is not installed!" && exit 1

[ ! "$(id -u)" == 0 ] && echo "Need to run as superuser!" && exit 1

main () {
    local GFU_KEY=""
    local GFU_DEVICE=""
    local GFU_LEGACY_MODE=false
    local GFU_EFI_MODE=false
    local GFU_MOUNT_PATH=""

    while [[ $# -gt 0 ]] ; do
        GFU_KEY="$1"
        case "${GFU_KEY}" in
            -d|--device)
                GFU_DEVICE="${2}"
                shift
                ;;
            -l|--legacy)
                GFU_LEGACY_MODE=true
                ;;
            -e|--efi)
                GFU_EFI_MODE=true
                ;;
            *)
                echo -e "Usage: $(basename ${SCRIPT_NAME}) -d <device> [OPTION]\n\n" \
                    "\t-d, --device <device>\tBootloader Installation Device\n" \
                    "\t-l, --legacy\t\tInstalling Legacy Bootloader\n" \
                    "\t-e, --efi\t\tInstalling EFI Bootloader\n"
                exit 1
                ;;
        esac
        shift
    done

    local GFU_GRUB_PATH="/usr/lib/grub"
    local GFU_GRUB_EFI_X32="i386-efi"
    local GFU_GRUB_EFI_X64="x86_64-efi"
    local GFU_GRUB_LEGACY="i386-pc"
    local GFU_MOUNT_PATH="$(mktemp -d)"

    GFU_DEVICE=${GFU_DEVICE:-$ENV_GFU_DEVICE}
    [ -z "${GFU_DEVICE}" ] && echo "ENV_GFU_DEVICE: The device was not set" && exit 1
    [ ! -b ${GFU_DEVICE} ] && echo "ENV_GFU_DEVICE: Device not found: ${GFU_DEVICE}" && exit 1

    ${GFU_LEGACY_MODE} && ${GFU_EFI_MODE} && echo "You only need to set one mode: legacy or efi" && exit 1
    ! ${GFU_LEGACY_MODE} && ! ${GFU_EFI_MODE} && echo "None of the modes are set: legacy or efi" && exit 1

    if ${GFU_LEGACY_MODE} ; then
        local GFU_GRUB_LEGACY_MODE_PATH="${GFU_GRUB_PATH}/${GFU_GRUB_LEGACY}"
        local GFU_GRUB_LEGACY_MODE=false

        [ -d ${GFU_GRUB_LEGACY_MODE_PATH} ] && GFU_GRUB_LEGACY_MODE=true

        ! ${GFU_GRUB_LEGACY_MODE} && echo "No legacy bootloader was found for installation: ${GFU_GRUB_LEGACY}" && exit 1
    fi

    if ${GFU_EFI_MODE} ; then
        local GFU_GRUB_EFI_MODE_X32_PATH="${GFU_GRUB_PATH}/${GFU_GRUB_EFI_X32}"
        local GFU_GRUB_EFI_MODE_X64_PATH="${GFU_GRUB_PATH}/${GFU_GRUB_EFI_X64}"
        local GFU_GRUB_EFI_MODE_X32=false
        local GFU_GRUB_EFI_MODE_X64=false

        [ -d ${GFU_GRUB_EFI_MODE_X32_PATH} ] && GFU_GRUB_EFI_MODE_X32=true
        [ -d ${GFU_GRUB_EFI_MODE_X64_PATH} ] && GFU_GRUB_EFI_MODE_X64=true

        ! ${GFU_GRUB_EFI_MODE_X32} && ! ${GFU_GRUB_EFI_MODE_X64} && echo "No EFI bootloader was found for installation: ${GFU_GRUB_EFI_X32} or ${GFU_GRUB_EFI_X64}" && exit 1
    fi

    while true; do
        read -p "All data will be deleted from your device ${GFU_DEVICE}. Are you ready to continue? [Y/N]: " answer
        case "$answer" in
            [Yy]* ) break ;;
            [Nn]* ) exit 0 ;;
            * ) ;;
        esac
    done

    for partition in $(mount | grep "${GFU_DEVICE}[0-9]" | awk '{print $1}') ; do
        if ! umount -f ${partition} ; then
            echo "Failed to unmount ${partition}"
            exit 1
        fi
    done

    if ${GFU_LEGACY_MODE} ; then
        if parted ${GFU_DEVICE} -s mklabel msdos > /dev/null 2>&1 ; then
            echo "The msdos partition table on ${GFU_DEVICE} has been created successfully."
        else
            echo "Failed to create msdos partition table on ${GFU_DEVICE}. Further installation will be terminated."
            exit 1
        fi
    else
        if parted ${GFU_DEVICE} -s mklabel gpt > /dev/null 2>&1 ; then
            echo "The gpt partition table on ${GFU_DEVICE} has been created successfully."
        else
            echo "Failed to create gpt partition table on ${GFU_DEVICE}. Further installation will be terminated."
            exit 1
        fi
    fi

    if ! parted ${GFU_DEVICE} -s -- mkpart primary fat32 2048s 2099199s > /dev/null 2>&1 ; then
        echo "Failed to create primary partition on ${GFU_DEVICE}. Further installation will be terminated."
        exit 1
    fi

    if ! parted ${GFU_DEVICE} -s set 1 boot on  > /dev/null 2>&1 ; then
        echo "Failed to make partition bootable. Further installation will be terminated."
        exit 1
    fi

    if ${GFU_LEGACY_MODE} ; then
        if ! parted ${GFU_DEVICE} -s set 1 lba on > /dev/null 2>&1 ; then
            echo "Failed to set lba flag. Further installation will be terminated."
            exit 1
        fi
    fi

    if ! mkfs.fat -F32 ${GFU_DEVICE}1 > /dev/null 2>&1 ; then
        echo "Failed to format ${GFU_DEVICE}1 to fat32. Further installation will be terminated."
        exti 1
    fi

    if ! mount -v -o umask=000 ${GFU_DEVICE}1 ${GFU_MOUNT_PATH} > /dev/null 2>&1 ; then
        echo "Failed to mount the device ${GFU_DEVICE}1 to the path ${GFU_MOUNT_PATH}. Further installation will be terminated."
        exit 1
    fi

    if ${GFU_LEGACY_MODE} ; then
        if ${GFU_GRUB_LEGACY_MODE} ; then
            if grub-install --no-floppy --boot-directory=${GFU_MOUNT_PATH}/boot --target=${GFU_GRUB_LEGACY} ${GFU_DEVICE} > /dev/null 2>&1 ; then
                echo "i386-pc bootloader was installed successfully."
            else
                echo "Failed to install i386-pc bootloader. Further installation will be terminated."
                exit 1
            fi
        fi
    else
        if ${GFU_GRUB_EFI_MODE_X32} ; then
            if grub-install --removable --boot-directory=${GFU_MOUNT_PATH}/boot --efi-directory=${GFU_MOUNT_PATH} --target=${GFU_GRUB_EFI_X32} ${GFU_DEVICE} > /dev/null 2>&1 ; then
                echo "i386-efi bootloader was installed successfully."
            else
                echo "Failed to install i386-efi bootloader. Further installation will be terminated."
                exit 1
            fi
        fi
        if ${GFU_GRUB_EFI_MODE_X64} ; then
            if grub-install --removable --boot-directory=${GFU_MOUNT_PATH}/boot --efi-directory=${GFU_MOUNT_PATH} --target=${GFU_GRUB_EFI_X64} ${GFU_DEVICE} > /dev/null 2>&1 ; then
                echo "x86_64-efi bootloader was installed successfully."
            else
                echo "Failed to install x86_64-efi bootloader. Further installation will be terminated."
                exit 1
            fi
        fi
    fi

    if [ -d ${SCRIPT_PATH}/grub ] ; then
        cp -r ${SCRIPT_PATH}/grub ${GFU_MOUNT_PATH}/boot
    else
        touch ${GFU_MOUNT_PATH}/boot/grub/grub.cfg
    fi

    if ! umount -v ${GFU_DEVICE}1 > /dev/null 2>&1 ; then
        echo "The installation is almost complete. But ${GFU_DEVICE} could not be unmounted."
        exit 1
    fi

    rm -rf ${GFU_MOUNT_PATH}

    echo "The boot device was created successfully!"
}

main "${@}"
