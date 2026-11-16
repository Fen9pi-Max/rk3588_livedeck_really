# Really TVI2340R AI 接手清单与交接

- 作者：OpenAI Codex（GPT-5），执行端：user
- 生成时间：2026-11-15T18:10:00+08:00
- 最后更新：2026-11-16
- 背景：Really TVI2340R 已完成 mainline 7.3 的主要板级 bring-up，但
  TF 启动和 USB-C DP 仍未闭环。GT9110 触控与 HYM8563 RTC 已于
  2026-11-16 通过恢复板级电源链完成实机闭环。
- 适用构建分支：`/home/user/github/build`，`main`，Armbian edge/resolute
- 适用内核：`7.3.4-edge-rockchip64`
- 运行设备：Really TVI2340R，RK3588，`192.168.3.233`
- 串口：UART2 M0，`1500000 8N1`
- 设备 DTS 基线：
  `/home/user/device/rk3588-really/rk3588_livedeck_really/dts-7.3-linux/rk3588-really.dts`

> 本文是给接手 AI 的当前工作清单。历史文档中的成功结论如果与本文冲突，
> 以本文和实测现场为准。尤其不要沿用“TF 已能启动”或“触控曾经绑定成功”
> 这两类旧结论。

---

## 1. 接手前必须知道的七件事

1. **TF 启动没有完成。** Linux 能看到 TF 卡不等于 U-Boot 能初始化它。当前
   U-Boot 对 TF 的 `mmc_init()` 仍为 `-EIO`。
2. **USB-C DP 当前没有闭环。** `DP-1 disconnected`，Type-C partner
   不稳定并在 PD/VDM 完成后反复 detach。历史上曾抓到 4K30，不能据此
   宣告当前镜像已修复。
3. **GT9110 和 HYM8563 已闭环。** 根因是 `vcc1v8_sys` 的 GPIO0_C0
   pinctrl/regulator 依赖和 GT9110 的 `vcc28_dvp` 2.8 V 供电未恢复。
   修复后 GT9110 I2C4 `0x14`、HYM8563 `0x51` 均正常。
4. **USB 相机默认由虚拟 PipeWire 节点提供。** 原 UVC 节点被 WirePlumber
   隐藏，直接用 `snapshot` 启动会显示 “No camera Found”。必须通过桌面
   图标或 `/usr/local/bin/really-camera-open` 启动。
5. **加速度计硬件存在且驱动可用。** STK8BAXX 位于 I2C6 `0x18`，7.3 DTS
   已补节点。当前运行态曾手工实例化验证；下一次重启应从 DTS 自动出现。
6. **eDP0 是可选内屏路径，不是不存在的接口。** 同一份 7.3 DTS 同时描述
   DSI1/LT9211/LVDS 和 VP2/eDP0；eDP 不设置 `force-hpd`/`no-hpd`，
   由真实 HPD/AUX 决定 connected 或 disconnected，不能伪造常亮内屏。
7. **涉及 Android 整盘刷写前必须得到用户明确授权。** 刷写会覆盖当前 Linux
   eMMC，属于破坏性操作。

---

## 2. 当前环境

| 项目 | 当前值 |
|---|---|
| 主机名 | `really` |
| SSH | 当前现场为 `root@192.168.3.233`，密码由用户单独提供 |
| 内核 | `Linux 7.3.4-edge-rockchip64 #61` |
| 启动介质 | eMMC |
| 桌面 | GDM + Ubuntu session，自动登录 `user` |
| 主题 | `gtk-theme=Yaru-dark`，`icon-theme=Yaru` |
| 电源策略 | CPU governor 全部 `performance` |
| 当前运行 DTB SHA256 | `98cb2541226cdc34ff269040f4b99cc30c21e159b15545d6709ef5688f4f9b84` |
| 当前完整镜像 | `/home/user/github/build/output/images/Armbian-unofficial_26.11.0-trunk_Really_resolute_edge_7.3.4_gnome_desktop.img` |
| 最近构建镜像 SHA256 | `9eb4f5726d337073a7d1e8a06f41ef5fd67fe9e5413ef1f15f702b5ce9585980` |

当前镜像包含：

- 完整社区启动链：SPL + U-Boot 2026.07 + Linux 7.3.4。
- Really LVDS 双链路、ES8388、GPS、USB HID workaround。
- Type-C DP 配置和 extcon 桥接代码已包含，但最终基线尚未闭环。
- Yaru 图标、Ubuntu session、首启账户预置。
- USB 摄像头虚拟源和启动器链路，当前方向设置为 `90r`。
- STK8BAXX 加速度计 DTS 节点。
- 常电性能模式服务。

### 2.1 设备树子仓库提交基线

硬件参考仓：

```text
/home/user/device/rk3588-really/rk3588_livedeck_really
remote: git@github.com:Junklords/rk3588_livedeck_really.git
HEAD:   08613d8
track:  main -> origin/main
state:  含未提交的设备树、eDP 和当前状态文档改动；接手前先执行 `git status`
```

提交历史与当前意义的对应关系：

| Commit | 内容 | 对当前工作的意义 |
|---|---|---|
| `3737bd2` | 首次加入逆向还原及移植的 5.10/6.1/7.3 DTS | 原始基线 |
| `0db7a50` | 集中补齐 SoC 级 RGA/VPU/etc. 能力并整理 DTS | SoC 外设基线 |
| `04cd7b9` | vendor 6.1 实机验证修复 | 仅直接适用于 `dts-6.1-linux` |
| `eee6452` | 合并 `04cd7b9` | vendor 6.1 修复进入 main |
| `67ac899` | LVDS dual-link 图、驱动文档和板级文档 | 内屏 full-screen 基线 |
| `eef2ce6` | 面板 portrait orientation | 1080x1920 逻辑方向 |
| `b866f34` | 修正 portrait rotation 和 fbcon rotation | 启动控制台方向 |
| `a5fd2ec` | 记录 DRM/fbcon 方向结论 | 防止回退说明 |
| `bcfaebc` | 归档 mainline U-Boot DTS/config | U-Boot 板级参考 |
| `35808e7` | 最近一次综合 DTS 更新 | 见下方逐项说明 |
| `08613d8` | U-Boot 更新 | 当前 main/upstream 基线 |

`35808e7` 实际上包含多组改动，提交标题 `update dts` 过于笼统。它包含：

- SARADC3 play/pause key。
- PWM 反向亮度表，默认逻辑亮度 154。
- M.2/5G DPR 电源控制 `GPIO3_D5`。
- USB 5V `GPIO4_A6` 控制。
- Type-C SBU 改为 `GPIO3_A0` / `GPIO1_B2`。
- LT9211 移除会引发竖线闪烁的 `dsi-mode-flags=<2051>`。
- GT9110 reset/IRQ 改为 ACTIVE_LOW、pinctrl 改 pull-none。该改动正确但
  没有解决触屏不响应。
- U-Boot SD 供电链改为原厂 `vcc_3v3_s3 -> vcc_sd`，并补充 SDIO 属性。
- 新增 `u-boot-mainline/TF-BOOT-STATUS.md` 初版。

当前工作树不能再用固定文件数描述，至少包含：

```text
M README.md
M README.en.md
M docs/AI-HANDOVER-CHECKLIST-20261115.md
M dts-7.3-linux/FIXES.md
M dts-7.3-linux/rk3588-really.dts
?? reports/
```

当前未提交 7.3 DTS 改动包括但不限于：

```text
eDP0/VP2/PWM6 optional internal-panel path
Type-C extcon bridge and SBU/lane experiment
GT9110 polarity and portrait coordinate experiment
mipi_cam_pwen and current Type-C power topology
```

当前 7.3 DTS 已与构建仓一致：

```text
/home/user/device/rk3588-really/rk3588_livedeck_really/dts-7.3-linux/rk3588-really.dts
/home/user/github/build/patch/kernel/archive/rockchip64-7.3/dt/rk3588-really.dts
SHA256 ae382b9180c02ff5755dc41ac663778f22740bea2fe170f79d91fe90b261a7bc
```

注意：子仓库是硬件、DTS 和 U-Boot 板级补丁的参考源；真正参与 Armbian
构建的源码在 `/home/user/github/build/patch/...`。两边必须用 `cmp` 检查，
不要假设自动同步。当前 7.3 DTS、U-Boot upstream DTS、U-Boot dtsi 和
defconfig 已同步。

构建仓的 U-Boot 板级补丁也已原样归档到：

```text
u-boot-mainline/board_really/0001-really-persistent-boot-log.patch
u-boot-mainline/board_really/0002-really-prefer-usb-before-emmc.patch
u-boot-mainline/board_really/0003-really-act-on-reboot-mode.patch
u-boot-mainline/board_really/0004-really-sdmmc-power-domain-in-spl.patch
```

其中 `0004` 已实测无效，只能作为失败实验保留，不能当作 TF 修复。

---

## 3. 硬件拓扑速查

```text
                         +-------------------------------+
                         |          RK3588 SoC           |
                         |                               |
 DSI1 4-lane ----------->| VOP/DSI -> LT9211 @ I2C4 0x2d|
                         |             |                 |
                         |             +-> dual LVDS ----> 15.6" portrait panel
 VP2 / eDP0 ------------->| optional internal eDP panel  |
                         |                               |
 DP Alt Mode <---------->| USBDP / HUSB311 Type-C       |
 HDMI OUT <--------------| HDMI1 TX                     |
 HDMI IN  ---LT6911C---->| MIPI CSI                     |
 eMMC <----------------->| sdhci mmc0                   |
 TF slot <-------------->| sdmmc mmc1                   |
                         |                               |
 GMAC0 <---RGMII-------->| YT8531C PHY + LEDs           |
 PCIe2x1l1 <------------>| M.2 / 5G slot                |
 PCIe2x1l2 <------------>| AP6275P Wi-Fi/BT             |
 UART0 <---------------->| UC6226NIS GNSS               |
 I2S1 M0 <-------------->| ES8388 audio                 |
 I2C4 <----------------->| GT9110 0x14 / HYM8563 0x51   |
 I2C6 <----------------->| LT6911C 0x2b / STK8BAXX 0x18 |
 USB EHCI <------------->| Fic QHD USB Camera           |
                         +-------------------------------+
```

---

## 4. 当前状态 Checklist

### 4.1 已闭环，回归时不要轻易回退

- [x] mainline 7.3 从 eMMC 启动。
- [x] GDM、Ubuntu session、自动登录。
- [x] Yaru-dark 和 Yaru 图标。
- [x] LVDS 双链路完整画面，`LVDS-1 connected`。
- [x] 内屏 1080x1920 竖屏方向。
- [x] 背光亮度调节。当前运行值可能被用户调成其他值；镜像默认逻辑值 154。
- [x] ES8388 扬声器、耳机、录音、耳机检测。
- [x] USB Type-C USB2、USB-A 主机。
- [x] YT8531C 有线网和 PHY LED。
- [x] GPS 以 NMEA0183 识别，室内无 fix 属正常。
- [x] M.2/5G 槽供电和 PCIe root port 枚举。
- [x] AP6275P PCIe 设备枚举，Wi-Fi/BT 硬件存在。
- [x] mini keyboard/触控板掉事件 workaround。
- [x] USB 相机取流、PipeWire 虚拟源和启动器。
- [x] `reboot loader` 返回 BootROM。

### 4.2 部分可用或需要重新验证

- [ ] HDMI OUT 热插拔后 HPD/EDID 状态可能不刷新；拔线后仍显示 connected。
- [ ] **Type-C DP 整体未闭环，不是只差 4K60。** 当前 `DP-1 disconnected`，
  Type-C partner 不存在；HUSB311/RT1711H 反复出现
  `SRC_READY -> disconnected -> TOGGLING`。历史配置曾抓到 4K30，
  但当前基线不能持续保持 Alt Mode。
- [ ] 相机 `90r` 方向等待用户最终目视确认；用户已确认 `90l` 会倒立。
- [ ] Wi-Fi/BT 设备已枚举，但完整新镜像上的重连和吞吐需回归。
- [ ] 硬解节点存在，但全 codec 矩阵和长时间稳定性未重新验收。
- [ ] RGA、JPEG、NPU 的 userspace 能力没有完成端到端基准。
- [ ] 加速度计已启用，但“相机自动跟随重力”尚未实现。
- [ ] `reboot sd`/`reboot emmc` 的 UI/用户态封装需回归；TF 本身未通。

### 4.3 明确未解决

- [ ] **TF 启动：U-Boot 初始化 TF 返回 `-EIO`。**
- [ ] **USB-C DP：partner/Alt Mode 不稳定，当前 `DP-1 disconnected`。**
- [x] **GT9110 触控：已完成电源修复并通过实机验证。**
- [x] **HYM8563 RTC：随共享电源链修复并通过实机验证。**
- [ ] HDMI IN mainline 采集链路。
- [ ] 相机随重力自动旋转服务。

### 4.4 未验证或不要声称已完成

- [ ] M.2 NVMe 启动。
- [ ] M.2 5G 模块实机联网。
- [ ] 硬件 JPEG encode。
- [ ] mainline H.264 encode。
- [ ] NPU Rocket userspace。
- [ ] 多显示器长期热插拔稳定性。

---

## 5. P0：TF 启动

### 5.1 目标启动优先级

```text
TF/eMMC 当前启动链 -> 同一链路 first -> TF -> USB -> eMMC
```

已有设计：

- `mmc0 = sdhci = eMMC`。
- `mmc1 = sdmmc = TF`。
- U-Boot 使用 `u-boot,spl-boot-order = "same-as-spl", &sdmmc, &sdhci`。
- U-Boot proper 应随后使用 `boot_targets`。

### 5.2 已确认事实

Linux 下 TF 卡可识别、ext4 可读，说明卡和槽的 Linux 运行态工作。

U-Boot 侧实测：

```text
mmc_init       = -EIO
card version   = 0
card caps      = 0
RCA            = 0
SCMI clock     = 400000 Hz, set OK
vmmc/vqmmc     = bound, 3.3 V, enabled
U-Boot PMU     = 0x11
PD_SDMMC       = absent
normal-world direct PMU RMW = ignored
SCMI pd get/on = -ENODEV / -ENODEV
```

当前 `0004-really-sdmmc-power-domain-in-spl.patch` 在 SPL 写：

```c
writel(readl(0xfd8d8150) | 0x2000, 0xfd8d8150);
```

该写法没有使 `PD_SDMMC` 真正上电，属于**未验证、可能应移除的实验补丁**。
接手 AI 不要因为补丁“有代码”就认为问题已修。

### 5.3 已排除

- [x] 卡座里是 FAT/坏卡不是唯一原因；Linux 可读 ext4。
- [x] `vcc_sd` 和 `vccio_sd_s0` 不是未绑定或 0 V。
- [x] U-Boot aliases 不是 `mmc1`/`mmc0` 写反。
- [x] 向 eMMC/TF 写入 U-Boot 的机械写入位置不是唯一问题。
- [x] 仅把 `&sdmmc` 加进 boot-order 不能解决。
- [x] Linux DTS 的 SD 属性不是当前 U-Boot 阶段的充分条件。

### 5.4 最可疑方向

**PD_SDMMC/SCMI/ATF 安全世界电源域初始化。** 当前 mainline U-Boot 只能访问
非安全世界，直接写 PMU 被忽略；SCMI 固件节点又没有暴露可用 power-domain
协议。下一步应对比：

- 原厂 vendor U-Boot + vendor BL31/OP-TEE 在 U-Boot 前对 `PD_SDMMC` 的操作。
- 原厂 SCMI/ATF 固件是否默认打开 SDMMC power domain。
- mainline ATF 是否有 RK3588 secure PMU backend，或是否需要增加安全调用。
- vendor U-Boot 的 SD host CMD0/CMD8 寄存器初始状态。

### 5.5 群友接串口后的最短诊断顺序

在 U-Boot 命令行执行：

```text
mmc list
mmc dev 1
mmc info
mmc part
ls mmc 1:1 /boot
```

同时抓完整串口启动日志，重点保存：

```text
Trying to boot from MMC2
mmc_init
no card present
PD_SDMMC
SCMI
clock/reset/power-domain
```

如果可进入 U-Boot shell，再检查：

```text
regulator list
regulator status
md.l 0xfd8d8150 1
```

不要只凭 `regulator status = enabled` 判定 SD 槽有电。必须继续确认
PD_SDMMC 是否真正解除门控。

### 5.6 验收标准

只有同时满足以下条件才算 TF 启动成功：

```text
U-Boot 能读取 TF 的 mmc 1:1 /boot/boot.scr
Linux 能正常启动并完成挂载
findmnt -n -o SOURCE,FSTYPE /
根分区来源是 TF ext4 UUID
```

曾经用于验证的 TF UUID：

```text
21e2f14a-ad69-4db5-872c-965c678ff425
```

如果根分区 UUID 仍是 eMMC，则实际仍从 eMMC 启动，不能算成功。

### 5.7 相关材料

```text
/home/user/device/rk3588-really/rk3588_livedeck_really/u-boot-mainline/TF-BOOT-STATUS.md
/home/user/github/build/patch/u-boot/v2026.07/board_really/0004-really-sdmmc-power-domain-in-spl.patch
/home/user/skysi-x5/backups/really-emmc-head-16m-20261115-1355.bin
/home/user/skysi-x5/artifacts/really-tf-boot-1115/
```

---

## 6. P0：GT9110 触控与 HYM8563 RTC（2026-11-16 已闭环）

### 6.1 最终结果

GT9110 和 HYM8563 均已恢复：

- GT9110 在 I2C4 `0x14` 正常通信并注册输入设备。
- HYM8563 在 I2C4 `0x51` 正常通信并注册 RTC。
- LT9211 在 I2C4 `0x2d` 保持正常。

根因与修复：

- 原厂 `vcc1v8_sys` 由 GPIO0_C0 控制，需要 regulator-fixed 和明确的
  GPIO-function/pull-up pinctrl。原来的 gpio-hog 没有提供同等依赖。
- 原厂 `vcc28_dvp` 是 always-on 2.8 V，GT9110 AVDD28 不应接 3.3 V。
- 最终映射为 `AVDD28=<&vcc28_dvp>`、`VDDIO=<&vcc1v8_sys>`。
- 修复后触控与 RTC 同时恢复，证明共同根因是 shared power/enable path。

### 6.2 修复前现场（历史证据）

系统输入设备里没有 Goodix 触控，仅有电源键、音频耳机检测、ADC keys、
mini keyboard：

```text
/proc/bus/input/devices  <- 无 Goodix Capacitive TouchScreen
```

内核日志持续出现：

```text
Goodix-TS 4-0014: Error reading 1 bytes from 0x8140: -6
Goodix-TS 4-0014: I2C communication failure: -6
```

`-6` 为 `-ENXIO`。

Android 12 对照基线已经采集，触控完全正常：

```text
input name       goodix-ts
event node       /dev/input/event6
I2C client       /sys/bus/i2c/devices/4-0014
device-tree path /i2c@feac0000/gt9xx@14
driver           Goodix-TS
raw X range      0..1080
raw Y range      0..1920
```

基线目录：

```text
/home/user/device/rk3588-really/reports/android-touch-baseline-20261115-1820/
```

四角触摸实测映射：

```text
top-left      X≈52  Y≈78
top-right     X≈1055 Y≈80
bottom-right  X≈1060 Y≈1875
bottom-left   X≈50  Y≈1875
center        X≈550 Y≈910
```

这直接证明：

- 触控硬件、排线、供电、上拉和 reset/IRQ 网络全部正常。
- 触控原生坐标系是 portrait `1080x1920`。
- 当前实验 DTS 已把 `touchscreen-size-x/y` 修正为 `1080/1920`，
  它与 Android 基线一致；该修正不解决 ENXIO。
- Android DTS 使用 `goodix,gt9xx`、`reset-gpio`、`touch-gpio`、
  `tp-size=<9110>`。
- mainline 使用 `goodix,gt9110`、`reset-gpios`、`irq-gpios`、
  `interrupts` 和 AVDD28/VDDIO supplies。
- Android runtime I2C4 节点没有 `clock-frequency` 属性。vendor 5.10 的
  `i2c_parse_timing()` 会回退到 `I2C_MAX_STANDARD_MODE_FREQ=100000`，所以
  Android 实测正常基线实际是 **100 kHz**；mainline 当前写 400 kHz，明显
  不一致。厂商源码重建树中的 400 kHz 与运行时 DTB 不符。
- HYM8563 也在同一条 I2C4 100 kHz 总线上正常工作。Android dmesg：

  ```text
  rtc-hym8563 4-0051: rtc information is valid
  rtc-hym8563 4-0051: registered as rtc0
  rtc-hym8563 4-0051: setting system clock to 2021-01-01T12:10:26 UTC
  ```

  因此 mainline 中 GT9110 和 HYM8563 同时失败，首要共同变量是 I2C4
  频率/控制器配置，而不是两个设备各自损坏。

原厂配置：

```text
I2C bus          4
GT9110 address   0x14
compatible       goodix,gt9110
reset GPIO       GPIO1_D3
IRQ GPIO         GPIO4_B0
HYM8563 address  0x51
```

### 6.3 已做过但无效（历史记录）

- reset/irq 极性对齐原厂。
- pinctrl 改为 pull-none。
- `tp-size = 9110`。
- regulator 保留和临时移除都试过。
- late-bind 服务。
- 手工复位时序。
- I2C 降速已试，且会影响 LT9211，不能继续降速。

### 6.4 已执行并验证的修复步骤

关闭本问题所执行的步骤：

1. 恢复 `vcc1v8_sys` regulator 到 GPIO0_C0。
2. 增加 `vcc1v8_sys_en` pinctrl：GPIO function + pull-up。
3. 删除原有 `vcc1v8_sys_hog`。
4. 恢复 always-on 2.8 V `vcc28_dvp`。
5. GT9110 VDDIO 改接 `vcc1v8_sys`，AVDD28 改接 `vcc28_dvp`。
6. 冷启动回归确认 GT9110、HYM8563、LT9211 三者均正常。

### 6.5 后续回归与安全禁忌

- 不要把 I2C4 降到 100 kHz 作为长期方案。
- 不要轻易 unbind LT9211，曾导致显示/SSH异常。
- 不要在用户会话直接改 Mutter monitor 配置来“修触控”。

---

## 7. USB 相机与方向

### 7.1 硬件

```text
USB ID      2757:1303
Name        Fic QHD CAMERA
Driver      uvcvideo
Capture     /dev/video6
Metadata    /dev/video7
Format      MJPG
```

### 7.2 当前实现

原 UVC PipeWire 节点被 WirePlumber 隐藏：

```text
/etc/wireplumber/wireplumber.conf.d/51-really-camera-hide.conf
```

虚拟相机由 GStreamer 提供：

```text
/usr/local/bin/really-camera-rotated
/etc/systemd/user/really-camera-rotated.service
```

处理链路：

```text
v4l2src 1920x1080@30 -> jpegdec -> videoflip 90r -> PipeWire Video/Source
```

桌面相机入口：

```text
/usr/local/share/applications/org.gnome.Snapshot.desktop
Exec=/usr/local/bin/really-camera-open
```

启动器会先停止旧虚拟相机、退出残留 Snapshot、启动虚拟相机、等待
PipeWire 节点出现，再启动全新 Snapshot。这样避免 “No camera Found”。

### 7.3 接手注意

- 必须通过桌面“相机”图标启动。
- 直接运行 `snapshot` 会绕过虚拟相机启动器。
- 调试用 `pw-cli ls Node` 和 `pw-link -l`，不要只看 `/dev/video6`。
- 出现 `MESA drmPrimeHandleToFD()` 警告不等于相机失败；以 PipeWire link
  和画面为准。
- 当前固定方向为 `90r`。用户已确认 `90l` 会得到倒立画面，`90r` 尚待最终
  目视确认。

---

## 8. STK8BAXX 加速度计与自动旋转

### 8.1 硬件和驱动

```text
Part         STK8BAXX
Bus          I2C6
Address      0x18
IRQ          GPIO4_B7
Driver       sensortek,stk8ba50
IIO name     stk8ba50
```

运行时手工实例化后已成功读取：

```text
in_accel_x_raw = -7
in_accel_y_raw = 239
in_accel_z_raw = -4
in_accel_scale = 0.038400
```

7.3 DTS 已补 `accelerometer@18` 节点，并安装到当前 DTB。重启后应由设备树
自动绑定。

### 8.2 自动旋转是否要做

物理规则：

- 设备树只能启用传感器、描述硬件。
- UVC 像素旋转不能写进设备树。
- 自动旋转必须由 userspace 读取 IIO 数据并动态设置 GStreamer `videoflip`。

建议：

- 直播机默认保持固定 `90r`。
- 自动旋转作为可选开关。
- 必须加角度阈值、去抖和锁定，避免轻微震动导致画面反复翻转。
- 内置屏幕和 Camera UI 若不同时自动旋转，只旋转相机可能与用户预期冲突。

---

## 9. HDMI、Type-C 与显示

### 9.1 已确认稳定

- LVDS 双链路 full-screen。
- 面板原生方向为 portrait。
- 背光 PWM 方向已经反向映射。

### 9.2 未稳定

- **Type-C DP 当前未闭环。** 当前运行态 `DP-1 disconnected`，
  `/sys/class/typec` 下只有 `port0`、没有 partner；日志反复显示
  HUSB311 在 `SRC_READY -> disconnected -> TOGGLING` 之间循环。
- 历史配置曾出现 `DP-1 connected`、Pin Assignment C 和完整 link
  training，并验证 4K30。该结果只能作为“链路具备潜力”的证据，
  不能作为当前镜像验收结论。
- Type-C DP 4K60 即使在此前成功状态下也不稳定。
- HDMI OUT 拔线后 HPD/EDID 可能保持 connected，导致桌面色深/模式协商异常。
- HDMI OUT 不插线时可能残留虚拟输出。
- HDMI IN mainline 仍需 open-source TF-A HDMIRX 支持及 LT6911 bridge/capture
  userspace 链路。

接手时先确认显示输出不要求 4K60。若要做动态 EDID，必须限制重试并有超时，
避免阻塞合成器。

### 9.3 Type-C DP 最终回归清单

群发给群友的镜像至少完成以下测试后才能标记闭环：

1. 冷启动不接 DP，再插入支持 3840x2160@30 的 DP 显示器。
2. 确认 DRM connector 为 connected，且没有右半屏缺失、花屏或链路重训失败。
3. 确认 `3840x2160@30` 模式实际生效，不要求 4K60。
4. 确认 Type-C DP 可作为 GNOME 主屏，内屏和 HDMI 保持可用。
5. 拔插 DP 至少两次，桌面合成器不能卡死。
6. 同时接 USB2 设备，确认 DP Alt Mode 没有把 USB2 一起断掉。

当前硬件限制：

- DP 与 USB3 共用 Type-C 高速 lane。
- 双 lane DP 只验收 4K30。
- 4K60 右半屏异常或不稳定属于已知风险，不作为群发验收条件。

---

## 10. 多媒体与加速器

当前内核暴露：

```text
rockchip-rga
rockchip,rk3328-vpu-dec
rockchip,rk3588-vepu121-enc
rockchip,rk3588-av1-vpu-dec
rkvdec
```

但“节点存在”不等于应用闭环。当前状态：

- VPU 解码：h264/hevc/vp9/av1 相关 V4L2 stateless 节点存在，需逐 codec
  重新跑 mpv/GStreamer 长测。
- H.264 encode：mainline wiring 不完整，仍可能走软件。
- JPEG encode：未形成最终验收记录。
- RGA：节点存在，userspace 加速路径未统一验收。
- NPU：kernel Rocket accel driver 有支持，但 Ubuntu/Mesa 默认 userspace
  不具备完整 Rocket Gallium 支持，`librknnrt.so` 不能直接用于 mainline
  rocket 接口。

不要把 vendor MPP/rknn 的二进制能力直接套到 mainline 上。

---

## 11. Android 触控基线抓取方案

### 11.1 推荐镜像

```text
/home/user/device/rk3588-really/EMMC-mod/android12-custom-1108/ExportImage-really-custom-1108.img
SHA256 903ee2932fec0d55f4a574ba1e37d7626e54f14c7dd2ee12b512f8100fd4a0a9
```

Loader：

```text
/home/user/device/rk3588-really/EMMC-mod/android12-custom-1108/artifacts/MiniLoaderAll-DC_Y588.bin
```

该镜像带 Android 12、ADB TCP 5555、Magisk root，适合抓数据，比未 root 的
纯原厂镜像方便。

**刷写前必须取得用户明确授权。**

### 11.2 抓取目录建议

```text
/home/user/device/rk3588-really/reports/android-touch-baseline-YYYYmmdd-HHMM/
```

### 11.3 必抓数据

```sh
adb wait-for-device
adb shell getprop
adb shell cat /proc/bus/input/devices
adb shell getevent -pl
adb shell dumpsys input
adb shell dumpsys display
adb shell dumpsys window displays
adb shell wm size
adb shell wm density
adb shell dmesg
adb shell logcat -d
```

设备树：

```sh
adb shell "su -c 'find /proc/device-tree -iname \"*gt9*\" -o -iname \"*touch*\"'"
adb shell "su -c 'find /proc/device-tree/i2c@fead0000 -maxdepth 2 -type f'"
```

对找到的 touch 节点逐项读取：

```sh
adb shell "su -c 'cat /proc/device-tree/.../compatible'"
adb shell "su -c 'cat /proc/device-tree/.../reg' | od -An -tx1"
adb shell "su -c 'cat /proc/device-tree/.../interrupts' | od -An -tx1"
adb shell "su -c 'cat /proc/device-tree/.../reset-gpio' | od -An -tx1"
adb shell "su -c 'cat /proc/device-tree/.../touch-gpio' | od -An -tx1"
```

I2C：

```sh
adb shell "su -c 'i2cdetect -y -r 4'"
adb shell "su -c 'i2cdetect -y -r 6'"
```

触控事件必须让用户依次点击屏幕四角、中心并画一条对角线，同时抓：

```sh
adb shell getevent -lt /dev/input/eventX
```

记录手指物理位置与 `ABS_MT_POSITION_X/Y` 的对应关系，用于判断轴方向和
坐标映射。

### 11.4 刷回 Linux

当前可用于恢复的 Linux 工件：

```text
/home/user/github/build/output/images/Armbian-unofficial_26.11.0-trunk_Really_resolute_edge_7.3.4_gnome_desktop.img
SHA256 9eb4f5726d337073a7d1e8a06f41ef5fd67fe9e5413ef1f15f702b5ce9585980
```

---

## 12. 构建与工作树

### 12.1 构建

```sh
cd /home/user/github/build
sudo ./compile.sh \
  RKBIN_GIT_REF=commit:98f106532c684c1741c10d027566bfd3662a4698 \
  really
```

本机未使用 Docker，`compile.sh` 会通过 sudo 重启自身。

### 12.2 当前主要未提交改动

```text
patch/kernel/archive/rockchip64-7.3/dt/rk3588-really.dts
patch/u-boot/v2026.07/defconfig/really-rk3588_defconfig
patch/u-boot/v2026.07/dt_uboot/rk3588-really-u-boot.dtsi
patch/u-boot/v2026.07/dt_upstream_rockchip/rk3588-really.dts
userpatches/config-really.conf
userpatches/customize-image.sh
userpatches/overlay/etc/systemd/system/power-mode.service
userpatches/overlay/usr/local/bin/power-mode.sh
```

`userpatches` 被 `.gitignore` 整体忽略，新增 overlay 文件需要 `git add -f`。
但本次相机虚拟源已改成由 `customize-image.sh` 内联生成，不再依赖新的
未跟踪 overlay 目录。

`userpatches/config-really.conf` 还含个人网络镜像策略，提交上游前必须拆分，
不要把个人镜像地址和社区板级支持混在一起。

### 12.3 相机临时产物

```text
/home/user/github/build/out/really-camera-rotation/
```

这是部署/调试镜像时使用的 staging 副本；长期来源是
`userpatches/customize-image.sh`。

---

## 13. 建议接手顺序

1. **串口接 TF 启动。** 这是当前最明确、最容易产生确定结论的 P0。
2. 记录完整社区 U-Boot SPL/U-Boot proper 日志。
3. 在 U-Boot 里验证 `mmc 1`、regulator、PD_SDMMC、SCMI。
4. 对比 vendor U-Boot/BL31 的 SDMMC power-domain 初始化。
5. 若 TF 仍不响应，暂缓“刷 TF 启动”工作，避免继续消耗轮次。
6. **Type-C DP 先稳定 partner/PD/VDM/extcon 状态，再验证 DP connector。**
7. GT9110/HYM8563 已通过共享电源修复闭环；后续只需做重启回归，
   不再重复更改 I2C4、GPIO 极性或 Goodix compatible。
8. 继续处理自动旋转、HDMI 热插拔、硬解/NPU 长测。

---

## 14. 禁止事项

- 不得在无用户明确授权时擦除 eMMC、写 MaskROM 整盘或刷 Android。
- 不得只因为“Linux 能看到 TF”就宣称 TF 启动已修。
- 不得把 `pkill` 旧的 Snapshot 当成相机故障本身；这是启动器正确行为。
- 不得直接运行 `snapshot` 后判断 USB 相机不存在。
- 不得把 I2C4 降到 100 kHz 并作为最终修复。
- 不得在用户会话强制重配 Mutter 多屏来修触控。
- 不得回退 LVDS 双链路、PWM 反向亮度表、ES8388 I2S1 M0。
- 不得把个人网络镜像配置混入板级社区提交。
- 不确定的硬件操作前先备份；串口日志、DTB 和完整镜像都保留 SHA256。

---

## 15. 快速现场命令

```sh
# 系统
uname -a
systemctl is-active gdm3
systemctl --user is-active pipewire pipewire-pulse wireplumber

# 显示与亮度
cat /sys/class/drm/card*-LVDS-1/status
cat /sys/class/backlight/backlight/brightness

# 音频
aplay -l

# 网络
nmcli device
rfkill list

# GPS
systemctl is-active gpsd
gpspipe -w -n 3

# 摄像头
v4l2-ctl --list-devices
pw-cli ls Node
pw-link -l
pgrep -a snapshot
systemctl --user status really-camera-rotated.service

# 加速度计
for d in /sys/bus/iio/devices/iio:device*; do
  [ -f "$d/name" ] && cat "$d/name"
done

# 触屏
cat /proc/bus/input/devices
sudo dmesg | grep -Ei 'goodix|gt9|hym8563'
sudo i2cdetect -y -r 4

# TF/U-Boot
# 在 U-Boot 命令行执行 mmc list / mmc dev 1 / mmc info / mmc part
```

## 2026-11-15 21:30 当前现场复核

最近完整 mainline `edge 7.3.4` 镜像 SHA256：

```text
9eb4f5726d337073a7d1e8a06f41ef5fd67fe9e5413ef1f15f702b5ce9585980
```

当前运行态：

```text
kernel           7.3.4-edge-rockchip64 #61
DTB SHA256       98cb2541226cdc34ff269040f4b99cc30c21e159b15545d6709ef5688f4f9b84
LVDS-1           connected
HDMI-A-1         disconnected (currently no HDMI sink)
DP-1             disconnected
Type-C partner   absent
USB camera       2757:1303 present
Goodix input     absent
```

`i2cdetect -y -r 4` 只显示 `0x2d` 为 `UU`，表示 LT9211 驱动占用；
`0x14` 和 `0x51` 均无 ACK。`/sys/bus/i2c/devices/4-0014/driver` 与
`4-0051/driver` 都不存在。

已试过 100/400 kHz、reset/IRQ ACTIVE_LOW/ACTIVE_HIGH、
pull-up/pull-none、late-bind，以及 `mipi_cam_pwen` 常开供电，均未解决。
tracefs 曾证明 Goodix reset/IRQ descriptor 都成功取得；probe 失败后
devm 自动释放，因此事后再看 gpioinfo 不能说明“GPIO 没申请”。

Type-C 当前 DTB 仍使用：

```text
SBU1       GPIO3_A0
SBU2       GPIO1_B2
DP lanes   <2 3>
USB 5V     GPIO4_A6
extcon     typec-extcon bridge
```

这组 GPIO/lane 配置曾进入完整 link training，所以不能简单判定为
“SBU 全错”。当前主要未解释项是 Type-C partner 为何在 PD/VDM 完成后
仍反复 detach，以及 extcon `dp` cable 状态与 HPD 的同步时机。

现场证据和后续命令见：

```text
reports/mainline-open-issues-20261115-2130/README.md
```
