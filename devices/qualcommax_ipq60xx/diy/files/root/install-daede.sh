#!/bin/sh
# 在路由器上装 kenzok8 的 dae/daed/luci-app-daede（装到 overlay，不占 squashfs）
# 用法：sh /root/install-daede.sh            # 装 daed（带 Web 面板）
#       sh /root/install-daede.sh dae        # 只装 dae 内核（更省空间）
set -u
[ "$(id -u)" = "0" ] || { echo "需要 root"; exit 1; }
ping -c1 -W3 223.5.5.5 >/dev/null 2>&1 || { echo "当前无外网，先让 wan 拨号"; exit 1; }
opkg update >/dev/null 2>&1
opkg install conntrack ip-full 2>/dev/null
wget -q -O - https://raw.githubusercontent.com/kenzok8/openwrt-daede/refs/heads/main/scripts/install.sh | sh
# 用预置的分流规则
[ -f /etc/dae/config.dae ] && echo "已使用预置校验规则：/etc/dae/config.dae（记得填 subscription）"
uci set daed.config.enabled='1' 2>/dev/null && uci commit daed
/etc/init.d/daed enable 2>/dev/null; /etc/init.d/daed restart 2>/dev/null
echo "完成。面板 http://$(uci -q get network.lan.ipaddr | cut -d/ -f1):2023"
