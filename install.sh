#!/bin/bash

[ ${GFU_DEBUG} ] && set -x

# set -x

SCRIPT_NAME="${0}"
SCRIPT_PATH=$(dirname $(realpath ${SCRIPT_NAME}))

GFU_PARTED=$(which parted 2>/dev/null)
GFU_GRUB=$(which grub-install 2>/dev/null)

[ -z "${GFU_PARTED}" ] && echo "The parted utility is not installed" && exit 1
[ -z "${GFU_GRUB}" ] && echo "The grub-install utility is not installed" && exit 1

[ ! "$(id -u)" == 0 ] && echo "Need to run as superuser" && exit 1

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
            -p|--path)
                GFU_MOUNT_PATH="${2}"
                shift
                ;;
            *)
                break
                ;;
        esac
        shift
    done

    local GFU_GRUB_PATH="/usr/lib/grub"
    local GFU_GRUB_EFI_X32="i386-efi"
    local GFU_GRUB_EFI_X64="x86_64-efi"
    local GFU_GRUB_LEGACY="i386-pc"

    GFU_DEVICE=${GFU_DEVICE:-$ENV_GFU_DEVICE}
    [ -z "${GFU_DEVICE}" ] && echo "ENV_GFU_DEVICE: The device was not set" && exit 1
    [ ! -b ${GFU_DEVICE} ] && echo "ENV_GFU_DEVICE: Device not found: ${GFU_DEVICE}" && exit 1

    ${GFU_LEGACY_MODE} && ${GFU_EFI_MODE} && echo "You only need to set one mode: legacy or efi" && exit 1
    ! ${GFU_LEGACY_MODE} && ! ${GFU_EFI_MODE} && echo "None of the modes are set: legacy or efi" && exit 1

    GFU_MOUNT_PATH=${GFU_MOUNT_PATH:-$ENV_GFU_MOUNT_PATH}
    [ -z "${GFU_MOUNT_PATH}" ] && echo "ENV_GFU_MOUNT_PATH: The path to the mount directory was not set" && exit 1
    GFU_MOUNT_PATH=$(realpath ${GFU_MOUNT_PATH} 2>/dev/null)

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

    if [ ! -d ${GFU_MOUNT_PATH} ] ; then
        echo "Path is not a directory: ${GFU_MOUNT_PATH}"
        exit 1
    fi

    if [ ! -z "$(ls -A ${GFU_MOUNT_PATH})" ]; then
        echo "Path is not empty: ${GFU_MOUNT_PATH}"
        exit 1
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
        parted ${GFU_DEVICE} -s mklabel msdos
    else
        parted ${GFU_DEVICE} -s mklabel gpt
    fi

    parted ${GFU_DEVICE} -s -- mkpart primary fat32 2048s 2099199s
    parted ${GFU_DEVICE} -s set 1 boot on

    if ${GFU_LEGACY_MODE} ; then
        parted ${GFU_DEVICE} -s set 1 lba on
    fi

    mkfs.fat -F32 ${GFU_DEVICE}1

    if ! mount -v -o umask=000 ${GFU_DEVICE}1 ${GFU_MOUNT_PATH} ; then
        echo "Failed to mount the device ${GFU_DEVICE}1 to the path ${GFU_MOUNT_PATH}. Further installation will be terminated"
        exit 1
    fi

    if ${GFU_LEGACY_MODE} ; then
        ${GFU_GRUB_LEGACY_MODE} && grub-install --no-floppy --boot-directory=${GFU_MOUNT_PATH}/boot --target=${GFU_GRUB_LEGACY} ${GFU_DEVICE}
    else
        ${GFU_GRUB_EFI_MODE_X32} && grub-install --removable --boot-directory=${GFU_MOUNT_PATH}/boot --efi-directory=${GFU_MOUNT_PATH} --target=${GFU_GRUB_EFI_X32} ${GFU_DEVICE}
        ${GFU_GRUB_EFI_MODE_X64} && grub-install --removable --boot-directory=${GFU_MOUNT_PATH}/boot --efi-directory=${GFU_MOUNT_PATH} --target=${GFU_GRUB_EFI_X64} ${GFU_DEVICE}
    fi

    if [ -d ${SCRIPT_PATH}/grub ] ; then
        cp -rv ${SCRIPT_PATH}/grub ${GFU_MOUNT_PATH}/boot
    else
        touch ${GFU_MOUNT_PATH}/boot/grub/grub.cfg
    fi

    umount -v ${GFU_DEVICE}1
}

main "${@}"
