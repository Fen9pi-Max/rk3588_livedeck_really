# Really TVI2340R TF boot status and handover

| Item | Value |
|---|---|
| Author | Codex |
| Generated | 2026-11-15 |
| Board | Really TVI2340R / RK3588 live-streaming box |
| Branch / scope | `rk3588_livedeck_really`, mainline U-Boot 2026.07 archive |
| Build project | `/home/user/github/build` |
| Kernel side | `dts-7.3-linux/rk3588-really.dts` |
| Vendor reference | `dts-5.10-android/rk3588-really.dts` |
| Environment | Native arm64 Armbian build, `really-rk3588_defconfig` |

## Target boot policy

The intended local boot order is:

```text
TF microSD -> USB -> eMMC
```

`same-as-spl` must remain first in `u-boot,spl-boot-order`. U-Boot proper then
uses its ordinary boot-target mechanism; the temporary shell `preboot` loader
used during bring-up is not a production solution and must not be committed.

## Verified facts

1. The Linux kernel sees the 59.4 GiB TF card as `/dev/mmcblk1p1`.
2. The TF root filesystem is valid ext4 and has UUID
   `21e2f14a-ad69-4db5-872c-965c678ff425`.
3. TF `/boot/armbianEnv.txt` points `rootdev` at that same UUID and selects
   `rockchip/rk3588-really.dtb`.
4. The compiled U-Boot FIT DTB contains the intended aliases:

   ```text
   mmc0 = /mmc@fe2e0000   # eMMC / sdhci
   mmc1 = /mmc@fe2c0000   # TF / sdmmc
   ```

   The aliases themselves are therefore not the failure.
5. U-Boot must look devices up by alias sequence with
   `uclass_get_device_by_seq(UCLASS_MMC, 1, ...)`. Calling
   `uclass_get_device(UCLASS_MMC, 1, ...)` uses enumeration index and was
   confirmed to return the second enumerated device (eMMC, block devnum 0),
   not the `mmc1` alias. This earlier diagnostic result must not be reused.
6. With the alias-aware lookup, U-Boot finds the real TF block device at
   devnum 1. On the last full diagnostic before the final vendor-aligned DTS
   build, `mmc_init()` returned `-EIO`, with card version, card capabilities,
   and RCA all still zero.
7. The board-specific SD rails are testable through U-Boot:

   ```text
   vccio_sd_s0 = 3.3 V, enabled
   vcc_sd      = 3.3 V, enabled
   ```

   Missing voltage or an unbound `vcc_sd` regulator is therefore no longer a
   supported explanation.
8. Writing the combined `u-boot-rockchip.bin` at byte offset `0x8000`
   (sector 64) to both eMMC and TF is mechanically valid. Readback with
   `cmp` succeeds on both devices.

## Deterministic vendor-aligned DTS changes

These changes are now archived in this directory:

- `vcc_sd` is the vendor GPIO4_C3 controlled fixed regulator and is powered
  from `vcc_3v3_s3`.
- RK806 `dcdc-reg8` defines `vcc_3v3_s3`.
- RK806 `pldo-reg5` defines `vccio_sd_s0` with a 3.3 V initial value.
- `&sdmmc` follows the vendor 5.10 properties: 4-bit bus, MMC/SD high-speed
  capability, SDR104 declaration, `supports-sd`, `no-mmc`, `no-sdio`,
  `disable-wp`, and both VMMC/VQMMC supplies.
- No `cd-gpios` is added because the vendor board DTS does not define one.
  The SoC default `sdmmc_det` pinctrl remains in effect through the base DTSI.
- SPL boot order is archived in `rk3588-really-u-boot.dtsi` as
  `"same-as-spl", &sdmmc, &sdhci`.

## Current blocker

The remaining problem is below DTS power configuration: U-Boot's SD host
initialization has not yet been proven to receive a card response. The final
vendor-aligned DTS build compiles, but a TF-rooted cold/warm boot has not yet
been recorded as successful.

Final bring-up result on 2026-11-15:

```text
mmc_init       = -EIO
SCMI clock     = 400000 Hz, set OK
vmmc/vqmmc     = bound, 3.3 V, enabled
U-Boot PMU     = 0x11 (PD_SDMMC power bit absent)
direct PMU RMW = ignored from the normal world
SCMI pd get/on = -ENODEV / -ENODEV
```

The SCMI firmware exposes clock and reset protocols but not a usable power
domain protocol through the current U-Boot firmware node. Further work requires
changing the ATF/SCMI firmware side or adding an RK3588 secure-call power-domain
backend; it cannot be completed by boot-order or Linux DTS changes alone.

Do not mark TF boot complete based only on:

- Linux seeing the card;
- U-Boot finding `mmc1`;
- `vcc_sd` and `vccio_sd_s0` reading enabled;
- U-Boot being written to both media.

The acceptance condition is a reboot where all of the following are true:

```text
U-Boot can read mmc 1:1 /boot/boot.scr
Linux mounts /
findmnt -n -o SOURCE,FSTYPE /
```

and the result is TF ext4 UUID `21e2f14a-ad69-4db5-872c-965c678ff425`, not
eMMC UUID `05d8ce93-2619-4837-8fc5-f2ed1f01a4df`.

## Next checks if card still reports no response

1. Confirm SCMI clock lookup/set-rate result for `sdmmc` clock index 1.
2. Compare the U-Boot SD controller register state with the vendor 5.10
   initial state during CMD0/CMD8.
3. Verify the SDMMC power domain state before the first command.
4. Only after the card responds, remove all diagnostic bootargs and test the
   unmodified `boot_targets` path.

## Artifacts and recovery

- eMMC first 16 MiB backup:
  `/home/user/skysi-x5/backups/really-emmc-head-16m-20261115-1355.bin`
- Backup SHA-256:
  `82966b34fab2a9778cd995ab06b77ff49c61f43a4a1af067a44019137ee8750a`
- U-Boot artifact directory:
  `/home/user/skysi-x5/artifacts/really-tf-boot-1115/`

Do not use destructive Git operations when updating this repository.
