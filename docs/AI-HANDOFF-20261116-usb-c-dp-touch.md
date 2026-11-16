# Really RK3588 USB-C DP 专项交接

更新时间：2026-11-16

范围：只处理 USB-C DP。

GT9110 触控与 HYM8563 RTC 已通过共享电源修复完成实机验证并关闭。
除非 USB-C DP 修改造成明确回归，否则不要再改它们的 I2C4、reset/IRQ、
Goodix compatible 或供电映射。

## 1. 当前现场

```text
Board: Really TVI2340R
Kernel: 7.3.4-edge-rockchip64 #61
DP connector: card1-DP-1
DP state: disconnected
Type-C partner: unstable
HUSB311: PD/VDM 后反复 detach
```

代表性日志：

```text
rt1711h 6-004e: tcpm: state change SRC_SEND_CAPABILITIES -> SRC_READY
rt1711h 6-004e: tcpm: AMS POWER_NEGOTIATION finished
rt1711h 6-004e: tcpm: VDM_DISCOVERY_COMPLETE
rt1711h 6-004e: tcpm: CC1: 0 -> 0, CC2: 2 -> 0
                 [SRC_READY, polarity 1, disconnected]
rt1711h 6-004e: tcpm: SRC_READY -> SNK_UNATTACHED
rt1711h 6-004e: tcpm: Start toggling
```

历史上曾经完成两 lane 4K30，但不可重复，不能作为当前已修复证据。

## 2. 当前 DTS 拓扑

```text
DP0 -> VOP2 VP1
USBDP PHY0 mode-switch/orientation-switch
DP lane mux = <2 3>
HUSB311 at I2C6 0x4e
SBU1 = GPIO3_A0
SBU2 = GPIO1_B2
USB camera 5 V = GPIO4_A6
custom linux,typec-extcon-bridge
```

标准链路：

```text
CC/PD roles -> TCPM -> DP Alt Mode VDM -> typec_displayport
-> USBDP PHY lane/orientation mux -> DP HPD bridge
-> SBU/AUX -> link training -> EDID
```

## 3. 首先确认运行 DTB

确认实机 DTB 包含：

```dts
sbu1-dc-gpios = <&gpio3 RK_PA0 GPIO_ACTIVE_HIGH>;
sbu2-dc-gpios = <&gpio1 RK_PB2 GPIO_ACTIVE_HIGH>;
```

并确认 GPIO4_A6 只用于 USB camera/USB 5 V：

```dts
vcc5v0_usb {
	gpio = <&gpio4 RK_PA6 GPIO_ACTIVE_HIGH>;
};
```

旧 DTB 中 GPIO4_A6/A7 作 SBU，会与摄像头供电冲突。若运行 DTB 早于
`35808e7 update dts`，先更新 DTB 再测试。

## 4. 状态采集

从插线前开始，以 100 ms 间隔记录：

```text
/sys/class/typec/port0/data_role
/sys/class/typec/port0/power_role
/sys/class/typec/port0/port0-partner.*
/sys/class/typec/port0/*/displayport/configuration
/sys/class/typec/port0/*/displayport/pin_assignment
/sys/class/typec/port0/*/displayport/hpd
/sys/class/typec/port0/*/displayport/irq_hpd
/sys/class/drm/card*-DP-1/status
/sys/class/drm/card*-DP-1/modes
```

保存：

- HUSB311/RT1711H 的 TCPM debugfs log
- TCPM log 只能读一次，读取会清空，必须立即保存
- `dmesg` 中 `rt1711h`、`tcpm`、`typec_displayport`、`usbdp`、
  `dwc3`、`dw-dp` 的完整日志
- 插线、PD 完成、断开、再次插入的时间点

## 5. 故障阶段分类

### A. Partner 在 DP Alt Mode 前消失

优先检查：

- CC1/CC2
- VBUS 稳定性
- `vbus5v0_typec`
- `vcc5v0_usb`
- GPIO4_A6
- `data_role`、`power_role`
- `try-power-role = "sink"` 是否符合板级供电设计

### B. Partner 稳定但 `hpd=0`

优先检查：

- TCPM 到 `typec_displayport` 的 HPD bridge
- 当前 custom `linux,typec-extcon-bridge`
- 内核 USBDP/DP bridge 补丁是否完整

### C. `hpd=1` 但 AUX 失败

优先检查：

- SBU1 GPIO3_A0
- SBU2 GPIO1_B2
- USBDP PHY 的 DP/SBU 路由
- orientation

### D. Link training 成功但显示模式失败

优先检查：

- 像素时钟
- VOP1/DP0 timing
- PHY 支持速率
- 4K60 是否超出当前稳定链路能力

## 6. 受控 A/B 测试

### 6.1 `typec-extcon-bridge`

当前 DTS 使用：

```dts
typec_extcon_bridge: typec-extcon {
	compatible = "linux,typec-extcon-bridge";
	mode-switch;
	orientation-switch;
	usb-role-switch;
	svid = /bits/ 16 <0xff01>;
};
```

HUSB311：

```dts
extcon = <&typec_extcon_bridge>;
```

该 bridge 不在 Collabora 描述的标准 TCPM/mode-switch 路径中，可作为
A/B 回归项。只有确认内核需要它时才保留，不能无日志依据永久删除。

### 6.2 power role

当前 connector：

```dts
power-role = "dual";
try-power-role = "sink";
```

Collabora 的 source-device 示例使用 `try-power-role = "source"`。
必须结合板上 VBUS 实际供电路径和 PD log 判断，不能单独翻转。

### 6.3 内核能力

Collabora 文章指出 USBDP PHY 和 DP DRM/HPD 补丁在文章发布时仍处于
上游评审阶段。核对当前 7.3.4 内核是否完整 backport：

- USBDP PHY
- Rockchip DWC3 glue
- DP bridge/HPD
- typec_displayport

如果 TCPM 稳定且 `hpd=1`，但 `DP-1` 仍不 connected，应优先查内核
补丁完整性，而不是继续改板级 DTS。

## 7. 验收标准

- 5 次冷启动稳定
- 5 次热插拔稳定
- Type-C partner 不反复 detach
- `displayport/hpd = 1`
- `DP-1 connected`
- EDID modes 可读
- 1920x1080 长时间稳定
- 3840x2160@30 长时间稳定
- DP 切换后 USB3 不失效
- 双链路 LVDS 不受影响

## 8. 交付格式

```text
测试版本：
DTS commit / DTB SHA256：

Type-C:
- data_role / power_role：
- partner VDO：
- pin_assignment：
- hpd / irq_hpd：

DRM:
- DP-1 status：
- modes：
- link training：
- 冷启动/热插拔次数：

失败阶段：
本次唯一改动：
回归结果：
结论：通过/部分通过/失败
```
