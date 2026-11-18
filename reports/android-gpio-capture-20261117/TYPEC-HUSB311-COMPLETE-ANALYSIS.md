# TypeC HUSB311 完整分析（2026-11-18）

## 三层问题叠加

### 层1: POWER_STATUS 误报 (已修复)
HUSB311 在未输出 VBUS 时报 VBUS_PRES|VCONN_PRES (0x0C)。
→ 已写 tcpci_get_vbus quirk（过滤双位置位+SOURCING=0），编入内核。

### 层2: CC 检测瞬态不稳定 (根本阻塞)
Toggling 期间 HUSB311 短暂检测到 Rd (CC2: 0→2)，tcpm 进入 SRC_ATTACH_WAIT。
但**随即 CC1=0 CC2=0 回到 OPEN**（TERM_RD=1 保留）。

tcpm 状态机要求:
- `tcpm_port_is_source(port)` 需要 CC 为 RP 类型 → CC=OPEN 时返回 false
- SRC_ATTACH_WAIT 处理器无匹配条件 → **永久卡死**
- `_tcpm_cc_change()` 可检测断开→回 UNATTACHED，但无新中断触发

### 层3: 中断只触发一次
IRQ114 计数=1（初始 CC 检测）。CC 状态回 OPEN 后芯片不再产生 ALERT
→ tcpm 无法感知断开 → 无法重试。

## 已尝试的修复
| 修复 | 结果 |
|------|------|
| tcpci_get_vbus HUSB311 quirk | 编入内核 ✓ 但不解决 CC 瞬态 |
| GPIO0_B7 中断脚修复 | 之前 D7 风暴→B7 正常 ✓ |
| vendor 驱动对比 | 无 HUSB311 专用代码 |

## 解决方向
1. **修改 tcpm 状态机**: SRC_ATTACH_WAIT 加超时→回 UNATTACHED 重试
2. **HUSB311 CC 稳定化**: vendor 初始化序列（未知）
3. **轮询模式**: tcpm 在 ATTACH_WAIT 状态加 CC 轮询
4. **硬件**: 检查 CC 线上拉/下拉电阻是否匹配 HUSB311 规格

## 对比上游
Junklords 也未解决（"TypeC DP 未闭环"）。此问题影响所有使用 HUSB311 的板子。
