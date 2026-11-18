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

## 四、菜单项与 ylboot 对照表

| 幽兰菜单项 | 本机等价 | 说明 |
|---|---|---|
| u26k6126/u23k6126… on nvme 0:1 | (无 NVMe;可加 USB 项) | 多内核段 = extlinux 多标签 |
| krnl6/krnl5 on mmc 0:2 | Armbian (TF) / Armbian (eMMC) | mmc0=eMMC;幽兰的 mmc0:2 是 eMMC 工厂分区 |
| MaskROM | Reboot to MaskROM | 寄存器 magic + reset,见上 |
| U-Boot console | U-Boot console | 空命令项=直接落 shell |
| 电源键双击呼出菜单 | (无 RK8xx 电源键长按逻辑) | 改为 bootdelay 内按任意键/固定每次显示 |
