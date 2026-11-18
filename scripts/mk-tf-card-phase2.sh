#!/bin/bash
# TF 卡制作 第二阶段(分区已完成: mmcblk1p1 MBR 32768..end) — 在盒子上执行
set -e
CARD=/dev/mmcblk1
MNT=/mnt/tfroot
LOG=/tmp/mk-tf-phase2.log
exec > >(tee -a $LOG) 2>&1

[ -b ${CARD}p1 ] || { echo "no p1"; exit 1; }

echo "=== [1/5] mkfs.ext4 ==="
mkfs.ext4 -F -L armbi_tf -m 2 ${CARD}p1

echo "=== [2/5] rsync 运行系统 → TF ==="
mkdir -p $MNT
mount ${CARD}p1 $MNT
rsync -aHAXx --numeric-ids --info=progress2 \
  --exclude=/proc/* --exclude=/sys/* --exclude=/dev/* --exclude=/run/* \
  --exclude=/tmp/* --exclude=/mnt/* --exclude=/media/* --exclude=/lost+found \
  / $MNT

echo "=== [3/5] fstab / hostname ==="
TFUUID=$(blkid -s UUID -o value ${CARD}p1)
echo "TF root UUID=$TFUUID"
sed -i "s|^UUID=[0-9a-f-]*[[:space:]]*/ |UUID=$TFUUID / |" $MNT/etc/fstab
grep -q "$TFUUID" $MNT/etc/fstab || echo "UUID=$TFUUID / ext4 defaults,errors=remount-ro,commit=15 0 1" >> $MNT/etc/fstab
grep " / " $MNT/etc/fstab
echo really-tf > $MNT/etc/hostname
sed -i 's/really-tf\b/really-tf/; s/127\.0\.1\.1.*/127.0.1.1\treally-tf/' $MNT/etc/hosts

echo "=== [4/5] extlinux.conf(仅 TF) ==="
KVER=7.3.4-edge-rockchip64
mkdir -p $MNT/boot/extlinux
cat > $MNT/boot/extlinux/extlinux.conf <<EOF
default tf
menu title Armbian TF boot (TV2340R)
prompt 0
timeout 30

label tf
    menu label Armbian edge ${KVER} (TF)
    linux /boot/vmlinuz-${KVER}
    initrd /boot/initrd.img-${KVER}
    fdt /boot/dtb-${KVER}/rockchip/rk3588-really.dtb
    append root=UUID=${TFUUID} rootwait rootfstype=ext4 console=ttyS2,1500000 console=tty1 consoleblank=0 loglevel=7 usb-storage.quirks=0x2537:0x1066:u,0x2537:0x1068:u pcie_aspm=off cma=512M cfg80211.ieee80211_regdom=CN fbcon=rotate:3 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory
EOF
cat $MNT/boot/extlinux/extlinux.conf | head -5

echo "=== [5/5] 校验卸载 ==="
sync
du -sh $MNT
# 确认内核三件套都在
ls -la $MNT/boot/vmlinuz-${KVER} $MNT/boot/initrd.img-${KVER} $MNT/boot/dtb-${KVER}/rockchip/rk3588-really.dtb
umount $MNT
sync
echo "[OK] TF 卡就绪 root UUID=$TFUUID"
