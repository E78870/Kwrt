#!/bin/sh
# 用法: sh /root/set-pppoe.sh <主账号> <主密码> [副账号] [副密码]
[ -n "$1" ] && [ -n "$2" ] || { echo "用法: $0 主账号 主密码 [副账号 副密码]"; exit 1; }
uci set network.wan.username="$1"; uci set network.wan.password="$2"
[ -n "$3" ] && { uci set network.wanb.username="$3"; uci set network.wanb.password="$4"; }
uci commit network
ifup wan >/dev/null 2>&1; [ -n "$3" ] && ifup wanb >/dev/null 2>&1
echo "已写入并重拨；用 ifstatus wan / ifstatus wanb 查看状态"
