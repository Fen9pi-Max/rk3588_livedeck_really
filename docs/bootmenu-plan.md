# 启动菜单(Boot Menu)实施方案 — 状态:未实施

> 2026-11-18 立项。参照幽兰 CodeBook 的开机菜单(ylboot `common/osl.c` 的
> `osl_show_bootmenu`:扫描多介质 `ylboot.ini` 段生成菜单项 + MaskROM + U-Boot console,
> 上下键+回车选择,30s 超时默认项)。
> 本文档只做设计留档,**不改现有引导链**。配套:`docs/tf-boot-retrospective.md`(当前
> 引导链:TF 优先 → eMMC 回落,loader = Armbian v2026.07 树构建)。

---

## 一、目标形态

```
**** Boot Menu of Really ****

    Armbian edge 7.3.4 (TF)          ← 默认项,超时自动选
    Armbian edge 7.3.4 (eMMC)
    U-Boot console
    Reboot to MaskROM                ← 恢复模式快捷入口
    USB recovery                     ← 可选

Press UP/DOWN to move, ENTER to select
```

与幽兰的本质差异:幽兰用自定义 `osl.c` 动态扫 `ylboot.ini` 多段(一张卡多个系统);
主线等价物是 `CONFIG_CMD_BOOTMENU`(env 驱动,静态/半动态)+ extlinux 多标签。
"每介质一个菜单项"可完全复刻;"一张 TF 卡里多个系统段"用 extlinux 标签近似,
不做 osl.c 移植(工作量大、要啃 next-dev 老代码)。

## 二、阶段 1:串口菜单(低风险,预计半天)

### 配置(Armbian v2026.07 树,增量改 really-rk3588_defconfig)
```
CONFIG_CMD_BOOTMENU=y        # 菜单命令(cmd/bootmenu.c)
CONFIG_MENU=y                # 依赖
# bootdelay 保留(菜单前仍可 Ctrl+C 进 shell)
```

### 环境(板级头或 env 注入)
```
bootmenu_0=Armbian (TF)=setenv boot_targets mmc1; bootflow scan -lb      # TF extlinux
bootmenu_1=Armbian (eMMC)=setenv boot_targets mmc0; bootflow scan -lb
bootmenu_2=U-Boot console=
bootmenu_3=Reboot to MaskROM=mw.l 0xfd588080 0xEF08A53D; reset
bootmenu_default=0
bootmenu_delay=5
bootcmd=bootmenu             # 或:TF 在位跳过菜单直接默认项(见下)
```

无卡降级思路(二选一,实施时验证):
- 简单:菜单项 0 固定 TF,超时默认 0;TF 无卡时 bootflow 失败自动落到菜单下一项
  (bootmenu 本身不重试,需 `bootmenu_0` 里做 `mmc dev 1 || setenv bootmenu_default 1`);
- 严谨:bootcmd 前置脚本 `mmc dev 1` 探测,动态设 `bootmenu_default`。

### MaskROM 项的寄存器操作(需先验证!)
`mw.l 0xfd588080 0xEF08A53D; reset` —— 0xfd588080 = RK3588 boot mode 寄存器,
0xEF08A53D = BOOT_USB_UPDATE magic(vendor U-Boot `reboot loader` 同款效果,ROM 进
USB 下载模式)。**风险点**:值/行为需先在串口下手动验证一次(失败最坏=普通重启,
无砖风险)。幽兰的 MaskROM 项走的是 `rbrom`(SPL 热回 BROM),主线没有等价命令。

### 构建与部署铁律(继承 2026-11-18 变砖教训)
1. 只在 **armbian-build/cache/sources/u-boot-worktree/u-boot-really/v2026.07** 树上
   增量构建(线上 loader 同源,SPL/BL31 链已硬件验证);
2. 产物先与线上 loader 二进制 diff,确认差异仅在预期范围(u-boot 正文+dtb,不含 SPL);
3. **串口在线**才允许刷;刷后首次启动逐菜单项人工验证;
4. 回滚:LBA64 备份 dd 回 / Maskrom `rkdeveloptool wl 64`。

## 三、输入与显示硬件可行性(2026-11-18 查证,证据:运行时 DTB + Armbian v2026.07 树源码)

### 3.1 机器按键的真实接线

| 按键 | 接线 | 内核 DT 证据 | U-Boot 主线可行性 |
|---|---|---|---|
| 音量+ / 音量- | **SARADC 分压**(saradc@fe720000 ch1) | `adc-keys` 节点:vol-up 17mV、vol-down 417mV、back 1.23V、menu;keyup 1.8V(阈值单位 µV) | ✅ **`drivers/button/button-adc.c` 的绑定 compatible 恰好就是 `"adc-keys"`**,SARADC 驱动(`drivers/adc/rockchip-saradc.c`)在主线。开 `CONFIG_BUTTON_ADC + CONFIG_ADC + CONFIG_CMD_BUTTON`,U-Boot DT 抄入 adc-keys 节点 → `button status "volume up"` 直接轮询 |
| 播放/暂停 | SARADC ch3(`play-pause-keys`) | 同上 | ✅ 同上 |
| **电源键** | **RK806 PMIC PWRON 引脚**(非 SoC GPIO) | 原厂 DTS `rk806 → pwrkey { status okay }`;运行时 DT 无 SoC 侧节点 | ⚠️ 主线只有 `button-qcom-pmic.c`,无 RK806 版。需自写 `button-rk806.c`(参照 qcom 版,~百行,经既有 rk8xx PMIC 驱动读 PWRON 状态/INT 寄存器,寄存器位查 RK806 手册)。**替代:放弃电源键,"音量+ 短按=确认"** |

注意:native `bootmenu`(cmd/bootmenu.c)只消费 stdin(串口/USB 键盘),button 不进输入流。
按键驱动菜单需自写精简菜单命令(如 `bootmenu_btn`:轮询 button uclass + 渲染文本菜单到串口,
~150 行,即 ylboot `osl_show_bootmenu` 的精简版);或菜单仍用 native bootmenu(串口操作),
按键仅做"呼出/确认"辅助。

### 3.2 内屏与触摸(结论:主线树不可行)

内屏实况(运行时 DTB):`panel-lvds`(vesa-24,**dual-link**,port0=odd-pixels)、PWM 背光 +
enable GPIO3_B6、270° 竖屏(1080×1920);触摸 = **Goodix GT9110**(i2c@feac0000 @0x14,
irq GPIO0_A0,reset GPIO1_D3)。

主线 U-Boot(Armbian v2026.07 树)查证:`drivers/video/rockchip/` 只有 rk3288/rk3328/rk3399
的 VOP/HDMI/MIPI/LVDS(rk_lvds.c 是 rk3288 时代),**全树无任何 RK3588 显示驱动——HDMI 也没有**
(修正本文早期版本"HDMI 成熟度未知"的说法)。因此:

- 内屏菜单:❌ 主线树无 RK3588 VOP2 → 无从点亮(LVDS 更无);
- 触摸:❌ 无 GT9110 输入驱动,且依赖屏显存在才有意义;
- HDMI 菜单:❌ 同因(无 dw-hdmi-qp/hdptx)。

**屏显(内屏或 HDMI)的唯一现实路线 = 换底盘**:Rockchip vendor SDK 树(ylboot 即此路线,
其产品化代码已含 VOP2+LVDS+Goodix 触摸+电源键手势整套)。代价:放弃主线构建链、重做
板级 DTS 移植、重新验证引导链(数天量级)。若坚持主线树,等价于自行 port VOP2 最小初始化,
风险高于收益,**不建议**。

### 3.3 修订后的阶段划分

| 阶段 | 内容 | 输入 | 显示 | 状态 |
|---|---|---|---|---|
| 1a | native bootmenu 五项菜单 | 串口 | 串口 | 设计完成,未实施 |
| 1b | `bootmenu_btn` 精简菜单命令 | **音量± 移动 + 音量+ 确认**(电源键可选,需 button-rk806.c) | 串口 | 设计完成,未实施 |
| 2 | 内屏/HDMI 屏显 + 触摸 | 触摸/按键 | 内屏 | **需换 vendor SDK 树,大工程,默认不做** |

## 四、"UEFI 思路"评估(2026-11-18 学习 nanocode.cn/wiki 幽兰 wiki 后修订)

### 4.1 幽兰 UEFI 的真实形态(易混淆点先澄清)

幽兰设备上 **U-Boot 与 UEFI 是两套可整体互换的固件**,不是"U-Boot 里跑 UEFI":

| 固件 | 内容 | 角色 |
|---|---|---|
| ylboot(U-Boot, next-dev) | 自定义 `bootyl`/osl 菜单(开机照片里的 Boot Menu 就是它)、ylboot.ini 引导、NDB 调试 | 日常主力 |
| edk2-yourland(EDK2 UEFI) | 《UEFI以战说法》课程固件:`RK3588_NOR_FLASH_YL.img` **整体 dd 到 NOR**(/dev/mtdblock0),含内屏控制台、UEFI Shell(dh/map/dblk/acpiview)、串口交互、NDB 调试 | 学习/实验 |

两者靠 **NOR 整镜像 dd 互换**(UEFI恢复到U-Boot / 使用刷机工具更新UEFI 两篇 wiki);老机型"双剑1"只支持 UEFI,双剑2 两者皆可。注意:《把u-boot跑成一个应用》讲的是 U-Boot **sandbox 模式**(Linux 用户态调试),与 UEFI 无关。

### 4.2 对 TV2340R 的两条 UEFI 路线

**路线 A:U-Boot EFI_LOADER + GRUB(UEFI 引导方式,不动固件)** —— 推荐
- 现状:线上 loader 已开 `CONFIG_EFI_LOADER=y` + `EFI_VARIABLE_FILE_STORE=y`,今晚 TF 启动日志的 `efi_mgr` 扫描证明运行时已激活,只差 TF 卡上没有 EFI 程序
- 做法:TF 加 ESP(FAT32)放 `EFI/BOOT/BOOTAA64.EFI`(GRUB)+ grub.cfg;菜单=GRUB UI(高亮/上下键/倒计时,串口);系统内 `efibootmgr` 管理 BootOrder/BootNext(变量持久化于 ESP 的 `ubootefi.var`)= ylboot.ini 多启动项的标准工具版,**改菜单不用重刷 loader**
- 回落:rootfs 分区保留 extlinux 作二级回落;loader 全程不动,失败最多回到现状

**路线 B:EDK2 整固件替换(edk2-yourland 思路)** —— 2026-11-19 完成代码学习后分级
> 源码:`/data/ruili/tmp/edk2-yl/src/edk2-yourland2024`(174MB,edk2-rockchip 社区底座 + GEDU 板级)

- **镜像/部署(利好)**:布局 = GPT@0 + idblock@32KB(**= LBA64**)+ FIT@1MB + NV 变量@7.75M;
  `ddsd.sh` 证明同一产物直接 dd 到 eMMC/SD LBA64 → **与我们现有 U-Boot loader 同槽位互换**,
  变量存储(RkFvbDxe)按启动介质自适应。安全网(备份+Maskrom)已实测。
- **SoC 层复用度 ~90%**:Vop2Dxe、USB 全套、PCIe/SATA、I2cDxe、FSPI/NOR、GpioLib、
  RK806 库(双 PMIC 表抄 YourLand)、Dw8250 串口 1500000、BDS/UEFI Shell/Ext4、
  idblock+FIT 构建管线;DDR/BL31(rkbin miniall)原样。
- **新板移植形状**:7 件套(DSC / Modules.fdf.inc / RockchipPlatformLib(iomux+电压表+背光GPIO) /
  AcpiTables / LogoDxe / non-osi DTB / configs),仿 YourLand 抄改,纯板级 1~2 人周。
- **三块缺口(代码证据)**:
  1. **LVDS 内屏 4~8 人周**:Vop2Dxe 仅寄存器宏认识 LVDS(含 DUAL_EN/LEFT_RIGHT/SWAP 位),
     **无 connector 驱动/PHY/panel 框架**;时序硬编码 1080p 单模式
     (LcdGraphicsOutputDxe.c `mDisplayModes[]`)。需从 downstream `rockchip-lvds.c`
     移植 1~2k 行 + 竖屏 GOP + dual-link 相位调试;
  2. **触摸 GT9110 2~4 人周**:全树无 goodix/触摸驱动;I2C 栈现成,
     自写 ABSOLUTE_POINTER DXE;
  3. **SARADC 按键 1~2 人周**:无 ADC 驱动,从零写 SARADC MMIO + SimpleTextIn 桥。
- **分级**:
  - **B-lite 骨架版(1~2 人周)**:串口 + UEFI Shell + 标准 Boot#### 管理 + 与 U-Boot dd 互换,
    不碰显示;获得幽兰课程同款调试能力(dh/map/dblk/acpiview、热键 s 进 Shell);
  - **B-full 完全体(骨架 + 8~12 人周)**:加 LVDS 内屏 + 触摸(+可选按键)。
- 顺带:`uboot_uefi.img` = "U-Boot FIT 外壳 + BL33 槽装 eMMC 版 UEFI" 的预编译组合镜像,
  `misc/repack.sh` 可把任意可执行塞进 BL33 槽——幽兰"双固件共存"的构建期机制。

### 4.3 结论(2026-11-19 修订)

- 只要"菜单体验+可管理性" → **路线 A**(GRUB,零 loader 风险,半天);
- 想实践幽兰 UEFI 思路 → **路线 B-lite**(骨架移植 1~2 人周,串口+Shell+启动项管理,
  与现有 U-Boot 同槽位可 dd 互换,风险可控且是 B-full 的必经第一步);
- "内屏触摸菜单完全体" → B-full,大头是这块 dual-link LVDS 屏(4~8 人周),建议分期,
  先 B-lite 验证平台,显示单独立项;
- UEFI 不改变音量/电源键结论(§3.1);幽兰思路真正值得学的是**双固件 dd 互换安全网**,
  这点我们已具备(eMMC LBA64 + Maskrom,2026-11-18 实测)。

## 五、菜单项与 ylboot 对照表

| 幽兰菜单项 | 本机等价 | 说明 |
|---|---|---|
| u26k6126/u23k6126… on nvme 0:1 | (无 NVMe;可加 USB 项) | 多内核段 = extlinux 多标签 / GRUB 菜单项 |
| krnl6/krnl5 on mmc 0:2 | Armbian (TF) / Armbian (eMMC) | mmc0=eMMC;幽兰的 mmc0:2 是 eMMC 工厂分区 |
| MaskROM | Reboot to MaskROM | 寄存器 magic + reset,见 §2 |
| U-Boot console | U-Boot console | 空命令项=直接落 shell;GRUB 下用 `exit` 返回 U-Boot |
| 电源键双击呼出菜单 | (无 RK8xx 电源键长按逻辑) | 改为 bootdelay 内按任意键/固定每次显示 |

## 六、Android + Linux 双系统兼容性(2026-11-20 评估)

结论:**能做到,幽兰自己就是活例**(菜单里 krnl5/krnl6 on mmc 0:2 = eMMC 原厂系统,
u26xxx on nvme 0:1 = 自装 Linux,一张菜单双系统切换)。三条路径:

| 路径 | Android 怎么引导 | 工作量/风险 |
|---|---|---|
| **现主线 U-Boot(现 loader)** | 实测 `CONFIG_ANDROID_BOOT_IMAGE/BOOTMETH_ANDROID/ANDROID_AB 全部未开` → 需重开配置重编 + 手拼 cmdline/dtb(RK Android 12 + 5.10 非 GKI:boot_a + dtbo + misc 传参) | 中;OTA 后 bootimg/dtbo 变化易碎 |
| **vendor U-Boot 树(幽兰路线)** | Android/AVB/misc/A-B 全套原生保留,TF Linux 走 osl 式菜单 | 中高(换底座重移植),但这是幽兰已验证形态 |
| **EDK2 路线(B-lite/B-full)** | 树内自带 `AndroidBootImg` 协议 + "Android Boot"/"Android Fastboot" 平台启动项(RK3588Dxe.c,`PcdAndroidBootDevicePath`)+ RkAtagsLib 传参 | 框架内建,随 B-lite 一起获得 |

**前提与风险:**
1. **当前 eMMC 已刷成 Armbian 单分区** —— Android 需从 `RK3588-TV2340R-Android12-Native-v1.1`
   整刷恢复(Maskrom + rkdeveloptool 全流程已实测可用),恢复后 Armbian 只住 TF;
2. **AVB**:原厂可 Magisk root → 校验宽松,第三方 loader 引导风险低(待实机验证);
3. Android A/B slot 的 boot success 标记由 Android 自身 bootctrl 维护,第三方 loader 只管
   `androidboot.slot_suffix=_a/_b` 传参即可,不做槽位切换也不会砖;
4. 菜单层面:GRUB(U-A)/ osl(vendor)/ EDK2 Boot Manager(B)都能把"Android(eMMC)"
   做成一个菜单项,与 Linux 项并列。

## 七、B-lite 双系统深度论证与零重复刷机序列(2026-11-20)

### 7.1 "一次移植拿到三样"的证据级修正

| 能力 | 状态 | 证据 |
|---|---|---|
| UEFI Shell | ✅ 确定 | `FvMainModules.fdf.inc` 内建所有板 |
| Linux 双系统 | ✅ 确定 | 标准 EFI 扫描 ESP/GRUB;现 TF Armbian 直接可用 |
| 双固件互换 | ✅ 确定 | 与 U-Boot 同槽 LBA64,dd 互换 |
| Android Boot 菜单项 | ⚠️ 框架在,需四件小活 | App 已编入(FvMain:211);①`PcdAndroidBootDevicePath` 改指 boot_a@LBA0x13000(默认值是占位) ②RK boot.img 主 DTB 在 `second`(resource 容器)内,EmbeddedPkg AndroidBootImgLib 不解析 → 需小改提取或独立加载 ③`AppendArgs` 补 androidboot cmdline(真值从恢复后的 Android `cat /proc/cmdline` 抄) ④AVB 已关(vbmeta flags=2,实测) |
| Android Fastboot | ⚠️ 菜单项在,App **未编入** | 需在板级 Modules.fdf.inc 加 INF(一行) |

### 7.2 两个硬前提(已查实)

1. **Android 完整可恢复**:`box-backup-20261101/`(21G,双端 SHA 校验)含 GPT 头尾 + 全部分区
   (security@8192 / uboot_a@16384,b@24576 / trust@32768,40960 / misc@49152 / dtbo@57344,65536 /
   vbmeta@73728,75776 / boot_a@77824(96M),b@274432 / backup / cache / metadata / baseparameter /
   super(4G))+ loader_gap(原厂 loader LBA34-8191)+ data.tar.gz。v1.1 目录只是"改版增量包"
   (仅 boot_a+super),不能独立恢复。
2. **EDK2 8MB 镜像与 Android GPT 精确冲突**:EDK2 跨 LBA 64-16447 → **完整覆盖 security 分区
   (8192-16383)+ uboot_a 头 32KB(16384-16447)**。EDK2 自身运行不受影响;Android 的 DRM
   (Widevine 等)若依赖 security 分区会降级(直播盒基本无感);**回滚 vendor 链前必须先写回
   security.img + uboot_a.img**(备份都在)。

### 7.3 零重复刷机序列(2 个刷机窗口)

**窗口 0(零刷机,本机)**:B-lite 移植 + Android Boot 四件小活;
离线解包备份里的 `boot_a.img`(magiskboot)确认 DTB 在 second 的具体格式,把 AndroidBootImgLib
的解析风险提前清掉;产物 = tv2340r EDK2 镜像 + 回滚物料清单。

**窗口 1(刷机 A:恢复 Android)**:maskrom 按备份 GPT 逐分区写回(脚本化,复用 v1.1 的
一键刷机框架)→ 验证 Android 正常 → **在运行中的 Android 里取三样**:
`cat /proc/cmdline`(cmdline 真值)、DRM/功能自检、现状二次备份。
用 cmdline 真值**在本机补编最终版 EDK2**(此环节纯本机,不占刷机窗口)。

**窗口 2(刷机 B:上 EDK2)**:Android(adb root)或 maskrom 下 dd EDK2@LBA64 →
验证清单逐项:UEFI Shell → TF Linux → Android Boot → Fastboot。
任一步失败 → maskrom 写回 loader_gap + security + uboot_a(=回到窗口 1 纯 Android)
或 Armbian loader(=回到 TF/Linux 现状),**一步到位,无未知路径**。

刷机总数 = 2;所有信息采集(bootimg 结构、cmdline、GPT)前置到窗口 0/1,
窗口 2 不存在"刷了才发现缺信息"的返工路径。

## 八、USB 硬盘/优盘启动(2026-11-20,增量已构建待刷)

- **boot_targets 零改动**:`mmc1 mmc0 nvme scsi usb …` 已含 usb(TF/eMMC 之后)。
- **缺口(已补)**:线上 loader `CONFIG_USB_XHCI_DWC3` 未开 + really.dts 只开了 OTG 从模式。
  已在 Armbian v2026.07 树增量:
  - `configs/really-rk3588_defconfig`:+`CONFIG_USB_XHCI_DWC3=y`(USB_STORAGE/CMD_USB 本就有)
  - `rk3588-really.dts`:+`&usb_host1_xhci`(fc400000,USB3 主机口,dr_mode=host,内核 DT 实证
    此口接线)+ `&u2phy1/_otg` + `&usbdp_phy1` + 两对 EHCI/OHCI(fc800000/fc880000)
  - 产物:`…/u-boot-really/v2026.07/u-boot-rockchip-usb.bin`(md5 00e48b65,FIT 结构与线上链一致:atf-1/2/3+fdt 无 tee;**BL31 必须用 v1.48**——v1.56 会产出 atf-1+tee-1 结构,即 out2026 变砖链;原位构建,勿用 O= 外部目录)
- **USB 盘内容与 TF 卡同构**(ESP/extlinux,root=UUID),插上即扫描。
- **刷入纪律**:与 bootmenu/音量键等 loader 改动**攒批一次刷**;刷前串口在线验证
  `usb start && usb tree` 枚举;回滚 = 现有 Armbian loader 备份。
- 注意:U-Boot 阶段先按 USB2 高速验收(USB3 combo PHY 初始化复杂,内核起来后全速);
  若要"USB 优先于 TF",调 env `boot_targets` 把 usb 提前即可,无需重编。

## 九、攒批 loader 实施完成(2026-11-20,构建待刷)

需求:启动顺序 **USB → TF → eMMC**,音量加减键调整菜单。

产物:`…/u-boot-really/v2026.07/u-boot-rockchip-menu.bin`(md5 4202c6f2…)

| 改动 | 文件 | 说明 |
|---|---|---|
| BOOT_TARGETS 默认序 | `include/configs/rockchip-common.h:17` | `usb0 mmc1 mmc0 …`(注:该宏的历史默认 env 并未进二进制,TF 优先一直来自 bootstd 内建序;顺序实际由菜单保证,双保险) |
| SARADC + 音量键 | `rk3588-really.dts` | `&saradc okay` + `adc-keys`(ch1,vol-up 17mV / vol-down 417mV,与内核 DT 同参);驱动 `SARADC_ROCKCHIP` + `BUTTON_ADC` |
| **音量键菜单命令** | `cmd/really_bootmenu.c`(新) | `really_bootmenu`:vol- 下移 / vol+ 上移 / **vol+ 长按 1s 确认**;串口方向键+回车、ESC 控制台;**超时 8s 自动按 USB→TF→eMMC 启动**;选择后 `env_set boot_targets` + `bootflow scan -lb`(bootstd 读该 env 定序,bootstd-uclass.c:116 实证) |
| BOOTCOMMAND | defconfig | `really_bootmenu`(原 `bootflow scan -lb`) |

菜单项:USB 链(usb>tf>emmc)/ TF 链 / eMMC 链 / U-Boot console。
验证:DTB(saradc okay+adc-keys 阈值正确)、菜单字符串/命令编入、FIT 结构 atf-1/2/3 与线上链一致、BL31 v1.48。

**刷入前串口验证清单**:`button list`(应列出 volume up/down 及状态)、`really_bootmenu`(菜单渲染+按键)、`usb start && usb tree`(USB 枚举)、最后 `boot`。回滚:现有 Armbian loader 备份 / Maskrom。
