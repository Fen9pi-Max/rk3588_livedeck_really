# Really TVI2340R — HDMI IN 双路待办（未闭环）

- 记录时间：2026-11-16 16:40
- 记录者：天禧 AI（依据 192.168.3.28 `/home/user/device/rk3588-really/` 实测）
- 适用：Really TVI2340R（`rockchip,rk3588-tvi2340r`），Android 5.10 + mainline 7.3
- 关联：`../mainline-open-issues-20261115-2130/README.md`

---

## 一、结论摘要

面板 HDMI IN **不是 LT6911 桥接**，而是 RK3588 SoC 内置 HDMIRX
（`hdmirx_ctrler` @ `fdee0000`）。LT6911UXC2 属于机身内部的**隐藏第二路**，
不引到面板。两路互相独立，不能混为一谈。

两个待办，优先级不同：

| # | 待办 | 物理口 | 状态 |
|---|---|---|---|
| 1 | 面板 HDMI IN（内置 HDMIRX）mainline 无法出图 | 面板 | **P0，未闭环** |
| 2 | 内部隐藏 HDMI IN（LT6911UXC2 → CSI）mainline 无驱动 | 机身内部 | P2，低优先 |

**此前的错误结论已撤回**：曾记为「原厂 5.10 dtb 未启用 HDMI RX，所以
HDMI IN 不可用」。这与事实不符——原厂 `hdmirx_ctrler` 一直是
`status = "okay"`，Android 下面板 IN 完全可用。

---

## 二、两路 HDMI IN 的确定事实

### 2.1 硬件拓扑

```text
面板 HDMI IN ──────> RK3588 SoC 内置 HDMIRX @ fdee0000
                     （无桥接芯片，直连 SoC）

机身内部隐藏口 ────> LT6911UXC2 @ I2C6 0x2b ──> MIPI CSI-2
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
    hdmirx-det-gpios = <323 22 1>;        # &gpio1 RK_PD6 ACTIVE_LOW
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
2. **对比 vendor 与 mainline 的 hpd 属性**：
   原厂是 `hpd-trigger-level = <1>` + `hdmirx-det-gpios = <&gpio1 RK_PD6 ACTIVE_LOW>`；
   mainline 用的是 `hpd-gpios = <&gpio4 RK_PC6 ACTIVE_LOW>` + `hpd-is-active-low`。
   引脚和属性名都不同，需确认哪个才是本板真实走线。**这是首要差异点。**
3. **userspace**：mainline 用 `snps,dw-hdmi-rx` 标准 V4L2 接口，
   与 vendor `rk_hdmirx` 的 `hdmirx/hdmirx/*` sysfs 和私有 ioctl 不兼容。
   现有 `hdmi-viewer` App 的 `VIDIOC_S_EDID` 路径需重新对接。

### 3.6 首查项：HPD 引脚冲突

原厂 `hdmirx-det-gpios = <323 22 1>` → **`&gpio1 RK_PD6`**，
mainline 写 `hpd-gpios = <&gpio4 RK_PC6>` → **GPIO4_C6**。

两者不是同一根引脚。需先确认：

- Really 面板 HDMI IN 的 HPD/检测脚究竟接 GPIO1_D6 还是 GPIO4_C6；
- 原厂 `pinctrl-0` 用的是 `hdmim1_*`，mainline 也写 `hdmim1_*`，这一项一致；
- 若 mainline 指错引脚，HPD 永远读不到插入，驱动会直接 probe 失败或静默。

**建议第一步就用万用表/原厂 sysfs 确认该脚实际编号。**

---

## 四、待办 2（P2）：内部隐藏 HDMI IN（LT6911UXC2）

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

- mainline 7.3 内核**没有** `lontium,lt6911uxc2` 驱动。
  `/lib/modules/7.3.4-edge-rockchip64/` 下无任何匹配模块，
  `modules.alias` 无对应条目 → 该节点静默不 probe。
- vendor 5.10 有 `drivers/media/i2c/lt6911uxc.c`（compatible 为
  `lontium,lt6911uxc`，**注意不是 `lt6911uxc2`**），移植需重写。
- CSI 链路需同步启用：`csi2_dphy0` → `mipi2_csi2` → `rkcif_mipi_lvds2`。
  原厂 `&rkcif_mipi_lvds2` 走 `mipi2_csi2_output`。

### 4.3 建议

若短期不做，**建议把该节点改为 `status = "disabled"`**，
避免一个永远 probe 失败的设备污染 dmesg 启动日志。

---

## 五、与既往结论的差异记录（避免重复踩坑）

| 既往说法 | 实际情况 | 依据 |
|---|---|---|
| 原厂 5.10 dtb 未启用 HDMI RX | **错**。原厂 `hdmirx_ctrler` 是 `okay` | `rk3588-tvi2340r-orig.dts:3464` |
| 面板 HDMI IN 走 LT6911UXC | **错**。面板走内置 HDMIRX，LT6911 在内部隐藏口 | 拆机 + `hdmirx.cpp` 用 `VIDIOC_S_EDID` |
| 192.168.3.28 是 Really | **错**。是 Skysi X5（`rk3588-skysi-x5`） | `armbianEnv.txt` / `compatible` |
| mainline DTS 未写 HDMI IN | **错**。7.3 和 6.1 dts 都已写，且 `okay` | `dts-7.3-linux/rk3588-really.dts:687` |

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
