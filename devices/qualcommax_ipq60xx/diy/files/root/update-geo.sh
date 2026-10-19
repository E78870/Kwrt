#!/bin/sh
# 下载/更新 Loyalsoldier 增强版 geosite/geoip 到 overlay（不占 squashfs）
set -u
D=/usr/share/v2ray
mkdir -p $D
ping -c1 -W3 223.5.5.5 >/dev/null 2>&1 || { echo "无外网"; exit 1; }
for f in geosite.dat geoip.dat; do
    wget -q -O "$D/$f.new" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/$f" \
        && mv -f "$D/$f.new" "$D/$f" && echo "✓ $f $(du -h $D/$f | cut -f1)" \
        || { rm -f "$D/$f.new"; echo "✗ $f 失败"; }
done
df -h /overlay | tail -1
/etc/init.d/daed restart 2>/dev/null; /etc/init.d/dae restart 2>/dev/null
