# Really TVI2340R — HDMI IN 双路待办（未闭环）

- 记录时间：2026-11-16 16:40
- 记录者：天禧 AI（依据 192.168.3.28 `/home/user/device/rk3588-really/` 实测）
- 适用：Really TVI2340R（`rockchip,rk3588-tvi2340r`），Android 5.10 + mainline 7.3
- 关联：`../mainline-open-issues-20261115-2130/README.md`

---

## 一、结论摘要

面板 HDMI IN **不是 LT6911 桥接**，而是 RK3588 SoC 内置 HDMIRX
（`hdmirx_ctrler` @ `fdee0000`）。LT6911C 属于机身内部的**隐藏第二路**，
不引到面板。两路互相独立，不能混为一谈。

两个待办，优先级不同：

| # | 待办 | 物理口 | 状态 |
|---|---|---|---|
| 1 | 面板 HDMI IN（内置 HDMIRX）mainline 无法出图 | 面板 | **P0，未闭环** |
| 2 | 内部隐藏 HDMI IN（LT6911C → CSI）驱动未编译 | 机身内部 | P2，低优先 |

**此前的错误结论已撤回**：曾记为「原厂 5.10 dtb 未启用 HDMI RX，所以
HDMI IN 不可用」。这与事实不符——原厂 `hdmirx_ctrler` 一直是
`status = "okay"`，Android 下面板 IN 完全可用。

---

## 二、两路 HDMI IN 的确定事实

### 2.1 硬件拓扑

```text
面板 HDMI IN ──────> RK3588 SoC 内置 HDMIRX @ fdee0000
                     （无桥接芯片，直连 SoC）

机身内部隐藏口 ────> LT6911C @ I2C6 0x2b ──> MIPI CSI-2
                     （csi2_dphy0 -> mipi2_csi2 -> rkcif_mipi_lvds2）
```

面板口拆机确认**无** LT6911UXC 芯片；带该芯片的另一路只存在于机身内部。

### 2.2 原厂 Android 5.10 设备树证据

`docs/rk3588-tvi2340r-orig.dts`（10385 行，从原厂 dtb 完整反编译）：

```text
&hdmirx_ctrler {                          # 行 3447，面板口
    compatible = "rockchip,rk3588-hdmirx-ctrler", "rockchip,hdmirx-ctrler";
    reg = <0 4260233216 0 24576>;         # 0xfdee0000, 0x6000
    power-domains = <&power 26>;          # RK3588_PD_VO1
    interrupts = <0 177 4 0 436 4 0 179 4>;
    interrupt-names = "cec", "hdmi", "dma";
    pinctrl-0 = <&hdmim1_rx_hpdin &hdmim1_rx_scl
                 &hdmim1_rx_sda &hdmirx_det>;
    status = "okay";                      # ← 原厂是启用的
    hpd-trigger-level = <1>;
    hdmirx-det-gpios = <323 22 1>;        # 323=0x143=&gpio4, pin22 -> GPIO4_C6, ACTIVE_LOW
};

lt6911uxc2: lt6911uxc2@2b {               # 行 863，内部隐藏口
    compatible = "lontium,lt6911uxc2";
    reg = <43>;                           # I2C6, 0x2b
    clocks = <&ext_cam_clk>;
    power-domains = <&power 27>;          # RK3588_PD_VI
    interrupts = <23 4>;                  # &gpio1 RK_PC7
    reset-gpios = <257 7 0>;              # &gpio1 RK_PB7
    hpd-ctl-gpios = <374 19 0>;           # &gpio2 RK_PC3
    status = "okay";
    port { hdmiin_out1: endpoint {
        remote-endpoint = <&mipi_in_dphy0>;
        data-lanes = <1 2 3 4>; }; };
};
```

注意：LT6911 那路的音频 `hdmiin2-lt6911c-sound` 原厂就是 `status = "disabled"`，
面板内的 `hdmiin-sound`（`rockchip,hdmiin`，走 I2S）才是启用的。

### 2.3 Android 运行时证据（面板口 = 内置 HDMIRX）

自写 App 走的就是内置 HDMIRX，不是 CSI：

```text
hdmi-viewer/src/main/cpp/hdmirx.cpp:35
    constexpr const char *kVideoDevice = "/dev/video31";

hdmi-viewer/src/main/cpp/hdmirx.cpp:612-621
    xioctl(fd, VIDIOC_G_EDID, &current)
    xioctl(fd, VIDIOC_S_EDID, &edid)      # HDMI RX 独有 ioctl，CSI 不可能有
```

`DEVICE-HANDOVER.md` §14.1：

```text
/dev/video31 是 stream_hdmirx，CameraService 映射为 cameraId=231
```

`docs/HDMI-IN-DIAGNOSIS.md` §9 记录了 2026-11-01 的完整闭环实测：

| 观测点 | 修复前 | 修复后 |
|---|---|---|
| `rk_hdmirx-5v` 中断 | 0 | 2 |
| `gpio-61 (hdmirx-det)` | `in hi` | `in lo` |
| `extcon5/state` | `VIDEO-IN=0` | `VIDEO-IN=1` |
| `hdmirx/status` | `disconnected` | `connected` |
| DV timings | 640x480@59.94 兜底 | **1920x1080@60, 148.5MHz** |

抓流验证：`--stream-count=3` 得到 18662400 字节 = 6 帧 1080p NV12，
Y 均值 42.2、非黑像素 99.0%。DMA 中断 0 → 4421。

**结论：Android 下软硬件链路完全正常。面板 HDMI IN 可正常出图。**

---

## 三、待办 1（P0）：mainline 7.3 面板 HDMI IN 不出图

### 3.1 当前状态

仓库 `dts-7.3-linux/rk3588-really.dts:687` 已声明启用：

```dts
&hdmi_receiver {
    /* Primary HDMI input, handled directly by RK3588's SoC HDMIRX. */
    hpd-gpios = <&gpio4 RK_PC6 GPIO_ACTIVE_LOW>;
    hpd-is-active-low;
    pinctrl-names = "default";
    pinctrl-0 = <&hdmim1_rx_cec &hdmim1_rx_hpdin
                 &hdmim1_rx_scl &hdmim1_rx_sda &hdmirx_hpd>;
    status = "okay";
};

&hdmi_receiver_cma { status = "okay"; };
```

磁盘 DTB `/boot/dtb-7.3.4-edge-rockchip64/rockchip/rk3588-really.dtb`
解析结果同样是 `status = "okay"`、CMA `okay`、`phandle` 正常。

但驱动始终未绑定，`/sys/devices/platform/fdee0000*` **不存在**，
`/sys/class/video4linux/` 下无 hdmirx 节点。

### 3.2 已排除项（在 192.168.3.28 上实测）

| 检查 | 结果 |
|---|---|
| 内核配置 | `CONFIG_VIDEO_SYNOPSYS_HDMIRX=m` 已启用 |
| 模块文件 | `synopsys-hdmirx.ko` 存在 |
| 模块 modinfo alias | `of:N*T*Crockchip,rk3588-hdmirx-ctrler` 匹配 DTS |
| 手动 `modprobe synopsys_hdmirx` | **加载成功**（lsmod 可见，45056 字节） |
| 模块依赖/黑名单 | 无依赖，无 blacklist |
| 加载后平台设备 | **仍未注册** |
| DTB compatible | `"rockchip,rk3588-hdmirx-ctrler","snps,dw-hdmi-rx"` 正确 |
| 内核源码 of_match | `snps_hdmirx.c:2810` → `rockchip,rk3588-hdmirx-ctrler` 完全匹配 |

设备树齐全、驱动能加载、字符串能匹配，但 platform device 不生成。
说明卡在 **TF-A / BL31 层**，不是 DTS 也不是模块加载。

### 3.3 关键前置：必须在 Really 上验证，不是 Skysi X5

**192.168.3.28 实际是 Skysi X5，不是 Really。**

```text
hostname                     skysi-x5
/sys/firmware/devicetree/base/compatible
                             rockchip,rk3588-skysi-x5 rockchip,rk3588
/boot/armbianEnv.txt         fdtfile=rockchip/rk3588-skysi-x5.dtb
运行时 status                disabled          ← Skysi 的 DTB 是灰的
磁盘 rk3588-really.dtb       okay              ← 但根本没在用
```

这解释了先前「磁盘 okay、运行时 disabled」的表象差异：**当前机器加载的
是 Skysi X5 的 DTB**，那上面 `hdmi_receiver` 本来就是 disabled。
本次排查中一度把它当成 Really 的运行时状态，已纠正。

因此：**上面 3.1/3.2 的结论需要在真正的 Really 设备上复验**，尤其
`/sys/devices/platform/fdee0000*` 是否真的缺失。若在 Really 上设备已注册，
问题就只剩 userspace，难度大幅下降。

### 3.4 验证命令（在 Really 上执行）

```bash
# 1. 确认是 Really 而非 Skysi
cat /sys/firmware/devicetree/base/compatible
grep fdtfile /boot/armbianEnv.txt

# 2. 设备树节点状态
cat /sys/firmware/devicetree/base/hdmi_receiver@fdee0000/status

# 3. platform device 是否绑定
ls -d /sys/devices/platform/fdee0000* 2>/dev/null || echo "未注册"

# 4. video 节点枚举
for v in /sys/class/video4linux/video*; do
    echo "$(basename $v): $(cat $v/name 2>/dev/null)"; done | grep -i hdmi

# 5. 驱动侧日志
sudo dmesg | grep -iE 'hdmirx|snps|dw-hdmi-rx'

# 6. 手动加载并观察
sudo modprobe synopsys_hdmirx
sudo dmesg | tail -30
```

### 3.5 预期卡点与后续路径

若确认 device 未注册，按此顺序推进：

1. **TF-A**：RK3588 HDMIRX 需要 BL31 内的固件/时钟初始化支持。
   上游 open-source TF-A 对此的支持程度需核实
   （参考 `dts-6.1-linux/FIXES.md`、`AI-HANDOVER-CHECKLIST:579`
   已记录「HDMI IN mainline 仍需 open-source TF-A HDMIRX 支持」）。
2. **HPD 属性名差异（引脚一致，已核实）**：
   原厂 `hdmirx-det-gpios = <&gpio4 RK_PC6 ACTIVE_LOW>` + `hpd-trigger-level = <1>`；
   mainline `hpd-gpios = <&gpio4 RK_PC6 GPIO_ACTIVE_LOW>` + `hpd-is-active-low`。
   **引脚完全相同**，只是 vendor 私有属性名换成了 mainline 的通用 `hpd-gpios`。
   这一点不构成差异，无需再查。
3. **userspace**：mainline 用 `snps,dw-hdmi-rx` 标准 V4L2 接口，
   与 vendor `rk_hdmirx` 的 `hdmirx/hdmirx/*` sysfs 和私有 ioctl 不兼容。
   现有 `hdmi-viewer` App 的 `VIDIOC_S_EDID` 路径需重新对接。

### 3.6 已核实：HPD 引脚与原厂一致，不是差异点

原厂 DTB 解析（`dtb-5.10-android/rk3588-really.dtb`）：

```text
hdmirx-det-gpios = <0x143 0x16 0x01>
  0x143 = 323 -> phandle，反查是 gpio@fec50000 = gpio4
  0x16  = 22  -> pin 22
  0x01        -> GPIO_ACTIVE_LOW
=> GPIO4_C6 ACTIVE_LOW
```

mainline 7.3 DTS 写的是 `hpd-gpios = <&gpio4 RK_PC6 GPIO_ACTIVE_LOW>`，
**同一根引脚**。

pinctrl 逐项对照（原厂 DTB vs mainline `rk3588-base-pinctrl.dtsi`）：

| 信号 | 原厂 | mainline `hdmim1_rx_*` | 结果 |
|---|---|---|---|
| HPDIN | bank3 pin28 = GPIO3_D4 | `<3 RK_PD4 5>` = GPIO3_D4 | 一致 |
| SCL | bank3 pin26 = GPIO3_D2 | `<3 RK_PD2 5>` = GPIO3_D2 | 一致 |
| SDA | bank3 pin27 = GPIO3_D3 | `<3 RK_PD3 5>` = GPIO3_D3 | 一致 |
| DET | bank4 pin22 = GPIO4_C6 | `<4 RK_PC6 GPIO>` = GPIO4_C6 | 一致 |

**结论：7.3 mainline 的 HDMI IN 引脚配置完全正确，与原厂逐根对齐。**
先前的「引脚不一致」判断是把 `323` 误读成 gpio1 bank 编号导致的，
已撤回。排查方向应从引脚转向 TF-A 与驱动绑定。

## 四、待办 2（P2）：内部隐藏 HDMI IN（LT6911C）

优先级低——该口未引到面板，用户日常不可达，但设备树已写入且会造成
无效 probe。

### 4.1 当前状态

`dts-7.3-linux/rk3588-really.dts:860`：

```dts
&i2c6 {
    lt6911: bridge@2b {
        compatible = "lontium,lt6911uxc2";
        reg = <0x2b>;
        clocks = <&ext_cam_clk>;
        interrupts = <&gpio1 RK_PC7 IRQ_TYPE_LEVEL_LOW>;
        reset-gpios = <&gpio3 RK_PA7 GPIO_ACTIVE_HIGH>;
        hpd-ctl-gpios = <&gpio2 RK_PC3 GPIO_ACTIVE_HIGH>;
        power-domains = <&power RK3588_PD_VI>;
        status = "okay";
        port { lt6911_out: endpoint {
            remote-endpoint = <&csi2_input>;
            data-lanes = <1 2 3 4>; }; };
    };
};
```

### 4.2 阻塞点

芯片丝印已确认 **LT6911C**，据此外部核对（详见 §4z.2）：

- **vendor 6.1 有 `lt6911c.c` 驱动**（compatible `lontium,lt6911c`，
  校验芯片 ID `0x0516` @ 寄存器 `0xA000`），但配置里
  `# CONFIG_VIDEO_LT6911C is not set` —— **驱动从未被编译**。
- DTS 写的 `lontium,lt6911uxc2` 与任何驱动都不匹配。
  原厂也是这么写的，说明原厂用的是一份 ODM 私有驱动，我们没有。
- LT6911C 与 LT6911UXC 读不同寄存器（`0xA000` vs `0x8100`），
  **不能**用 `lt6911uxc.c` 顶替，必须用 `lt6911c.c`。
- 中断极性当前写 `LEVEL_LOW`，原厂是 `LEVEL_HIGH`。
- CSI 链路需同步启用：`csi2_dphy0` → `mipi2_csi2` → `rkcif_mipi_lvds2`。
  7.3 这三处一个都没启用。

### 4.3 建议

若短期不做，**建议把该节点改为 `status = "disabled"`**，
避免一个永远 probe 失败的设备污染 dmesg 启动日志。

若要做，最小改动见 §4z.3 第 3 条。

---

## 四之二、构建树实测核查（`/home/user/github/build`）

核查对象：

```text
patch/kernel/archive/rockchip64-7.3/dt/rk3588-really.dts          # mainline 7.3
patch/kernel/rk35xx-vendor-6.1/dt/rk3588-really.dts              # vendor 6.1
```

7.3 源文件与 worktree 完全一致（md5 `851716026d5e...`）。
6.1 源文件与 worktree 有差异，但仅 `&edp0` 一处注释措辞，无实质影响。

### 4z.1 面板口（内置 HDMIRX）—— 配置正确

**mainline 7.3**（`rk3588-really.dts:687`）：

```dts
&hdmi_receiver {
	hpd-gpios = <&gpio4 RK_PC6 GPIO_ACTIVE_LOW>;
	hpd-is-active-low;
	pinctrl-names = "default";
	pinctrl-0 = <&hdmim1_rx_cec &hdmim1_rx_hpdin
		     &hdmim1_rx_scl &hdmim1_rx_sda &hdmirx_hpd>;
	status = "okay";
};
&hdmi_receiver_cma { status = "okay"; };
```

逐项对照原厂，**全部正确**：

| 项 | 原厂 | 7.3 mainline | 结果 |
|---|---|---|---|
| 控制器 | `rockchip,rk3588-hdmirx-ctrler` @fdee0000 | 同（内核 dtsi 提供） | ✅ |
| HPD | `hdmirx-det-gpios=<&gpio4 RK_PC6 ACTIVE_LOW>` | `hpd-gpios=<&gpio4 RK_PC6 GPIO_ACTIVE_LOW>` | ✅ 同引脚 |
| HPDIN | `<3 RK_PD4 5>` GPIO3_D4 | `hdmim1_rx_hpdin` = GPIO3_D4 | ✅ |
| SCL | `<3 RK_PD2 5>` GPIO3_D2 | `hdmim1_rx_scl` = GPIO3_D2 | ✅ |
| SDA | `<3 RK_PD3 5>` GPIO3_D3 | `hdmim1_rx_sda` = GPIO3_D3 | ✅ |
| DET pinctrl | `<4 RK_PC6 func0 pull_up>` | 自定义 `hdmirx_hpd` 同配置 | ✅ |
| CMA | 需要，原厂预留 | `hdmi_receiver_cma` okay | ✅ |
| status | `okay` | `okay` | ✅ |

**结论：7.3 面板口设备树配置无误，问题不在 DTS。**

**vendor 6.1**（`rk3588-really.dts:603`）：

```dts
&hdmirx_ctrler {
	hpd-trigger-level = <1>;
	hdmirx-det-gpios = <&gpio4 RK_PC6 GPIO_ACTIVE_LOW>;
	pinctrl-names = "default";
	pinctrl-0 = <&hdmim1_rx &hdmirx_det>;
	status = "okay";
};
```

`hdmim1_rx` 在 6.1 内核 `rk3588s-pinctrl.dtsi:599` 是组合组，含
CEC(GPIO3_D1)/SCL(GPIO3_D2)/SDA(GPIO3_D3)/HPDIN(GPIO3_D4) 四根，
DET 单独在 `hdmirx_det`。**与原厂完全对齐，配置正确。**

### 4z.2 内部隐藏口 —— 芯片丝印已确认为 LT6911C

用户拆机确认丝印为 **LT6911C**（不是 UXC2）。按此重新核对，结论变了：
vendor 6.1 **有**匹配的驱动，问题出在内核配置和 compatible 字符串上。

#### 驱动侧事实

vendor 6.1 自带三个 Lontium 驱动，各自校验不同的芯片 ID：

| 驱动 | compatible | 芯片 ID 寄存器 | 期望值 |
|---|---|---|---|
| `lt6911c.c` | `lontium,lt6911c` | `0xA000`/`0xA001` | `0x0516` |
| `lt6911uxc.c` | `lontium,lt6911uxc` | `0x8100`/`0x8101` | `0x0417` |
| `lt6911uxe.c` | `lontium,lt6911uxe` | — | — |

**关键：LT6911C 与 LT6911UXC 读的是完全不同的寄存器地址**
（`0xA000` vs `0x8100`）。所以**不能**靠改 compatible 蒙混，
必须用对驱动——幸好 `lt6911c.c` 已经存在。

#### 真正的问题：驱动没被编译

```text
config/kernel/linux-rk35xx-vendor.config:1819  CONFIG_VIDEO_LT6911UXC=y
config/kernel/linux-rk35xx-vendor.config:1820  CONFIG_VIDEO_LT6911UXE=m
（无 CONFIG_VIDEO_LT6911C）

worktree .config:5138  # CONFIG_VIDEO_LT6911C is not set
```

驱动源码在、Makefile 和 Kconfig 都在，但**配置没打开**，所以 `lt6911c.o`
从未被编译。DTS 里写 `lontium,lt6911uxc2` 或 `lontium,lt6911c` 都一样，
因为根本没有这个驱动参与匹配。

CSI 子系统本身是齐的：

```text
CONFIG_VIDEO_ROCKCHIP_CIF=y
CONFIG_PHY_ROCKCHIP_CSI2_DPHY=y
```

#### DTS 侧：compatible 写错，引脚基本正确

原厂 DTB 里 `lt6911uxc2@2b` 的 compatible 也是 `lontium,lt6911uxc2`——
说明**原厂用的是一份我们没有的厂商驱动**（厂商把 C 版芯片挂在 uxc2
的 compatible 下，属于 ODM 私有的绑定方式）。vendor 6.1 主线化的
`lt6911c.c` 用的是规范的 `lontium,lt6911c`，两者不通用。

引脚对照（原厂 DTB 解码 vs 当前 DTS）：

| 属性 | 原厂 | 当前 6.1/7.3 DTS | 结果 |
|---|---|---|---|
| `reset-gpios` | gpio3 pin7 = GPIO3_A7, ACTIVE_HIGH | `<&gpio3 RK_PA7 GPIO_ACTIVE_HIGH>` | ✅ 一致 |
| `hpd-ctl-gpios` | gpio2 pin19 = GPIO2_C3, ACTIVE_HIGH | `<&gpio2 RK_PC3 GPIO_ACTIVE_HIGH>` | ✅ 一致 |
| `interrupts` 引脚 | gpio1 pin23 = GPIO1_C7 | `<&gpio1 RK_PC7>` | ✅ 引脚一致 |
| `interrupts` 极性 | `0x04` = LEVEL_**HIGH** | `IRQ_TYPE_LEVEL_**LOW**` | ❌ **极性相反** |
| `compatible` | `lontium,lt6911uxc2`（私有） | 同 | ⚠️ 无匹配驱动 |

#### 7.3 另外还缺东西

- 设备树写了 `&csi2 { status = "okay" }`，但
  **`csi2_dphy0` / `mipi2_csi2` / `rkcif_mipi_lvds2` 一个都没启用**，
  CSI 管道是断的。
- `linux-rockchip64-edge.config` 没有 `CONFIG_VIDEO_LT6911C`，
  且该版本 `lt6911uxe.c` 只有 ACPI 匹配表、无 of_match。
- 已装内核 `/lib/modules/7.3.4-edge-rockchip64/` 下无任何 lt6911 模块。

### 4z.3 建议（按优先级）

面板口 P0 不受影响，以下是内部口的独立工作项：

1. **面板口 DTS 保持不动**，排查直接跳 TF-A / 驱动绑定，不要再动引脚。
2. **内部口短期不做 → 两份 DTS 都置 `status = "disabled"`**，
   避免 dmesg 噪音。
3. **要做的话，最小改动路径（vendor 6.1）**：
   - 打开 `CONFIG_VIDEO_LT6911C=y`（Kconfig 依赖：`VIDEO_DEV && I2C`，
     select `HDMI`/`MEDIA_CONTROLLER`/`VIDEO_V4L2_SUBDEV_API`/`V4L2_FWNODE`，
     这些在 vendor 配置里都满足）；
   - DTS 把 `compatible` 改成 `lontium,lt6911c`；
   - 中断极性按原厂改成 `IRQ_TYPE_LEVEL_HIGH`（需实测确认）；
   - CSI 链路 `csi2_dphy0` / `mipi2_csi2` / `rkcif_mipi_lvds2` 全部使能。
4. **验证芯片 ID**：驱动 probe 会打 `check chipid ok, id:0x516`。
   若打出 `chipid err, read:0xXXXX, expect:0x516`，说明丝印判断有误，
   需回头核对是不是真的 C 版。

## 五、与既往结论的差异记录（避免重复踩坑）

| 既往说法 | 实际情况 | 依据 |
|---|---|---|
| 原厂 5.10 dtb 未启用 HDMI RX | **错**。原厂 `hdmirx_ctrler` 是 `okay` | `rk3588-tvi2340r-orig.dts:3464` |
| 面板 HDMI IN 走 LT6911UXC | **错**。面板走内置 HDMIRX，LT6911 在内部隐藏口 | 拆机 + `hdmirx.cpp` 用 `VIDIOC_S_EDID` |
| 192.168.3.28 是 Really | **错**。是 Skysi X5（`rk3588-skysi-x5`） | `armbianEnv.txt` / `compatible` |
| mainline DTS 未写 HDMI IN | **错**。7.3 和 6.1 dts 都已写，且 `okay` | `dts-7.3-linux/rk3588-really.dts:687` |
| 内部口芯片是 LT6911UXC2 | **错**。拆机丝印是 **LT6911C** | 用户拆机确认 |
| 原厂 HPD 用 gpio1 RK_PD6，与 mainline 不一致 | **错**。`323`=phandle 指向 gpio4，实际同为 GPIO4_C6 | 原厂 DTB 反查 `phandle = <0x143>` |
| 内部口没有可用驱动 | **错**。vendor 6.1 有 `lt6911c.c`，只是 `CONFIG_VIDEO_LT6911C` 未开 | worktree `.config:5138` |

---

## 六、验收标准

面板 HDMI IN 闭环需同时满足：

1. `/sys/devices/platform/fdee0000*` 存在且驱动绑定成功；
2. `/sys/class/video4linux/` 出现 hdmirx 对应节点（名称含 hdmi）；
3. 插入 1080p 信号源后，`v4l2-ctl --get-dv-timings` 返回真实时序
   （不再是 640x480@59.94 兜底值）；
4. `v4l2-ctl --stream-mmap=3 --stream-count=3 --stream-to=/tmp/f.raw`
   取得 1080p 有效帧，Y 分量非黑像素占比 > 90%；
5. 拔插可重复，至少 3 次冷启动 + 3 次热插拔无回归。

---

## 七、下一步

1. **在真正的 Really 上**执行 3.4 的六条验证命令，确认
   `fdee0000` 是否注册（这是唯一未定的关键事实）。
2. 若未注册 → 复核 3.6 的 HPD 引脚（GPIO1_D6 vs GPIO4_C6）。
3. 若引脚修正后仍不注册 → 转向 TF-A BL31 侧 HDMIRX 支持。
4. 视情况将 `lt6911` 节点先置 `disabled`，清理 dmesg 噪音。
