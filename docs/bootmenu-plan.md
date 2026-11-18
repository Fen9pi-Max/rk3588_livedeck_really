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

## 三、阶段 2:HDMI 屏显菜单(风险与工作量都更高,按需启动)

依赖链:
```
dm_video(vidconsole) → RK3588 HDMI TX(drivers/video/dw_hdmi_qp + hdptx PHY)
→ 字体/ framebuffer → menu 渲染到 vidconsole
输入:USB 键盘(CONFIG_USB_KEYBOARD + USB host 初始化);IR 遥控器主线无通用驱动,不可用
```
不确定性:主线 U-Boot 对 RK3588 HDMI 输出的成熟度(2026.07 时点 rock5b 是否开箱亮屏
未验证);若不亮,需移植/调试 hdptx PHY 初始化,工作量不可控。
建议:阶段 1 稳定运行、确有屏显刚需再启动;先在串口+HDMI 监视器上做一次现状摸底
(现 loader 开 CONFIG_VIDEO 没有、亮不亮)再定。

## 四、菜单项与 ylboot 对照表

| 幽兰菜单项 | 本机等价 | 说明 |
|---|---|---|
| u26k6126/u23k6126… on nvme 0:1 | (无 NVMe;可加 USB 项) | 多内核段 = extlinux 多标签 |
| krnl6/krnl5 on mmc 0:2 | Armbian (TF) / Armbian (eMMC) | mmc0=eMMC;幽兰的 mmc0:2 是 eMMC 工厂分区 |
| MaskROM | Reboot to MaskROM | 寄存器 magic + reset,见上 |
| U-Boot console | U-Boot console | 空命令项=直接落 shell |
| 电源键双击呼出菜单 | (无 RK8xx 电源键长按逻辑) | 改为 bootdelay 内按任意键/固定每次显示 |
