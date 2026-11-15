# Really TVI2340R — mainline U-Boot device-tree archive

| Item | Value |
|---|---|
| Author | Codex |
| Generated | 2026-11-15 |
| Board | Really TVI2340R / RK3588 live-streaming box |
| Scope | Mainline U-Boot 2026.07 board DTS, U-Boot DTSI, and defconfig |
| Source tree | `u-boot/u-boot` commit `ece349ade2973e220f524ce59e59711cc919263f` |
| Build project | `/home/user/github/build` |
| Armbian family | `rockchip-rk3588` / `rockchip64` |
| Environment | Armbian build framework, native arm64, `really-rk3588_defconfig` |

## Why this directory exists

Linux and mainline U-Boot use separate device trees and separate DTB
artifacts. The kernel DTS in `dts-7.3-linux/` is not consumed by U-Boot.

At build time, Armbian maps these archived files to:

```text
u-boot-mainline/dts/upstream/src/arm64/rockchip/rk3588-really.dts
  -> <u-boot>/dts/upstream/src/arm64/rockchip/rk3588-really.dts

u-boot-mainline/arch/arm/dts/rk3588-really-u-boot.dtsi
  -> <u-boot>/arch/arm/dts/rk3588-really-u-boot.dtsi

u-boot-mainline/configs/really-rk3588_defconfig
  -> <u-boot>/configs/really-rk3588_defconfig
```

The corresponding build-repository copies are under:

```text
patch/u-boot/v2026.07/dt_upstream_rockchip/rk3588-really.dts
patch/u-boot/v2026.07/dt_uboot/rk3588-really-u-boot.dtsi
patch/u-boot/v2026.07/defconfig/really-rk3588_defconfig
```

## Build usage

```bash
cd /home/user/github/build
./compile.sh really uboot
```

The resulting DTB is named `u-boot.dtb`; the final bootloader artifact is
`u-boot-rockchip.bin`.

## Current hardware assumptions

```text
mmc0 = &sdhci  (eMMC)
mmc1 = &sdmmc  (microSD/TF)
UART2 = M0 on the on-board UART header
SD power enable = GPIO4_C3, active high
```

The mainline U-Boot DTS now carries the minimum SD power chain aligned with
Skysi-X5 and the kernel DTS:

```text
RK806 PMIC on SPI2
pldo-reg5 = vccio_sd_s0, 3.3 V, boot-on/always-on
SD pinctrl = bus4/clk/cmd/det
SD card detect = GPIO0_A4, active low
SD vmmc = GPIO4_C3 controlled vcc_sd
```

This is separate from the Linux DTS. Changes to either side must be checked
against its own binding and runtime behavior.
