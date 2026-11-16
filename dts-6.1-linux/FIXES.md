# dts-6.1-linux 修复记录（vendor 6.1 内核，Armbian rk35xx BRANCH=vendor）

Author: Codex (GPT-5); executor: user

Generated: 2026-11-14T21:55:00+08:00

Last updated: 2026-11-14T22:17:00+08:00

Context: Really TVI2340R vendor 6.1 board enablement, including the later
synchronization of board-level fixes first validated on Linux 7.3.

Applicable branch: `/home/user/github/build`, `main`, Armbian
`rk35xx` vendor 6.1 based on `rk-6.1-rkr7.2`.

Environment: Really TVI2340R, RK3588, eMMC boot, AP6275P
Wi-Fi/Bluetooth, HUSB311 Type-C, two PCIe 2.0 x1 links, HDMI1 and the
15.6-inch portrait DSI1-to-LT9211 dual-link internal display path. The
controller scan is 1920x1080; desktop presentation must rotate left to
1080x1920.

> 基准内核：`armbian/linux-rockchip` 分支 `rk-6.1-rkr7.2`（KERNEL_MAJOR_MINOR=6.1，
> 实测编译为 6.1.172-really-vendor）。以下修改均在 Really TVI2340R 实机验证通过：
> 系统完整启动、串口/eMMC/千兆网（大帧 0 丢包）/USB3/HDMI 1080p60 输出正常。

## 2026-11-14：从 Linux 7.3 同步到 vendor 6.1

本节只同步与 vendor 6.1 驱动模型兼容的板级事实。DTS 已使用 vendor 6.1
源码树完整编译通过，但本轮新增的 Wi-Fi/BT、Type-C、M.2 和风扇节点尚需
装入完整 vendor 镜像后做实机回归。

- AP6275P LPO 改为常开 32.768 kHz `wifi-lpo` fixed-clock。vendor
  `rfkill-bt` 使用 `ext_clock`，vendor `rfkill-wlan` 使用 `clk_wifi`，
  因此没有照搬 mainline 的 `lpo` 命名。
- 补齐 `wireless-bluetooth` / `wireless-wlan` 平台节点、UART7 M1
  pinmux、BT reset/wake/host-wake GPIO0_C6/GPIO0_C5/GPIO0_A0，以及
  Wi-Fi 电源使能 GPIO0_C4。
- 补齐 AP6275P 的 `pcie2x1l2` reset GPIO3_B7、`wifi_vbat` 供电，
  以及 M.2/5G 的 `pcie2x1l1` reset GPIO1_A7、供电 GPIO3_B3、
  模块 reset GPIO2_C5。
- 补齐 HUSB311 Type-C、USB-C role switch、USBDP orientation/DP
  Alt Mode mux、VBUS GPIO1_D1，以及 USB-A host 5 V GPIO3_A5。
- Type-C DP 使用双 lane，`rockchip,dp-lane-mux = <2 3>`，保留与
  USB3 共用高速 lane 的已验证 4K30 配置。
- 板级同时定义两条可选内屏路径：当前 BOM 的 DSI1/LT9211/LVDS，
  以及可选的 VP2/eDP0。默认镜像显式禁用 `edp0`、`edp0_in_vp2`
  和 `route_edp0`，避免未装配面板进入 DRM 聚合。
- LT9211 输出图已同步为 dual-link：port 2 为 odd pixels，port 3 为
  even pixels，panel-lvds 使用两个对应的 sink port。vendor 6.1 当前
  没有 LT9211 驱动，节点仍保持 disabled，但拓扑已与 7.3 一致。
- PWM2 风扇按 40000 ns（25 kHz）、反相输出配置，冷却级数为
  `0/76/153/204`；
  vendor 6.1 使用 `rockchip,temp-trips` 接入 55/65 摄氏度两级主动散热。

以下 7.3 改动明确不同步：

- 不同步 `lontium,dsi-mode-flags` 和 mainline LT9211 初始化逻辑。
  vendor 6.1 没有可用 LT9211 bridge 驱动，DSI1 链继续禁用。
- 不同步 mainline `simple-audio-amplifier` 声卡模型。vendor 6.1 的
  `rockchip,multicodecs-card` 已正确使用 GPIO4_B2/GPIO4_B4。
- 不同步 mainline GT9110 active-high 语义。vendor Goodix 驱动继续使用
  原厂 active-low reset/IRQ。
- 不照搬 mainline HDMI graph。vendor 6.1 继续使用
  `force-output + force_timing`。

本轮编译产物：

```text
/home/user/skysi-x5/artifacts/really-6.1-sync-1114/rk3588-really.dtb
SHA256: af411007674061923240708b8f6406fb181b37a7f3a188acd798725c67f20b94
```

## 2026-11-17：补齐原厂电源拓扑（13 个 regulator）

此前本文件只同步了 7.3 的显示/串口/USB 等结论，**漏掉了整棵电源树**。
对照原厂 DTB 后发现，6.1 的板级 `regulator-fixed` 只有 15 个，原厂有 23 个。
补齐后 29 个（多出的部分来自 PMIC 内部轨的正常差异）。

### 缺的是什么

| 类别 | 缺失项 |
|---|---|
| 带 GPIO 的关键轨 | `vcc1v8_sys`(GPIO0_C0)、`mipi_cam_pwen`(GPIO1_A2)、`vcc_5g_dpr_ctl`(GPIO3_D5)、`power_on_led`(GPIO3_D0) |
| 无 GPIO 的虚拟轨 | `vcc4v0_sys`、`vcc3v3_ext`、`vcc12_dvp`、`vcc28_dvp`、`vcc1v8_pmu_ddr_s3`、`pcie20_avdd0v85/1v8`、`pcie30_avdd0v75/1v8` |
| 共享使能 | `touch_panel_pwr`(GPIO1_PD0) |

### 为什么之前没发现

原厂触控 `gt9xx@14` 和 RTC `hym8563@51` **都没有 `*-supply` 属性**，
它们完全依赖 `vcc1v8_en`(GPIO0_C0) 这条 always-on 轨被拉起。少了这条轨，
两个器件会一起失效，而 I2C 控制器本身是好的——很容易被误判成 I2C 或
驱动问题。

同样的道理，`GPIO1_PD0` 是**触控模块和面板的共享使能**，此前只挂在 eDP
面板的 `enable-gpios` 上。一旦 eDP 被 disable（本机确实没有 eDP 面板），
触控跟着断电。必须抽成独立常开 regulator。

### 供电轨接错

GT9110 原来写 `power-supply = <&vcc_3v3_s3>`，实际需要：

```dts
AVDD28-supply = <&vcc28_dvp>;   /* 2.8V */
VDDIO-supply  = <&vcc1v8_sys>;  /* 1.8V */
```

`vcc_3v3_s3` 是 PMIC 常开轨，看着"更安全"但不是这颗芯片的供电来源。
这类错误能编译、能 probe，只是电压不对，比缺节点更难发现。

### 与 mainline 保持一致的取舍

- `vcc1v8_sys` 的 pinctrl（`gpio0_C0` + pull-up）**必须写**。7.3 最初只用
  裸 gpio-hog，引脚从未真正被驱动，这个坑不能重犯。
- 触控坐标保持 vendor 语义：`touchscreen-size-x=<1920>` /
  `touchscreen-size-y=<1080>`，与原厂 `max-x=0x780` / `max-y=0x438` 一致。
  **不加** mainline 的 `touchscreen-swapped-x-y` / `-inverted-x`，因为
  vendor Goodix 驱动的轴序与 mainline 不同。

### 验证状态

**未上机验证。** 本地没有 6.1 的 dtsi 可供编译，只做了结构校验：
大括号净差 0、无重复 label、未定义 label 数（25）与改动前一致。
上机后需确认 `i2cdetect -y 4` 能看到 `0x14` 与 `0x51`。

完整分析见
[`../docs/DTS-POWER-RESTORE-20261117.md`](../docs/DTS-POWER-RESTORE-20261117.md)。

## 历史实测修复（对上游 dts 的 6 处变更）

### 1. `&uart0` → disabled（关键修复）

UART0 m2 引脚与 **SPI2-CS0（GPIO0_B1/pin9）冲突**。本板 RK806 PMIC 挂在 SPI2
（见 `rk3588-rk806-single.dtsi`）。uart0 使能时 SPI2 pinctrl 申请失败：

```
rockchip-pinctrl: pin gpio0-9 already requested by fd890000.serial; cannot claim for feb20000.spi
rockchip-spi feb20000.spi: Error applying setting
```

→ RK806 不 probe → 全部主调压器缺失（vdd_cpu_lit/gpu/log/vdenc/ddr…）→
cpufreq 放弃 + VOP/GPU/NPU/panel/dmc 全部 deferred，系统仅剩基础功能。
**禁用 uart0 后 RK806 正常，29 个调压器全部注册。**

### 2. `&pwm12` 移除板级 pinctrl 覆盖

vendor `rockchip-pwm` 驱动要求 pinctrl-names 为 `"active"`（dtsi 默认）。
板级写 `pinctrl-names = "default"` 会导致：

```
rockchip-pwm febf0000.pwm: No active pinctrl state
```

→ pwm12 不注册 pwmchip → backlight deferred → panel deferred →
**rockchip-drm 聚合整体被拖死（HDMI 陪葬）**。修复：删除板级覆盖，用 dtsi 默认。

### 3. DSI1 → LT9211 → panel-lvds 整链 disabled（v6.1 临时）

vendor 6.1 内核**没有 LT9211（lontium,lt9211）bridge 驱动**（主线 5.16 引入，
BSP 未回合）。DSI1 链的 remote bridge 永远等不到，rockchip-drm 聚合无法 bind，
`/dev/dri` 为空。禁用 `&dsi1 / &dsi1_in_vp3 / &route_dsi1 / lt9211 / panel-lvds /
backlight-lvds` 后 HDMI 独立成路，card0 正常出现。
（后续回合 lt9211 驱动后可恢复。）

### 4. `hdmi1-con`（hdmi-connector 节点）删除

主线写法的辅助 connector 节点，vendor DRM 图解析不需要且可能干扰。

### 5. `&hdmi1` 使用 `force-output` + `force_timing`（关键修复）

本板 **HDMI HPD 线未接进 SoC**（工厂 5.10 DTB 用 `force-hpd`；但 vendor 6.1 的
`dw_hdmi_qp` 驱动不识别 `force-hpd`——该属性仅 `dw-dp.c` 支持）。表现为
connector 永远 disconnected。vendor 6.1 正确机制（见
`dw_hdmi_qp-rockchip.c` `of_property_read_bool(np, "force-output")` +
`of_get_display_timing(np, "force_timing", ...)`）：

```dts
&hdmi1 {
	force-output;
	force_timing: force_timing { /* 1080p60 CEA 时序 */ ... };
};
```

实测：`card0-HDMI-A-1 connected/enabled`、VOP2 输出 1920x1080p60、fbcon 上屏。

### 6. rk3588s.dtsi SCMI 依赖（记录，dts 层无解）

rkr7.2 把 CPU/GPU/NPU/DMC/SDMMC/crypto/rng 时钟移交 `firmware/scmi`
（SMC 0x82000010）。原厂 OP-TEE 3.13 不实现 SCMI → `arm-scmi probe -22` →
上述设备 deferred（CPU 固定 boot 频率、SD 卡不可用）。CRU 中无对应时钟，
板级 dts 无法改回；需回退 rkr6 之前 dtsi 或更换支持 SCMI 的 trust（后者受
Boot1 校验限制不可行）。**不挡基本功能。**

## 附：这台设备（原厂 Boot1/U-Boot 链）的刷写要点

- boot image id@576 校验：两步哈希法（刷入 → U-Boot 拒绝打印 real → 写回）
- U-Boot shell 的 `mmc read/write` LBA 参数是**十六进制**：
  boot_a=0x13000（十进制 77824），id 扇区=0x13001，id 在第二扇区偏移 0x40
- maskrom loader 的裸 LBA 小扇区写入存在假成功（同会话回读命中 RAM 缓存），
  大块/整镜像或 U-Boot shell 直写可靠

## 实测启动日志关键证据

```
ANDROID: Hash OK
Linux version 6.1.172-really-vendor
Machine model: Really TVI2340R RK3588 Live Streaming Box
rk806 spi2.0: chip id: RK806,ver:0x2
rk_gmac-dwmac fe1b0000.ethernet: TX delay(0x44).   ← 工厂真值生效
end0: PHY [YT8531] ... 8000B 大帧 TX 0% 丢包（主线 7.3 时代 100% 丢）
rockchip-vop2: Update mode to 1920x1080p60 for vp0 ... if:HDMI1
card0-HDMI-A-1: connected enabled
```
