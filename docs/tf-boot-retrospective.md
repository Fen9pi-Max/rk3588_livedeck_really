# TF 卡启动系统全程复盘

> 2026-11-18,一晚完成。参考 [gedulab/ylboot](https://github.com/gedulab/ylboot)(幽兰 CodeBook,RK3588)
> 的"TF 卡纯系统盘"思路,为 TV2340R 实现 TF 卡启动 Armbian。
> 全程含一次 loader 误刷变砖、一次串口适配器硬件级卡死、一次 Maskrom 恢复,
> 以及一个贯穿数周的误判(`-110` 的真实含义)在本晚被纠正。
> 配套阅读:`docs/community-bootchain-plan.md`(社区链规划)、`docs/community-chain-evidence.md`(证据链)。

---

## 〇、一页摘要

| 项 | 内容 |
|---|---|
| 目标 | 拔 eMMC 依赖:插 TF 卡即从 TF 启动完整系统,拔卡回落 eMMC,引导链解耦 |
| 参考思路 | ylboot:bootloader 固化内部存储(幽兰=SPI NOR),TF 卡只放系统(内核分区+rootfs),U-Boot 优先扫 TF |
| 本机架构 | U-Boot 固化 **eMMC LBA64**(Armbian 框架构建);TF 卡单分区 ext4 完整系统 + `/boot/extlinux/extlinux.conf`;`boot_targets=mmc1 mmc0…` TF 优先、无卡自动回落 eMMC |
| 关键硬件事实 | TF 卡槽 3.3V 由 **GPIO4_C3 门控**(原厂 DTS `vcc_sd` regulator-fixed,高有效,上电延时 100ms)。vccio 由 RK806 PLDO5 提供 |
| 结果 | ✅ 插卡冷启动:`mmc1` 枚举 SanDisk 64G → TF extlinux → 内核/initrd/dtb 全部从 TF 加载 → `root=UUID(TF)` → 系统 `really-tf`,`/`=/dev/mmcblk1p1。✅ 拔卡:回落 eMMC `really` 不受影响 |
| 最大弯路 | 误判 `-110`(voltage select 超时)为"TF 供电从未生效"→ 刷入未经硬件验证的 `out2026` 新构建 → **SPL 死于 FIT 校验后,整机变砖** → Maskrom 恢复 |
| 真相 | 线上一直运行的 Armbian 构建 loader **本来就支持 TF 启动**(vcc_sd 带 `regulator-always-on` + `DM_REGULATOR_FIXED=y`),历史上的 `-110` 只是**卡槽里没插卡**的正常报错 |
| 教训之最 | ① 未验证的 bootloader 不上生产存储;② 报错≠故障——先穷举"这个报错在什么正常情况下也会出现";③ 变砖可恢复的前提是备份先行(LBA64 备份 + Maskrom 通道当晚都已备好) |

---

## 一、参考架构:ylboot 做了什么,我们映射了什么

分析 `gedulab/ylboot`(Rockchip next-dev 深度定制)得出的核心设计:

| ylboot(幽兰 CodeBook) | TV2340R 适配 |
|---|---|
| U-Boot 固化 SPI NOR(idblock@0,uboot.img@2MB,`dd seek=4096` 更新) | U-Boot 固化 eMMC 用户区 **LBA64**(系统内 `dd seek=64` / Maskrom `rkdeveloptool wl 64`) |
| 自定义 `bootyl` 命令读 TF `ylboot.ini` 或硬编码路径 | 标准主线 distro boot:TF 上 `/boot/extlinux/extlinux.conf` |
| bootdev=nvme 优先,失败最后兜底 TF(救砖通道) | `BOOT_TARGETS="mmc1 mmc0 …"`:**TF(mmc1)优先**,失败回落 eMMC(mmc0) |
| TF p1 内核分区 + p2 rootfs(root=/dev/mmcblk1p2) | TF 单分区 ext4(rootfs 含 /boot),`root=UUID=<TF分区>` |
| TF 供电:RK806 双 PMIC 的 `vccio_sd_s0`/`vcc_3v3_sd_s0` | TF 供电:`vcc_sd` = regulator-fixed **GPIO4_C3** |

解耦的本质两边一致:**TF 卡上没有任何 bootloader**,换卡只要求文件布局符合约定;
U-Boot 升级/回滚完全不碰 TF 卡,拔卡即回内部盘。

## 二、最终验证:如何证明"确实从 TF 启动"

五重独立证据(缺一不可造假):

```
① /proc/cmdline            → root=UUID=6e9a0dd1-…            (内核被指示从 TF 分区挂根)
② blkid -U 6e9a0dd1…       → /dev/mmcblk1p1                  (该 UUID 确属 TF 分区)
③ findmnt /                → /dev/mmcblk1p1, 58.2G           (运行时事实;eMMC 根是 113G)
④ /sys/block/mmcblk1       → type=SD, name=SN64G             (物理层:mmcblk1=SanDisk TF 卡)
⑤ hostname                 → really-tf                       (TF 副本专用名;eMMC 副本叫 really)
```

外加启动时刻串口证据:

```
Scanning bootdev 'mmc@fe2c0000.bootdev':        ← fe2c0000 = TF 控制器(U-Boot mmc1)
  1  extlinux  ready  mmc 1  /boot/extlinux/extlinux.conf
1:  Armbian edge 7.3.4-edge-rockchip64 (TF)
Retrieving file: /boot/vmlinuz-7.3.4-edge-rockchip64   ← 内核/initrd 均从 TF 读取
```

日常最快判别:看主机名 `really-tf`(TF)/`really`(eMMC)。

## 三、时间线(均为当晚,关键节点附证据)

| 时刻 | 事件 | 证据/后果 |
|---|---|---|
| ~21:00 | 分析 ylboot 完成;梳理社区链现状(线上 loader md5 `5cec58…` 与本地三份产物都不符) | `community-chain/loader-backups/` |
| ~21:46 | TF 卡插入盒子,主线内核下 SDR104 正常识别(`mmc1: new UHS-I … SN64G`) | dmesg @13188s |
| ~21:50 | 发现运行时内核 DTB 已含 vcc_sd GPIO;社区 U-Boot 树早有 `rk3588-really.dts` 但从未部署 | `/sys/firmware/fdt` 反编译 |
| ~21:55 | 备份线上 loader(LBA64 8MB)→ 上传 `out2026/u-boot-rockchip.bin` | md5 回读一致 |
| ~22:00 | 就地制作 TF 卡(rsync 运行系统→mmcblk1,fstab/hostname/extlinux 适配) | TF UUID `6e9a0dd1…` |
| 22:04 | 刷入 out2026 loader → 重启 → **变砖**(无网络/串口静默/非 Maskrom) | 串口后补:FIT hash 全过 → 一条 -110 → 死 |
| 22:16 | 冷启动捕获失败(自研脚本 bug);诊断出 **CH340 TX 卡死**(TIOCOUTQ=4160 不下降) | USB unbind/bind 恢复 |
| ~22:25 | serialweb 修复会话接管串口;拿到 22:04 完整日志,确认 out2026 SPL 死点 | SPL banner 后无 BL31 输出 |
| ~22:30 | 对比成功链日志(Armbian loader 同样有 -110×4 但**非致命**)→ 认知纠偏 | 串口日志 L13065712 |
| ~22:32 | 定位线上 loader 来源:armbian-tv2340r 框架构建(`u-boot-really/v2026.07`,含 vcc_sd always-on + DM_REGULATOR_FIXED) | md5 `cef7beba…` 前 8MB = 线上 |
| ~22:33 | **Maskrom 恢复**(BOOT 键+上电,rkdeveloptool wl 64) | 写入 100%,reset |
| 22:34 | U-Boot 提示符实测:`mmc dev 1` 枚举 64G TF 成功、`ls mmc 1:1` 可读 ext4 | 无 -110 |
| 22:36 | `boot` → TF extlinux → 内核起来 → **`really-tf login:`** → SSH 验证五重证据全过 | `/`=mmcblk1p1 |

## 四、根因分析:`-110` 的三种含义(本次的核心纠偏)

`Card did not respond to voltage select! : -110`(dw_mmc 驱动)在本机出现过三种场景:

| 场景 | 含义 | 致命性 |
|---|---|---|
| A. TF 槽无卡 | 正常报错,boot_targets 继续扫下一介质 | 无(成功链每次启动都有,×4) |
| B. 有卡但 vcc_sd 未驱动(rock5b DTB vmmc=常开假 regulator) | 真·供电缺失 | 影响仅 TF,回落 eMMC |
| C. out2026 SPL 在 FIT 校验后打印一条即死 | 与 TF 无关的巧合伴生症状 | **致命**(该 SPL 本身坏) |

前期把 A/B/C 混为一谈,统一解读成"B:供电 bug",于是得出"必须换 loader"的错误结论。
正确姿势:**先证明"插卡 + 线上 loader"这个最小组合的行为**——当晚在 U-Boot 提示符下
`mmc dev 1` 一条命令即可证伪"B 假设"(线上 loader 下 TF 枚举正常),而这一步本应是第一步。

## 五、变砖事故与恢复(复盘重点)

**事故**:22:04 将 `out2026/u-boot-rockchip.bin`(ub2026 树构建,从未上过硬件)直接 dd 到 eMMC LBA64。
**现象**:SPL banner → "trying to boot from mmc1" → FIT hash 全部 OK → 一条 -110 → 死。
无 BL31 输出(成功链 BL31 v1.48 有大量 INFO 输出)、无 U-Boot banner、无网络、非 Maskrom。

**差异定位**(与线上 Armbian 构建逐项对比):
- BL31:out2026 用 rkbin `v1.56`(FIT 内 atf-1+tee-1);Armbian 构建 FIT 内 **atf-1/2/3**(BL31 v1.48, 2024-12-19)
- 源树:ub2026(7 月状态克隆)vs armbian v2026.07 工作树(带 Armbian 补丁集)
- 死因未深究,但结论明确:**该产物废弃,永远不再刷**

**恢复**(22:33,全程 3 分钟):
```
# 按住 BOOT 键上电进 Maskrom(USB 2207:350b)
rkdeveloptool boot MiniLoaderAll-DC_Y588.bin
rkdeveloptool wl 64 u-boot-rockchip.bin   # Armbian 树完整产物
rkdeveloptool reset
```

**暴露的流程缺陷**:刷 loader 前未回答"这个构建在任何硬件上成功启动过吗"。
当晚线上 loader 的来源(armbian 框架构建)都没有被先识别出来——它才是经过验证的基线。

## 六、串口基础设施事故

1. **CH340 硬件级卡死**:内核 TX 缓冲 4160 字节永不下降(`ioctl TIOCOUTQ` 验证),
   写入"成功"但字节从未上线,表象为"盒子串口静默"——极易误判为盒子死机。
   恢复:USB unbind/bind(重新枚举为 ttyUSB1)。
   *教训:串口静默 ≠ 盒子死机,先验证适配器 TX 排空。*
2. **serialweb 多实例互踩**(由修复会话定位):旧版"先开串口后绑端口",僵尸实例抢 RX + 喷 Ctrl+C 洪水。
   修复后单实例 + HTTP API(`/send` `/stream` `/spam/*`),日志 `/data/ruili/tmp/serial_boot.log`。
   *本会话教训:禁止绕过服务直开 tty,多读者分抢 RX 字节。*

## 七、教训清单

1. **未验证的 bootloader 不进生产存储**——刷之前必须知道它至少在哪儿成功启动过一次。
2. **报错 ≠ 故障**:拿到报错先穷举"什么正常路径也会产生它"(A 场景的 -110 无处不在)。
3. **最小复现优先**:"插卡 + 线上 loader + `mmc dev 1`"是一条命令的实验,却排在最后;应排第一。
4. **备份与恢复通道先行**:LBA64 备份、Maskrom 流程、MiniLoader 都是当晚之前就位的,变砖后 3 分钟恢复——没有这些,这次事故就是灾难。
5. **双盲调试最贵**:串口(唯一观测通道)和盒子同时"失联"时,先修观测工具(CH340),再修目标。
6. **产物要有唯一可信来源**:同一功能三份产物(out/、out2026、armbian 树)+ 线上第四份,版本管理失控是事故温床。

## 八、遗留问题

- `out2026` SPL 死因(BL31 v1.56 兼容性?FIT atf 结构?)未深究,产物已废弃;
- 社区树 `really-rk3588_defconfig` 链接失败(`ft_system_setup` 未定义),与 ub2026/Armbian 树的配置差异未整理;
- 盒子上 sfdisk 建 GPT 分区报 `EINVAL`(只能用 MBR/dos),原因未查,不影响使用;
- U-Boot 阶段 TF 仅 High Speed 50MHz(内核下 SDR104 正常),引导加载 ~40MB 需数秒,可接受;
- eMMC 与 TF 两份系统同源(SSH 主机密钥相同),插拔切换时 known_hosts 不冲突但需注意身份区分。

## 九、产物清单

| 产物 | 位置 |
|---|---|
| 验证过的 loader(唯一可信来源) | `armbian-build/cache/sources/u-boot-worktree/u-boot-really/v2026.07/u-boot-rockchip.bin` |
| TF 卡制作脚本(盒子上运行) | `scripts/mk-tf-card-phase2.sh`(本仓库) |
| 运维手册(布局/部署/回滚) | `community-chain/TF-BOOT.md`(另册,含废弃构建标记) |
| 变砖前线上 loader 备份(8MB 截断) | `community-chain/loader-backups/loader-online-lba64-20261118.img` |
| Maskrom 恢复用 MiniLoader | `RK3588-TV2340R-Android12-Native-v1.1/MiniLoaderAll-DC_Y588.bin` |
