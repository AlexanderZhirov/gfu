# GRUB for USB

```sh
#!/bin/bash

disk="${1}"

parted ${disk} -s mklabel gpt
parted ${disk} -s -- mkpart primary 2048s 2099199s
parted ${disk} -s -- mkpart primary 2099200s 40G
parted ${disk} -s -- mkpart primary 40G 100%

parted ${disk} -s set 1 boot on

mkfs.fat -F32 ${disk}1
mkfs.ext4 -F ${disk}2

mount -v -o umask=000 ${disk}1 /mnt

grub-install --removable --boot-directory=/mnt/boot --efi-directory=/mnt --target=x86_64-efi ${disk}
grub-install --removable --boot-directory=/mnt/boot --efi-directory=/mnt --target=i386-efi ${disk}

touch /mnt/boot/grub/grub.cfg

umount -v ${disk}1
```
