# Really TVI2340R — U-Boot TF 卡启动电源审查

- 执行时间：2026-11-16 14:30 — 15:00
- 构建：192.168.3.28 `/home/user/github/build`（Armbian，`compile.sh uboot`）
- 验证：192.168.3.233（really，Linux 7.3.4-edge-rockchip64）
- U-Boot 版本：`2026.07-Sece3-P56fc-Hae08-V6f98-Bd800-R448a`
- 关联：`TF-BOOT-STATUS.md`、`../REALLY-Uboot阶段电源轨调查-20261116.md`

---

## 一、结论摘要

TF 卡启动确属电源问题，但**不是 GPIO 使能缺失**。根因是 U-Boot 设备树在
`2b7fb0e26`（添加模块电源轨那次提交）中**误删了整段 `&spi2` + RK806 PMIC**，
连带丢失 SD 供电链的三个环节。

| 项 | 修复前 | 修复后 |
|---|---|---|
| `vccio_sd_s0`（vqmmc）provider | ❌ 不存在 | ✅ `pldo-reg5` |
| `vcc_3v3_s3`（vcc_sd 的 vin）provider | ❌ 不存在 | ✅ `dcdc-reg8` |
| `vqmmc-supply` 属性 | ❌ 无 | ✅ 指向 `pldo-reg5`（phandle `0x88`） |
| SD 能力声明 | 仅 `cap-sd-highspeed` | 恢复 `cap-mmc-highspeed` / `sd-uhs-sdr104` / `supports-sd` |
| `CONFIG_POWER_DOMAIN` | ❌ 未设置 | ✅ `=y` |

已实机验证新 U-Boot 可正常启动，触控 / RTC / eMMC 均无回归。

**尚未验证 TF 实际启动**：当前 192.168.3.233 未插 TF 卡，Linux 下
`mmc1` 也识别不到卡（`400k → 300k → 200k` 逐级降速无响应），无法做启动验证。

---

## 二、根因：`2b7fb0e26` 的连带删除

该提交的意图是给 U-Boot DTS 补 4 个模块 regulator（`vcc5v0_sys`、
`vcc28_dvp`、`vcc1v8_sys`、`lvds_pwr_en`），但 diff 里同时包含了大段删除：

```diff
-&spi2 {
-	status = "okay";
-	...
-	pmic@0 {
-		compatible = "rockchip,rk806";
-		...
-		regulators {
-			vcc_3v3_s3: dcdc-reg8 { ... };
-			vccio_sd_s0: pldo-reg5 { ... };
-		};
-	};
-};
```

以及：

```diff
-		vin-supply = <&vcc_3v3_s3>;      /* vcc_sd 的父电源，改成 regulator-always-on */
-	vqmmc-supply = <&vccio_sd_s0>;   /* sdmmc 的 IO 域电源 */
-	sd-uhs-sdr104;
-	supports-sd;
-	cap-mmc-highspeed;
```

结果：`vcc_sd` 的 `vin-supply` 悬空、`sdmmc` 失去 `vqmmc`，两个 regulator
全部失去 DT provider（U-Boot 里 `pmic@0` 出现次数为 **0**）。

原厂 5.10 DTS（`dts-5.10-android/rk3588-really.dts:1575-1576`）与内核 7.3 DTS
（`dts-7.3-linux/rk3588-really.dts:1291-1292`）**都同时声明 vmmc 和 vqmmc**，
U-Boot 侧丢失属于回归，不是设计取舍。

---

## 三、三处电源缺口的可信度排序

### 3.1 `vqmmc` 丢失（最可能的直接原因）

SD 卡初始化在 CMD8 / ACMD41 阶段需要按卡的能力切换信号电平（3.3 V ↔ 1.8 V）。
`vqmmc` 缺失会让 IO 域停在未定义状态，表现正是历史记录的现象：

```text
mmc_init = -EIO
card version / capabilities / RCA 全为 0
```

即"控制器在跑但卡完全没响应"。

### 3.2 `PD_SDMMC` 电源域从未被打开（已确证，但当前无解）

`rk3588-base.dtsi:2211` 中 `sdmmc` 声明了：

```dts
power-domains = <&power RK3588_PD_SDMMC>;
```

但 U-Boot 侧三个事实叠加：

1. defconfig **没有** `CONFIG_POWER_DOMAIN`（现已补上，但仅 uclass 存在）；
2. U-Boot 源码树里**不存在** `rockchip,rk3588-power-controller` 驱动
   （`grep -rln 'rk3588-power-controller' drivers/ arch/` 无结果）；
3. U-Boot DM core **完全不解析** `power-domains` 属性
   （`drivers/core` 与 `include/dm` 均无命中）。

历史补丁 `0004` 试图在 SPL 直接写 `0xfd8d8150 |= 0x2000` 绕过，实测
`PMU = 0x11`，写入被忽略。原因是 **SCMI 固件不提供电源域协议**，已实机核实：

```text
/proc/device-tree/firmware/scmi/ 下只有 protocol@14 (Clock) 和 protocol@16 (Reset)
缺少 protocol@11 (Power Domain)
```

Linux 侧能工作，是因为 `rockchip-pm-domain` 驱动**直接裸访 PMU 寄存器**，
不走 SCMI。

**关键对照**：`sdhci`（eMMC）在 dtsi 里**没有** `power-domains`，属 always-on
域 —— 这正是 eMMC 在 U-Boot 里一直正常、唯独 TF 失败的原因。

### 3.3 `startup-delay-us` 语义可能失效

`vcc_sd` 原厂靠 `vin-supply` 建立父子关系，由 regulator core 串行上电并等待。
改成 `regulator-always-on` 后，`_regulator_enable()` 在 `use_count != 0` 时
直接短路返回，`startup-delay-us = <100000>` 可能不再生效。本次已恢复
`vin-supply`，但保留 `regulator-always-on` 以维持 U-Boot 早期可用性。

---

## 四、代码改动

### 4.1 `patch/u-boot/v2026.07/dt_upstream_rockchip/rk3588-really.dts`

恢复 RK806 PMIC 区块：

```dts
&spi2 {
	status = "okay";
	assigned-clocks = <&cru CLK_SPI2>;
	assigned-clock-rates = <200000000>;
	num-cs = <1>;
	pinctrl-names = "default";
	pinctrl-0 = <&spi2m2_pins>, <&spi2m2_cs0>;

	pmic@0 {
		compatible = "rockchip,rk806";
		reg = <0x0>;
		spi-max-frequency = <1000000>;
		interrupt-parent = <&gpio0>;
		interrupts = <7 8>;
		pinctrl-names = "default";
		pinctrl-0 = <&pmic_pins>, <&rk806_dvs1_null>,
			    <&rk806_dvs2_null>, <&rk806_dvs3_null>;
		system-power-controller;
		gpio-controller;
		#gpio-cells = <2>;

		rk806_dvs1_null: dvs1-null-pins { pins = "gpio_pwrctrl1"; function = "pin_fun0"; };
		rk806_dvs2_null: dvs2-null-pins { pins = "gpio_pwrctrl2"; function = "pin_fun0"; };
		rk806_dvs3_null: dvs3-null-pins { pins = "gpio_pwrctrl3"; function = "pin_fun0"; };

		regulators {
			vcc_3v3_s3: dcdc-reg8 {
				regulator-always-on;
				regulator-boot-on;
				regulator-min-microvolt = <3300000>;
				regulator-max-microvolt = <3300000>;
				regulator-ramp-delay = <12500>;
				regulator-name = "vcc_3v3_s3";
			};

			vccio_sd_s0: pldo-reg5 {
				regulator-always-on;
				regulator-boot-on;
				regulator-init-microvolt = <3300000>;
				regulator-min-microvolt = <1800000>;
				regulator-max-microvolt = <3300000>;
				regulator-ramp-delay = <12500>;
				regulator-name = "vccio_sd_s0";
			};
		};
	};
};
```

`vcc_sd` 恢复父电源：

```dts
	vcc_sd: regulator-vcc-sd {
		...
		startup-delay-us = <100000>;
		vin-supply = <&vcc_3v3_s3>;
		regulator-always-on;
	};
```

`&sdmmc` 恢复能力与 IO 电源：

```dts
&sdmmc {
	bus-width = <4>;
	cap-mmc-highspeed;
	cap-sd-highspeed;
	disable-wp;
	no-mmc;
	no-sdio;
	sd-uhs-sdr104;
	supports-sd;
	status = "okay";
	vmmc-supply = <&vcc_sd>;
	vqmmc-supply = <&vccio_sd_s0>;
};
```

### 4.2 `patch/u-boot/v2026.07/defconfig/really-rk3588_defconfig`

```diff
+CONFIG_POWER_DOMAIN=y
 CONFIG_DM_PMIC=y
```

---

## 五、验证

### 5.1 DTB 内容校验（构建产物）

```
$ dtc -I dtb -O dts u-boot.dtb | grep -A3 vqmmc-supply
		vqmmc-supply = <0x88>;

$ dtc -I dtb -O dts u-boot.dtb | grep vccio_sd_s0
	vccio_sd_s0 = "/spi@feb20000/pmic@0/regulators/pldo-reg5";
								regulator-name = "vccio_sd_s0";
								phandle = <0x88>;
```

`0x88` 正确解析到 `pldo-reg5`，不再是悬空引用。

### 5.2 实机部署

```bash
dpkg -i linux-u-boot-really-edge_26.11.0-trunk_arm64__...-P56fc-....deb
write_uboot_platform /usr/lib/linux-u-boot-edge-really /dev/mmcblk0
```

写入回读校验：

```text
00b5df19e2eea6b5d538273226fce944  (eMMC LBA64 起 512KiB)
00b5df19e2eea6b5d538273226fce944  (u-boot-rockchip.bin 前 512KiB)
```

一致。

### 5.3 启动后确认

```text
chosen/u-boot,version = 2026.07_armbian-2026.07-Sece3-P56fc-Hae08-V6f98-Bd800-R448a
根文件系统 = /dev/mmcblk0p1 ext4
```

功能无回归：

```text
i2c-4: 0x14 UU (GT9110), 0x2d UU (LT9211), 0x51 UU (HYM8563)
Goodix-TS 4-0014: ID 9110, version: 1050
rtc-hym8563 4-0051: registered as rtc0
mmc0 (eMMC) HS400 Enhanced strobe, 115 GiB
```

### 5.4 TF 卡未能验证

当前机器未插 TF 卡，Linux 下 `dwmmc_rockchip fe2c0000` 初始化时出现
逐级降速后无响应，符合"无卡"特征：

```text
[5.363951] mmc_host mmc1: Bus speed = 400000Hz (req 400000Hz, actual 400000HZ div = 0)
[5.515009] mmc_host mmc1: Bus speed = 300000Hz (req 300000Hz, actual 300000HZ div = 0)
[5.674946] mmc_host mmc1: Bus speed = 200000Hz (req 200000Hz, actual 200000HZ div = 0)
```

**因此本次修改对 TF 启动是否生效，尚未取得证据。**

---

## 六、下一步验证步骤（需要插卡）

1. 在 192.168.3.233 插入已写入 Armbian 的 TF 卡。
2. 在 Linux 下先确认卡能被识别：

   ```bash
   lsblk | grep mmcblk1
   ```

   若此处仍无 `mmcblk1`，则问题在硬件/卡本身，与 U-Boot 无关，先解决。

3. 确认后可进 U-Boot 命令行直接测：

   ```text
   => mmc dev 1
   => mmc info
   => ls mmc 1:1 /boot
   ```

   `mmc dev 1` 成功且 `mmc info` 能报出容量，即说明 SD 供电链修复生效。

4. 再把 `u-boot-rockchip.bin` 写到 TF 卡的 LBA64：

   ```bash
   dd if=u-boot-rockchip.bin of=/dev/mmcblk1 bs=32k seek=1 conv=notrunc
   ```

5. 冷启动后按 `TF-BOOT-STATUS.md` 的验收标准判断：

   ```text
   Linux mounts /
   findmnt -n -o SOURCE,FSTYPE /
   ```

   结果必须是 TF 的 ext4 UUID `21e2f14a-ad69-4db5-872c-965c678ff425`，
   而不是 eMMC 的 `05d8ce93-2619-4837-8fc5-f2ed1f01a4df`。

---

## 七、若 vqmmc 修复仍不足

按可信度，下一个候选是 `PD_SDMMC`。注意事项：

- 纯 DT 手段**不可行**：U-Boot 无 rockchip 电源域驱动，DM core 也不解析
  `power-domains`。
- SPL 直写 PMU **已验证无效**（`0004`，SCMI 无 power domain 协议）。
- 剩余可能路径只有：给 U-Boot 补一个 `rockchip,rk3588-power-controller` 驱动，
  或让 ATF 暴露 SCMI power domain 协议。两者都超出 DT 范畴。

**风险提示**：任何在 SPL 早期强改 PMU 时序的尝试都可能挂死 SPL，导致只能
MaskROM 救砖。建议在 vqmmc 方案实测失败后再考虑，且必须保留 eMMC 首 16 MiB
备份（`/home/user/skysi-x5/backups/really-emmc-head-16m-20261115-1355.bin`）。

---

## 八、过程中的操作教训

1. **heredoc 写 DT 节点会被 shell 吞引号**。本次插入 PMIC 区块时，`status =
   "okay"`、`compatible = "rockchip,rk806"`、`pins = "gpio_pwrctrl1"` 等 12 处
   引号全部丢失，导致 dtc 报 `Lexical error`。写 DTS 片段必须用 `Write` 工具
   落文件再 `scp`，或至少用 Python 显式构造引号字符。

2. **改完 DT 先本地 dtc 预检，再跑完整构建**。Armbian 的 `compile.sh` 单次
   循环约 1 分钟且失败后日志会被清理，本地 `cpp + dtc` 秒级定位行号。

3. **diff 要看全**。`2b7fb0e26` 的提交信息只说"添加 4 个 regulator"，实际
   diff 里删了 75 行，正是这些删除造成了 SD 供电链断裂。
