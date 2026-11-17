# HDMI-in (LT6911UXC2) 驱动评估

## 现状
- 芯片: LT6911UXC2 (i2c6 0x2b, compatible `lontium,lt6911uxc2`)
- CSI 通路: csi@fdd30000 → video-capture@fdce0000 (主线已 probe)
- DT 节点存在, 内核 fw_devlink 已解析依赖
- **主线无 LT6911UXC 驱动** (lt6911uxe.c 仅支持 UXE + ACPI only)

## 移植评估
| 项 | 说明 |
|---|---|
| Vendor 驱动 | 1670 行, `lontium,lt6911uxc` compatible, RK 专有框架 |
| 主线参考 | lt6911uxe.c 707 行 (Intel ACPI, 不同芯片) |
| 工作量 | ~800-1200 行新代码: V4L2 subdev + I2C 寄存器序列 + HPD/EDID |

## 建议路径
1. 以 lt6911uxe.c 为骨架 (主线 V4L2 框架)
2. 从 vendor lt6911uxc.c 移植寄存器初始化序列
3. 添加 OF match: `lontium,lt6911uxc2` + `lontium,lt6911uxc`
4. 连接 rk3588 CSI host 的 V4L2 async

这属于独立项目级别的工作, 暂不在主线 bring-up 范围内。
