#!/bin/bash

shopt -s extglob

SHELL_FOLDER=$(dirname $(readlink -f "$0"))

rm -rf package/boot package/firmware/ipq-wifi target/linux/generic target/linux/qualcommax package/firmware/ath11k-firmware package/kernel/mac80211 package/kernel/nat46

git_clone_path 25.12-nss https://github.com/LiBwrt/openwrt-6.x target/linux/generic target/linux/qualcommax package/boot package/firmware/ipq-wifi package/firmware/ath11k-firmware package/kernel/mac80211 package/kernel/nat46

wget -N https://github.com/LiBwrt/LibWrt/raw/refs/heads/25.12-nss/include/image-commands.mk -P include/
wget -N https://github.com/LiBwrt/LibWrt/raw/refs/heads/25.12-nss/config/Config-ipq.in -P config/
wget -N https://github.com/LiBwrt/LibWrt/raw/refs/heads/25.12-nss/Config.in -P ./

rm -rf feeds/kiddin9/shortcut-fe

git clone https://github.com/qosmio/nss-packages.git package/nss-packages
git clone https://github.com/qosmio/sqm-scripts-nss.git package/sqm-scripts-nss

sed -i "/ECM_INTERFACE_RAWIP_ENABLE/d"  package/nss-packages/qca-nss-ecm/Makefile
rm -rf package/nss-packages/nss-userspace-oss

sed -i "s/luci uboot-envtools wpad-openssl/luci uboot-envtools wpad-mbedtls/" target/linux/qualcommax/Makefile

# --- 预装 mwan4（nftables 版 mwan3；官方只发 ipk，这里从源码编进固件）---
git clone --depth 1 https://github.com/mossdef-org/mwan4.git package/mwan4 || true

# geo 数据（geosite/geoip）不编入固件：更新极频繁（每日），改由 /root/update-geo.sh 下载到 overlay

# --- subconverter（用户指定的 asdlokj1qpi233 fork，静态链接 aarch64）---
SC_VER=v0.9.9
mkdir -p diy/files/opt
wget -q -O /tmp/sc.tgz "https://github.com/asdlokj1qpi233/subconverter/releases/download/${SC_VER}/subconverter_aarch64.tar.gz" && \
  tar xzf /tmp/sc.tgz -C diy/files/opt/ && ls -lh diy/files/opt/subconverter/ | head -5 || echo "subconverter 下载失败"
