#!/bin/sh
# ============================================================================
# Router_experiment 整合包安装脚本
# 目标固件：Kwrt 25.12-SNAPSHOT (qualcommax/ipq60xx, zn_m2)，内核 6.12.108 + BTF + NETKIT
# 内容：pbr + luci-app-pbr + mwan4 + subconverter + kenzok8 dae/daed/luci-app-daede
#      + 网络配置（LAN 192.168.1.3 / lan1=wanb / 双 PPPoE）
#      + mwan4 3:2 负载均衡
#
# 用法（在路由器上执行）：
#   wget -O - https://raw.githubusercontent.com/E78870/Kwrt/25.12/router-bundle/install.sh | sh
# 或者下载后：
#   sh install.sh
#
# 说明：
#   * 幂等：可重复执行
#   * 会先备份 /etc/config/{network,mwan4,daed} 到 /root/backup-<时间戳>/
#   * 修改 wan 为 PPPoE 后网络会短暂中断（脚本末尾会自动重连）
# ============================================================================
set -u

REPO_RAW="https://raw.githubusercontent.com/E78870/Kwrt/25.12/router-bundle"
MWAN4_IPK="pkgs/mwan4-0.1.1-4_openwrt-24.10_aarch64_cortex-a53.ipk"

# ---------- 参数（用环境变量传入，仓库里不写明文账号）----------
WAN_USER="${WAN_USER:-}"      # 主 WAN（mwan4 权重 3）
WAN_PASS="${WAN_PASS:-}"
WANB_USER="${WANB_USER:-}"    # 副 WAN（mwan4 权重 2）
WANB_PASS="${WANB_PASS:-}"
LAN_IP="${LAN_IP:-192.168.1.3}"
WANB_DEV="${WANB_DEV:-lan1}"
# ---------------------------------------------------------------

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[x]\033[0m $*"; exit 1; }

[ "$(id -u)" = "0" ] || die "请用 root 运行"

if [ -z "$WAN_USER" ] || [ -z "$WAN_PASS" ] || [ -z "$WANB_USER" ] || [ -z "$WANB_PASS" ]; then
    cat <<'EOT'
用法（先在 shell 里导出 PPPoE 账号，再运行本脚本）：

  export WAN_USER='主账号'     # mwan4 权重 3
  export WAN_PASS='主密码'
  export WANB_USER='副账号'    # mwan4 权重 2
  export WANB_PASS='副密码'
  export LAN_IP='192.168.1.3'  # 可选
  export WANB_DEV='lan1'       # 可选，副 WAN 的物理口
  sh install.sh

EOT
    exit 1
fi

# ---------- 0. 联网检查 ----------
log "检查外网连通性…"
if ! ping -c1 -W3 223.5.5.5 >/dev/null 2>&1; then
    warn "当前无法访问外网（WAN 未拨号/未接线）。"
    warn "请先让 wan 口能上网（或先 `ifup wan`），再运行本脚本。"
    exit 1
fi

BK="/root/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BK"
for f in network mwan4 daed dae; do
    [ -f "/etc/config/$f" ] && cp -f "/etc/config/$f" "$BK/" 2>/dev/null
done
log "配置已备份到 $BK"

# ---------- 1. opkg 依赖 + pbr ----------
log "opkg update"
opkg update >/dev/null 2>&1 || warn "opkg update 有告警（可忽略）"

log "安装 pbr / luci-app-pbr / 依赖 / subconverter"
# subconverter: C++ 静态二进制，无需 node/docker（来自 kiddin9 源）
opkg install pbr luci-app-pbr conntrack ip-full subconverter 2>&1 | tail -5

# ---------- 2. mwan4 ----------
log "安装 mwan4"
if opkg list-installed 2>/dev/null | grep -q '^mwan4 '; then
    log "mwan4 已安装，跳过"
else
    TMP="$(mktemp -d)"
    if wget -q -O "$TMP/mwan4.ipk" "$REPO_RAW/$MWAN4_IPK"; then
        opkg install "$TMP/mwan4.ipk" 2>&1 | tail -3
    else
        warn "下载 mwan4 ipk 失败；请手动下载后 opkg install"
    fi
    rm -rf "$TMP"
fi
# mwan4 与 mwan3 互斥
if opkg list-installed 2>/dev/null | grep -q '^mwan3 '; then
    warn "检测到 mwan3，与 mwan4 冲突：请先 opkg remove mwan3 luci-app-mwan3"
fi

# ---------- 3. kenzok8 daede（dae + daed + luci-app-daede）----------
log "安装 kenzok8 优化版 daede"
if opkg list-installed 2>/dev/null | grep -q '^luci-app-daede '; then
    log "luci-app-daede 已安装，跳过"
else
    wget -q -O - https://raw.githubusercontent.com/kenzok8/openwrt-daede/refs/heads/main/scripts/install.sh | sh 2>&1 | tail -8
fi

# ---------- 4. 网络配置 ----------
log "配置网络：LAN=$LAN_IP / $WANB_DEV→wanb / 双 PPPoE"

# 4.1 把 lan1 从 br-lan 摘出去
IDX=0
while uci -q get "network.@device[$IDX]" >/dev/null 2>&1; do
    if [ "$(uci -q get network.@device[$IDX].name)" = "br-lan" ]; then
        uci -q del_list "network.@device[$IDX].ports=$WANB_DEV" || true
    fi
    IDX=$((IDX+1))
done

# 4.2 LAN 地址
uci set network.lan.ipaddr="$LAN_IP/24"
uci set network.lan.proto='static'

# 4.3 主 WAN：wan 口 PPPoE
uci set network.wan.device='wan'
uci set network.wan.proto='pppoe'
uci set network.wan.username="$WAN_USER"
uci set network.wan.password="$WAN_PASS"
uci set network.wan.ipv6='1'
uci set network.wan.keepalive='10 3'
uci set network.wan.metric='10'

# 4.4 副 WAN：lan1 PPPoE
uci set network.wanb='interface'
uci set network.wanb.device="$WANB_DEV"
uci set network.wanb.proto='pppoe'
uci set network.wanb.username="$WANB_USER"
uci set network.wanb.password="$WANB_PASS"
uci set network.wanb.ipv6='1'
uci set network.wanb.keepalive='10 3'
uci set network.wanb.metric='20'

# 4.5 wan6 跟随 wan（PPPoE 的 IPv6 由 ppp 自动处理，删掉原来的 dhcpv6）
uci -q delete network.wan6 || true

uci commit network
log "network 已写入"

# ---------- 5. mwan4 配置（3:2，主=wan）----------
log "写入 mwan4 配置（balanced 3:2）"
cat > /etc/config/mwan4 <<'EOF'
config globals 'globals'
	option mmx_mask '0x3F00'

config interface 'wan'
	option enabled '1'
	list track_ip '223.5.5.5'
	list track_ip '119.29.29.29'
	list family 'ipv4'
	option reliability '2'
	option timeout '4'
	option interval '10'
	option down '3'
	option up '3'

config interface 'wanb'
	option enabled '1'
	list track_ip '223.5.5.5'
	list track_ip '119.29.29.29'
	list family 'ipv4'
	option reliability '1'
	option timeout '4'
	option interval '10'
	option down '3'
	option up '3'

# 权重 3 : 2（主 WAN 权重 3）
config route 'wan_m1_w3'
	option interface 'wan'
	option metric '1'
	option weight '3'

config route 'wanb_m1_w2'
	option interface 'wanb'
	option metric '1'
	option weight '2'

config strategy 'balanced'
	list use_route 'wan_m1_w3'
	list use_route 'wanb_m1_w2'

config rule 'default_rule_v4'
	option dest_ip '0.0.0.0/0'
	option use_strategy 'balanced'
	list family 'ipv4'
EOF

# ---------- 6. daed 配置 ----------
log "写入 daed 配置"
if [ -f /etc/config/daed ]; then
    uci set daed.config.enabled='1'
    uci set daed.config.listen_addr='0.0.0.0:2023'
    uci set daed.config.subscribe_auto_update='1'
    uci commit daed
else
    cat > /etc/config/daed <<'EOF'
config daed 'config'
	option enabled '1'
	option listen_addr '0.0.0.0:2023'
	option log_maxbackups '1'
	option log_maxsize '5'
	option subscribe_auto_update '1'
	option subscribe_update_cycle 'daily'
	option subscribe_update_hour '4'
EOF
fi

# dae 后端的分流规则（模板，需自己填订阅）
mkdir -p /etc/dae
if [ ! -f /etc/dae/config.dae ]; then
    if wget -q -O /etc/dae/config.dae "$REPO_RAW/files/config.dae"; then
        log "已放置 /etc/dae/config.dae（记得填订阅链接）"
    else
        warn "下载 config.dae 失败"
    fi
fi

# ---------- 7. 重启服务 ----------
log "重启网络与相关服务"
/etc/init.d/network restart >/dev/null 2>&1
sleep 6
/etc/init.d/mwan4 enable 2>/dev/null; /etc/init.d/mwan4 restart 2>/dev/null
/etc/init.d/pbr enable 2>/dev/null;   /etc/init.d/pbr restart 2>/dev/null
/etc/init.d/daed enable 2>/dev/null;  /etc/init.d/daed restart 2>/dev/null

sleep 4
echo
log "===== 结果 ====="
echo "PPPoE 状态："
ifstatus wan  | grep -E '"(up|address|proto)"' | head -5
ifstatus wanb | grep -E '"(up|address|proto)"' | head -5
echo
echo "mwan4 状态："
mwan4 status 2>&1 | head -20
echo
echo "daed："
ps w | grep -c '[d]aed'
echo
echo "刷完请把订阅填进 /etc/dae/config.dae（subscription { ... }），然后 /etc/init.d/daed restart"
echo "备份在：$BK"
