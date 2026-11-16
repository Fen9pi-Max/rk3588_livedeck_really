# Really TF 卡写入验收记录 — community 启动链

- 执行时间：2026-11-16 19:38 — 20:05
- 构建机：`192.168.3.28`（skysi-x5），`/home/user/github/build`
- 目标介质：`/dev/mmcblk1`，59.4 GiB，整卡覆盖
- 状态：**镜像已写入并回读校验通过；2026-11-16 23:48 已通过冷启动验证。**

> **后续闭环：** 更新到 U-Boot `-P743c` 后，设备冷启动成功，
> Linux 从 `/dev/mmcblk1p1` 挂载 ext4 根文件系统，UUID 为
> `7faf7863-d5d5-419e-81bd-902914de6883`。下面保留写入阶段的历史记录。

---

## 一、背景：本次写入改变了引导方式

此前的验收卡（11-14 构建）用的是**原厂启动链**方案：把 16 MiB 厂商
IDB/SPL/U-Boot FIT 手术式塞进 SD 卡 LBA64 起，靠原厂 U-Boot 2017.09
的 `distro_bootcmd` 启动 Armbian。

提交 `05c27bd3c`（`really: drop the factory boot chain, community U-Boot only`）
移除了 `REALLY_COMMUNITY_UBOOT` 开关和 `REALLY_VENDOR_BOOT_CHAIN` 路径，
连带删除整个 `post_build_image_modify()`，其中包括：

- 16 MiB 厂商链的 dd 注入与 IDB/FIT 魔数校验
- `LegacyBIOSBootable` GPT 属性设置（只为原厂 U-Boot 的
  `part list -bootable` 服务）

现在镜像走纯 community 链：
`BootROM -> 上游 SPL/U-Boot v2026.07 (binman) -> Armbian`。

---

## 二、构建

```bash
./compile.sh really
```

| 项 | 值 |
|---|---|
| 分支 | `edge`（Linux 7.3.4 mainline） |
| Release | resolute 26.04 |
| 桌面 | GNOME minimal |
| 启动链 | community（binman） |
| 耗时 | 7 分 10 秒 |

产物：

```text
output/images/Armbian-unofficial_26.11.0-trunk_Really_resolute_edge_7.3.4_gnome_desktop.img
大小    7864320000 字节
SHA256  d27384d5f7bb0b6f775469b44b3a50d289045a879f63126cc531acbcc16fde1a
```

### 2.1 构建期网络问题

首次构建失败于 `raw.githubusercontent.com` 不可达（构建机网络限制），
停在 `artifact_uboot_prepare_version` 的 Makefile 拉取阶段。
加镜像变量后通过：

```bash
GITHUB_MIRROR=ghproxy GHPROXY_ADDRESS=gh-proxy.com ./compile.sh really
```

配置本身无问题；`BOARD=really` 命令行形式会跳过 `config-really.conf`
的完整加载，因此该文件里的镜像设置未生效。正常交互构建不受影响。

---

## 三、写卡前校验

| 检查项 | 结果 |
|---|---|
| LBA64 魔数 | `534e4b52`（RKNS，**正常**） |
| LBA16384 | `edfe0dd0`（U-Boot FIT，binman 布局正确） |
| 引导区 U-Boot 版本 | `U-Boot SPL 2026.07_armbian-2026.07-Sece3-P56fc-Hae08-V6f98-Bd800-R448a` |
| 原厂 2017.09 残留 | **0 命中** |
| 分区表 | GPT，p1 `start=32768 size=15325184` rootfs |
| `fdtfile` | `rockchip/rk3588-really.dtb` |
| `rootdev` | `UUID=7faf7863-...`（与分区一致） |
| DTB 内容 | `compatible = "rockchip,rk3588-tvi2340r"` 正确 |
| `snps_hdmirx` | 已内建进 `vmlinuz`（`CONFIG_VIDEO_SYNOPSYS_HDMIRX=y`，非 .ko） |

**关于 `534e4b52` 的说明**：这个魔数是 Rockchip 标准 IDB 头（`RKNS`
反序），社区 U-Boot 的 binman 同样会生成它，不能据此判定是否残留原厂链。
真正的判据是引导区内嵌的 U-Boot 版本字符串——已确认是 `2026.07`
（`-P56fc`），不是原厂 `2017.09`。

---

## 四、写入

```bash
sudo dd if=<img> of=/dev/mmcblk1 bs=4M conv=fsync status=progress
sudo sync
```

- 写入量：`7864320000` 字节（1875 个 4 MiB 记录），与镜像大小一致
- 平均速率：约 39 MB/s（eMMC 后段降速）
- 旧卡内容（11-14 原厂链镜像）已被完全覆盖，**不可恢复**
- `/dev/mmcblk0`（115 GiB，另一张卡）未触碰
- NVMe 根分区 `/dev/nvme0n1p1` 全程未受影响

---

## 五、回读校验

| # | 检查项 | 结果 |
|---|---|---|
| 1 | **整盘 SHA256** | `d27384d5f7bb0b6f775469b44b3a50d289045a879f63126cc531acbcc16fde1a` — **与源镜像逐字节一致** |
| 2 | GPT 分区表 | `label-id 23199A7C-...`，p1 与本机镜像一致 |
| 3 | 引导区 U-Boot | `2026.07_armbian-...-P56fc-...`（回读确认） |
| 4 | 原厂 2017.09 残留 | 0 命中 |
| 5 | p1 文件系统 | `ext4`，`LABEL=armbi_root`，`UUID=7faf7863-d5d5-419e-81bd-902914de6883` |
| 6 | 只读挂载 | 成功 |
| 7 | `boot/Image` | 符号链接 → `vmlinuz-7.3.4-edge-rockchip64` |
| 8 | `boot/armbianEnv.txt` | `fdtfile` / `rootdev` 均正确 |
| 9 | DTB 可解析 | `compatible = "rockchip,rk3588-tvi2340r"` |
| 10 | 卡容量 | 63831015424 字节，仅用 7864320000，剩余空间完好 |

**整盘 SHA256 完全一致**是本记录最有力的证据：写入过程无丢字节、无坏块。

---

## 六、未验证项（回去后要做）

### 6.1 TF 冷启动（P0，仍未闭环）

```bash
# 在 Really 实机上：插入本卡，冷启动，抓串口
# 观察点：
#   1. U-Boot 是否打印 2026.07 版本号（而非原厂 2017.09）
#   2. mmc1 是否被 U-Boot 识别
#   3. 是否进入 distro_bootcmd 并从 p1 读 boot.scr
#   4. 内核是否起来、rootfs 是否挂到 UUID=7faf7863
```

U-Boot 侧 SD 供电链修复（`0005`+`0004` 组合，`-P56fc`）已在镜像内，
但 `0004`（SPL 阶段 SDMMC 电源域）此前实测**无效**，真正的修复来自
U-Boot DTS 的 `vqmmc`/`vcc_sd` 电源链恢复。这一条只有在冷启动时才
能被证伪。

### 6.2 已知风险

| 风险 | 说明 |
|---|---|
| 启动验证 | 原记录写入时尚未验证；后续冷启动已验证通过，见文首更新 |
| 首次启动配置 | 需通过 `really-firstrun` 扩展预置的账号首次登录 |
| 触屏 / RTC | 原记录写于 late-bind 阶段；后续 U-Boot GPIO hog + 首次原生 probe 已验证，服务已删除 |
| HDMI OUT | 默认关闭，拔线后 HPD 可能残留 connected |
| Type-C DP | 限 4K30 |
| 面板 HDMI IN | DTS 已 okay，但 device 是否注册未验证 |

### 6.3 如果启动失败

不要急着重写卡。先在 U-Boot 串口阶段确认 `mmc1` 是否 enumerate：

```text
=> mmc list
=> mmc dev 1
=> part list mmc 1
```

若 `mmc dev 1` 失败 → 仍是 SD 供电/时钟问题，回到
`reports/uboot-tf-boot-power-20261116/README.md` 的电源链分析。
若 `mmc dev 1` 成功但 `part list` 为空 → 分区表或 bootable 属性问题
（本次已移除 `LegacyBIOSBootable`，社区 U-Boot 不需要它）。
