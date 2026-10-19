# router-bundle —— Router_experiment 一键整合包

针对 **Kwrt 25.12-SNAPSHOT / qualcommax / ipq60xx / zn_m2**（内核 6.12.108 + **BTF** + **NETKIT**）的一套整合安装方案。

> ✅ 已在本机的 **10.18.2026** 固件上确认：`/sys/kernel/btf/vmlinux` 存在（3.85 MB），`CONFIG_NETKIT=y`

## 一、包含什么

| 组件 | 版本 | 来源 | 作用 |
|---|---|---|---|
| `pbr` + `luci-app-pbr` | 1.2.2-r20 | Kwrt 源（packages/luci） | 策略路由（按域名/客户端选出口） |
| `mwan4` | 0.1.1-r4 | 官方 ipk（`pkgs/` 内已带） | **多线负载均衡/故障切换（nftables 版 mwan3）** |
| `dae` + `daed` + `luci-app-daede` | 最新 | [kenzok8/openwrt-daede](https://github.com/kenzok8/openwrt-daede) | 内核态透明代理（PGO 优化版）+ Web 面板 |
| `subconverter` | 0.9.0 | Kwrt 源（kiddin9） | **本地订阅转换（C++ 静态二进制，不需要 node/docker）** |
| `conntrack`、`ip-full` | — | Kwrt 源 | mwan4/pbr 的依赖 |

配套配置文件：

- `files/config.dae` —— 完整分流规则（对齐 ACL4SSR Full 的覆盖面 + dae 原生分组）
- `install.sh` —— 一键安装 + 写配置

## 二、网络规划（本包写入的内容）

| 逻辑接口 | 物理口 | 协议 | 账号 | mwan4 权重 |
|---|---|---|---|---|
| `lan` | br-lan（lan2 + lan3） | static | — | — |
| `wan` | **wan** | PPPoE | 主账号 / 主密码（脚本内由环境变量传入） | **3（主）** |
| `wanb` | **lan1**（从 br-lan 摘出） | PPPoE | 副账号 / 副密码（脚本内由环境变量传入） | **2（副）** |

- LAN 地址：**192.168.1.3/24**
- 负载均衡策略：`balanced` = `wan_m1_w3`(w3) + `wanb_m1_w2`(w2) → **3:2**

## 三、fwmark 分配（关键，别撞车）

| 组件 | 位段 | 值 |
|---|---|---|
| **mwan4** | bit8–13 | `0x3F00` |
| **pbr** | bit16–23 | `0x00ff0000` |
| **dae/daed** | bit26 | `0x04000000` ← `config.dae` 已设 |
| 旧 mwan3 | bit8–13 | `0x3F00`（与 mwan4 相同，故二者互斥） |

> 所以 **mwan4 与 pbr 可共存**；**dae 必须把 `so_mark_from_dae` 改成 `0x04000000`**，否则它的出站 socket 会被 mwan4 误判。

## 四、安装

前提：路由器已能上网（WAN 已通）。

```sh
wget -O /tmp/bundle.sh https://raw.githubusercontent.com/E78870/Kwrt/25.12/router-bundle/install.sh
sh /tmp/bundle.sh
```

脚本会依次：备份 `/etc/config` → opkg 装 pbr/subconverter/依赖 → 装 mwan4 → 装 kenzok8 daede → 写 network（lan1 出 br-lan、双 PPPoE）→ 写 mwan4（3:2）→ 写 daed 配置 → 重启服务并打印状态。

**注意**：把 wan 改成 PPPoE 后，脚本会重启网络，SSH 会断几秒。

## 五、装完之后必须做的一件事：填订阅

```sh
vi /etc/dae/config.dae     # subscription { my_sub: 'https://你的订阅' }
/etc/init.d/daed restart
```

或者用 daed 面板（`http://192.168.1.3:2023`）导入订阅 —— daed 的 UI 支持直接从订阅链接导入节点。

**建议先改面板默认口令**（默认 `daed/daed`），或把监听改为 `127.0.0.1:2023` 走 SSH 隧道。

## 六、本地订阅转换（subconverter）

装好后监听 `127.0.0.1:25500`（默认），可把任意订阅转成 dae/clash 等格式：

```sh
# 例：把机场订阅转成 clash 格式
curl "http://127.0.0.1:25500/sub?target=clash&url=<你的订阅URL编码>"
```

- **不需要 node / docker**，是单个 C++ 静态二进制（几 MB），装进 `/overlay`（62 MB 可用）绰绰有余
- 配置在 `/etc/subconverter/`
- 若你更想用 `sub-store`：**不行**，它依赖 node（本机没装也不建议装）

## 七、验证清单

```sh
# 1. 双拨是否都拨上
ifstatus wan  | grep -E '"(up|address)"'
ifstatus wanb | grep -E '"(up|address)"'

# 2. mwan4 是否接管
mwan4 status
ip rule | head
nft list ruleset | grep -c mwan4

# 3. pbr
/etc/init.d/pbr status
nft list table inet fw4 | grep -c pbr_

# 4. dae/daed
ls -l /sys/kernel/btf/vmlinux          # 必须存在
tail -n 30 /var/log/daed/daed.log      # 不应有 "no BTF found" / "falling back to veth"
dae validate -c /etc/dae/config.dae    # 若装了 dae 命令行

# 5. 分流抽查（应该在各自出口）
curl -s https://ipinfo.io/ip                       # 走代理
curl -s --resolve ipinfo.io:443:<国内IP> ...        # 略
```

## 八、回滚

```sh
ls -d /root/backup-*        # 找到最近一次
cp /root/backup-XXXX/network /etc/config/network
cp /root/backup-XXXX/mwan4   /etc/config/mwan4 2>/dev/null
/etc/init.d/network restart
```

彻底回滚：卸载 `mwan4 pbr luci-app-pbr daed luci-app-daede dae subconverter`，恢复 `/etc/config/network`。

## 九、已知取舍

1. **mwan4 没有官方 LuCI** —— 只有 `mwan4` CLI + `/etc/config/mwan4`。第三方 `brauliobo/luci-app-mwan4`（★2）可选但非官方。
2. **mwan4 与 mwan3 互斥**（`Conflicts: mwan3`）。
3. **dae 的 geosite 标签写错会导致启动失败** —— `config.dae` 里已把不常用的标签注释掉，按需打开。
4. **kenzok8 的包未包含在固件里**，是刷完后在线安装（它的包版本号比 Kwrt 的低，预装会阻止安装）。
