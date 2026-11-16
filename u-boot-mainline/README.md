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

The U-Boot DTS carries the minimum SD power chain taken from the vendor 5.10
DTS, not from a generic RK3588 board:

```text
RK806 PMIC on SPI2
pldo-reg5 = vccio_sd_s0, 3.3 V, boot-on/always-on
RK806 dcdc-reg8 = vcc_3v3_s3, parent of vcc_sd
SD vmmc = GPIO4_C3 controlled vcc_sd
SD vqmmc = pldo-reg5 vccio_sd_s0
SD bus = the SoC's default clk/cmd/det/bus4 pinctrl
SD card detect = no board-level cd-gpios override
```

**This chain was briefly lost and has been restored.** Commit `2b7fb0e26`
added the four switched module rails (for GT9110 and HYM8563) but deleted the
whole `&spi2` + RK806 block along with `vqmmc-supply` and the `vin-supply` link
on `vcc_sd` in the same diff. The archived file in this directory kept the PMIC,
which is why the archive and the build tree disagreed for a while. The build
tree is now correct again and both copies match. Whenever you touch this DTS,
diff the whole file rather than reading the commit subject.

### Power domains

`sdmmc` declares `power-domains = <&power RK3588_PD_SDMMC>` in the upstream
DTSI, but U-Boot cannot act on it: there is no `rockchip,rk3588-power-controller`
driver in the U-Boot tree, the DM core does not parse `power-domains`, and the
SCMI firmware exposes no power-domain protocol. `sdhci` (eMMC) has no
`power-domains` property and lives in an always-on domain, which is why eMMC has
always worked here and TF has not. See
[TF-BOOT-STATUS.md](TF-BOOT-STATUS.md) for what this means for bring-up.

`u-boot,spl-boot-order` mirrors the proven Skysi-X5 structure:
`same-as-spl`, then `&sdmmc`, then `&sdhci`. U-Boot proper uses the normal
`boot_targets` mechanism after SPL. No board-specific `preboot` loader is part
of the final configuration.

See [TF-BOOT-STATUS.md](TF-BOOT-STATUS.md) for the verified facts, current
blocker, and the checks that must pass before calling TF boot complete.

The Armbian build-time board patches are archived under
[`board_really/`](board_really/README.md). They include boot logging,
boot-target selection, reboot-mode handling, module-rail enablement in
`board_init()`, and one explicitly ineffective SDMMC power-domain experiment
(`0004`, kept for the record: the SPL write to the PMU is ignored because the
normal world has no power-domain access). The build-tree copies remain the source of
truth.

This is separate from the Linux DTS. Changes to either side must be checked
against its own binding and runtime behavior.
