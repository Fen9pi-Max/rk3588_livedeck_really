# 5.10 / 6.1 / 7.3 设备树电源配置修补

- 执行时间：2026-11-17 01:20 — 01:45
- 基准：原厂 Android 12 5.10 DTB（`dtb-5.10-android/rk3588-really.dtb`）
- 参照：7.3 mainline 实机调试结果
- 构建树：`/home/user/github/build`

## 一、为什么漏掉了这么多电源配置

还原方法本身有四个盲区，不是个别疏漏。

### 盲区 1：只还原"带 GPIO 的" regulator

原厂 23 个板级 `regulator-fixed` 里有 8 个**没有 `gpio` 属性**：
`pcie20_avdd0v85`、`pcie20_avdd1v8`、`pcie30_avdd0v75`、
`pcie30_avdd1v8`、`vcc12_dvp`、`vcc3v3_ext`、`vcc4v0_sys`、
`vcc1v8_pmu_ddr_s3`。它们看起来是可省的中间节点，实际是供电链枢纽——
删掉后下游 `vin-supply` 引用就断了。

### 盲区 2：整条丢掉了 GPIO0_C0

原厂 `vcc1c8_en`（`gpio0_PC0`，always-on + boot-on），在 **5.10、
6.1android、6.1linux 三个版本里完全不存在**，只有 7.3 调试时补上
（改名 `vcc1v8_sys`）。

这一条同时打掉两个器件，因为**原厂触控和 RTC 都没有 `*-supply` 属性**：

| 器件 | 原厂写法 | 实际依赖 |
|---|---|---|
| `gt9xx@14` | 无 supply | 靠 `vcc1c8_en` 常开拉起 |
| `hym8563@51` | 无 supply | 靠 `vcc1c8_en` 常开拉起 |

这解释了为什么触屏和 RTC 一起坏，而 LT9211（接常开 `vcc_1v8_s3`）一直正常。

### 盲区 3：把共享使能当成专属使能

`GPIO1_D0` 实际是**触控模块 + 面板的共享电源使能**。5.10 / 6.1a /  6.1l
都只把它挂在 eDP 面板的 `enable-gpios` 上。一旦判定"本机没有 eDP 面板"
而 disable eDP，触控跟着断电。

7.3 的修法是抽出独立常开 regulator：

```dts
touch_panel_pwr: regulator-touch-panel-pwr {
    gpio = <&gpio1 RK_PD0 GPIO_ACTIVE_HIGH>;
    regulator-always-on;
    regulator-boot-on;
};
```

### 盲区 4：供电轨接错

6.1 两个版本的触控写 `power-supply = <&vcc_3v3_s3>`，但 GT9110 实际需要：

```dts
AVDD28-supply = <&vcc28_dvp>;   /* 2.8V */
VDDIO-supply  = <&vcc1v8_sys>;  /* 1.8V */
```

`vcc_3v3_s3` 是 PMIC 常开轨，看起来"更安全"，却不是这颗芯片的供电来源。
这类错误比缺失更隐蔽：DTS 能编译、驱动也能 probe，只是电压不对。

## 二、修复内容

### 2.1 5.10 android（`dts-5.10-android/rk3588-really.dts`）

新增 7 个 regulator（20 → 27）：

| regulator | GPIO | 作用 |
|---|---|---|
| `vcc1v8_sys` | gpio0_PC0 | 触控 VDDIO + RTC 主供电 |
| `touch_panel_pwr` | gpio1_PD0 | 触控/面板共享使能，从 eDP 解耦 |
| `pcie20_avdd0v85` | — | 虚拟轨 |
| `pcie20_avdd1v8` | — | 虚拟轨 |
| `pcie30_avdd0v75` | — | 虚拟轨 |
| `pcie30_avdd1v8` | — | 虚拟轨 |
| `vcc1v8_pmu_ddr_s3` | — | 虚拟轨 |

新增 pinctrl 组：`vcc1v8_sys_en`（gpio0_C0）、`touch_panel_en`（gpio1_PD0）。

触控补 `AVDD28-supply` / `VDDIO-supply`。

**触控坐标保持原样**：`max-x = <1920>; max-y = <1080>;` 与原厂
（`0x780` / `0x438`）完全一致，**不加** `touchscreen-swapped-x-y`。
7.3 之所以需要旋转属性，是因为它当时把坐标系写成了 1080x1920，
再靠属性转回来——5.10 这边本来就对。

### 2.2 6.1 android（`dts-6.1-android/rk3588-really-android.dts`）

按 Android 栈单独处理，保留 `rk3588-android.dtsi`。新增 14 个 regulator
（15 → 29），含 `mipi_cam_pwen`、`vcc28_dvp`、`vcc_5g_dpr_ctl`、
`power_on_led` 等此前全缺的项。触控供电从 `vcc_3v3_s3` 改为
`AVDD28` + `VDDIO`。

### 2.3 6.1 linux（`dts-6.1-linux/rk3588-really.dts`）

同 2.2，保留 `rk3588-linux.dtsi`。两版除 include 外内容一致，改动也一致。

### 2.4 7.3 linux（`patch/kernel/archive/rockchip64-7.3/dt/rk3588-really.dts`）

补 9 个此前残留的虚拟轨和 `power_on_led`（43 → 52）。
7.3 已有 `vcc1v8_sys` / `vcc28_dvp` / `touch_panel_pwr`，无需重复。

## 三、验证

### 3.1 编译验证

7.3 用真实内核树编译：

```bash
make ARCH=arm64 rockchip/rk3588-really.dtb
  DTC     arch/arm64/boot/dts/rockchip/rk3588-really.dtb
```

**零 warning、零 error**。产物 212190 字节，DTB 内 regulator 52 个。

5.10 / 6.1 无法在本地编译（缺对应版本的 dtsi），改用结构校验：
大括号净差 0、无重复 label、未定义 label 数量与改动前一致
（29/25，全部来自 dtsi）。

### 3.2 覆盖度对比

| 版本 | 板级 regulator | 相对原厂缺口 |
|---|---|---|
| 原厂 | 23 | — |
| 5.10 | 27 | 0（`vcc1c8_en` 由 `vcc1v8_sys` 等价替代） |
| 6.1 android | 29 | 0（同上） |
| 6.1 linux | 29 | 0（同上） |
| 7.3 | 52 | 0（同上） |

剩余"缺失"项均为 PMIC 内部轨（`vcc_1v8_s0`、`vcc_3v3_s3`、
`vccio_sd_s0`、`vdd_gpu_s0` 等），由 `rk806` 驱动按 PMIC 型号动态注册，
不需在板级 DTS 中声明。

### 3.3 GPIO 一致性

已存在的所有 regulator，GPIO 引脚与原厂**逐项一致**（11/11 全对）。
修复前就已正确，问题纯粹是遗漏而非接错。

## 四、未验证项

- **5.10 / 6.1 未实机验证**。本地无法编译这两版 DTS，只做了结构校验。
  上机后需确认 `i2cdetect -y 4` 能看到 `0x14`(GT9110) 和 `0x51`(HYM8563)，
  且触控可用、RTC 走时正常。
- **5.10 触控坐标需实测**。虽然与原厂一致，但 5.10 的 gt9xx 驱动行为
  与 mainline 不同，方向需上机确认。
- **7.3 已编译通过但未上机**。新增的虚拟轨不驱动引脚，风险低，
  但仍应在下次启动时确认 `regulator_summary` 无异常。
