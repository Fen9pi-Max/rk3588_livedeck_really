# Really TVI2340R AI 交接清单

更新时间：2026-11-16

## 当前状态

仓库：`/home/user/rk3588_livedeck_really`

分支：`main`

当前提交：`c9e16bd add touch screen fix doc`

主要文件：

- `dts-7.3-linux/rk3588-really.dts`
- `reports/mainline-open-issues-20261115-2130/README.md`
- `docs/AI-HANDOFF-20261116-usb-c-dp-touch.md`

| 项目 | 状态 |
| --- | --- |
| 内屏双链路 LVDS | 已实机验证 |
| HDMI 输出 | 已实机验证 |
| GT9110 触控 | 已实机验证闭环 |
| HYM8563 RTC | 已实机验证闭环 |
| USB-C DP | **未闭环，当前唯一板级显示问题** |
| TF 启动 | 不在本交接单范围 |

重要：触控/RTC 的修复已在验证树实机通过，但当前 Git checkout 中
`dts-7.3-linux/rk3588-really.dts` 没有对应的未提交 diff。接手时应先确认
运行/构建树是否已同步以下修复，不要仅凭文档假定仓库 DTS 已包含：

- `vcc1v8_sys` regulator，由 GPIO0_C0 控制；
- `vcc1v8_sys_en` pinctrl，GPIO function + pull-up；
- 删除原 `vcc1v8_sys_hog`；
- always-on 2.8 V `vcc28_dvp`；
- GT9110 `AVDD28=<&vcc28_dvp>`；
- GT9110 `VDDIO=<&vcc1v8_sys>`。

## 板级硬约束

- 原厂 Android 基线：Android 11 / Linux 5.10。
- 内屏是双链路 LVDS：

```text
VOP2 VP3 -> DSI1 -> LT9211
LT9211 port 2 -> odd pixels
LT9211 port 3 -> even pixels
```

- USB-C DP SBU：

```text
SBU1 = GPIO3_A0
SBU2 = GPIO1_B2
```

- GPIO4_A6 是 USB 摄像头/USB 5 V enable，不能当 SBU。
- 不复制 Chmayco、Skysi 或其他单板的 I2C/GPIO 配置。
- 不改变已经闭环的触控/RTC 电源和 Goodix 极性，除非出现明确回归。

## 当前唯一活动问题

USB-C DP 历史版本曾完成 4K30 link training，但当前基线中：

```text
/sys/class/drm/card1-DP-1/status = disconnected
HUSB311 在 PD/VDM 后反复 detach
SRC_READY -> SNK_UNATTACHED -> toggling
```

当前失败点早于稳定的 DP AUX 输出。不要先改 VOP、LVDS、EDID 或
`rockchip,dp-lane-mux`。

详细诊断、状态采集和验收标准见：

[`AI-HANDOFF-20261116-usb-c-dp-touch.md`](AI-HANDOFF-20261116-usb-c-dp-touch.md)

## 接手顺序

1. 确认实机运行 DTB 包含正确的 SBU GPIO 和 USB 摄像头 5 V 分配。
2. 插着 DP 显示器冷启动，记录 Type-C、TCPM、displayport HPD 和 DRM 状态。
3. 判断 partner 是否在 Alt Mode 前消失。
4. 确认内核是否包含 Collabora USBDP PHY/DP bridge/HPD 补丁。
5. 只在有状态证据时测试 `typec-extcon-bridge`、power-role 或 lane mux。
6. 完成多次冷启动和热插拔回归后再标记闭环。

## 交付要求

- 只修改 `dts-7.3-linux/rk3588-really.dts` 和对应验证报告。
- 不覆盖原厂 DTB，不归档重新生成的 DTB。
- DP 修改单独提交，不混入触控/RTC。
- 记录修改前后的 DTB SHA256、Type-C 状态、dmesg 和测试次数。

## 禁止事项

- 不得把双链路 LVDS 改成单链路。
- 不得把 GPIO4_A6 重新用于 SBU。
- 不得在 Type-C partner 尚未稳定时修改 DP lane mux。
- 不得恢复已删除的 Android 触控日志作为当前待办。
- 不得声称 USB-C DP 已修复，除非满足 DP 专单的验收标准。
