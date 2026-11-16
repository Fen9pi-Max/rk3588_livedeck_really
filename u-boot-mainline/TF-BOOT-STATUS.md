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
7. The board-specific SD rails were measured as enabled in one earlier
   bring-up:

   ```text
   vccio_sd_s0 = 3.3 V, enabled
   vcc_sd      = 3.3 V, enabled
   ```

   **Caution:** that measurement predates commit `2b7fb0e26`, which removed the
   RK806 PMIC block from the U-Boot DTS. It must not be treated as describing
   the current tree. Re-measure before relying on it.
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

**Rewritten 2026-11-16.** Part of the 2026-11-15 reasoning above was wrong and
is corrected here.

The `vmmc/vqmmc = bound` line recorded on 2026-11-15 was measured against a
build that no longer matches the tree. Commit `2b7fb0e26` ("describe the
switched module rails in U-Boot DTS") added the four module regulators but also
deleted the entire `&spi2` + RK806 PMIC block, `vqmmc-supply`, the `vin-supply`
link on `vcc_sd`, and the SD capability properties. After that commit the U-Boot
device tree contained **no** `pmic@0` node at all, so `vcc_3v3_s3` and
`vccio_sd_s0` had no provider and `vqmmc` was dangling.

That regression has now been fixed (see
[`../reports/uboot-tf-boot-power-20261116/README.md`](../reports/uboot-tf-boot-power-20261116/README.md)).
The rebuilt `u-boot.dtb` resolves `vqmmc-supply` to `pldo-reg5` (phandle
`0x88`) instead of leaving it dangling.

### What is still true

The `PD_SDMMC` power domain is genuinely never enabled by U-Boot, and it cannot
be fixed from the device tree:

- The U-Boot defconfig did not set `CONFIG_POWER_DOMAIN` (now set, but only the
  uclass exists).
- There is **no** `rockchip,rk3588-power-controller` driver anywhere in the
  U-Boot tree.
- The U-Boot DM core does not parse the `power-domains` property at all.
- SCMI firmware exposes only `protocol@14` (Clock) and `protocol@16` (Reset).
  There is no `protocol@11` (Power Domain), so the normal world cannot ask the
  firmware to power the domain on.

The `0004` experiment (SPL writes `0x2000` into `0xfd8d8150`) was measured as
having no effect: `PMU = 0x11` afterwards.

The useful control case: `sdhci` (eMMC) declares **no** `power-domains` and sits
in an always-on domain, which is exactly why eMMC has always worked in U-Boot
while TF never has.

### Status of the verification

**Corrected 2026-11-16 16:10.** The earlier note said "a TF card was not
inserted during verification". That was true of the device under test
(192.168.3.233) but was read as "no acceptance card exists", which was wrong.

A usable acceptance card has been prepared on the build host 192.168.3.28:

```text
device       /dev/mmcblk1        62 GB
partition    /dev/mmcblk1p1      ext4, LABEL=armbi_root
UUID         21e2f14a-ad69-4db5-872c-965c678ff425   <- the TF acceptance UUID
```

The card previously carried `U-Boot SPL 2026.07_armbian-2026.07-Sece3-Pc12d`
(Nov 15 16:39), which predates the vqmmc/PMIC restore. It has been rewritten
with the current build:

```text
U-Boot       2026.07-Sece3-P56fc-Hae08-V6f98-Bd800-R448a  (Nov 16 14:49)
write        dd if=u-boot-rockchip.bin of=/dev/mmcblk1 bs=32k seek=1 conv=notrunc
readback     cmp of LBA64..+512 KiB against u-boot-rockchip.bin: identical
partition    UUID unchanged after the write
backup       /home/user/skysi-x5/backups/really-tf-head-16m-20261116-1608.bin
             sha256 2c17f609892da3895f95a5476f254c00cac63884ade3bd61ee3f068d9c4b22e8
```

So the blocker is no longer "there is no card to test with". It is only that
192.168.3.233 is currently powered down (it was hung by an ES8388
unbind/rebind at 15:33 and needs a physical power cycle).

The card must be moved to 192.168.3.233 and that board cold-booted with it
inserted. A single command then produces the verdict:

```bash
bash really-tf-verify.sh          # lives in
                                  # /home/user/skysi-x5/artifacts/really-tf-verify-1116/
```

It compares `findmnt -n -o SOURCE,FSTYPE,UUID /` on the device against the two
recorded UUIDs and prints PASS/FAIL, then dumps `lsblk`, the `mmc1`/`dwmmc`
dmesg lines, the mmc1 sysfs uevent and `chosen/u-boot,version`.

Do not read the fix as validated until the acceptance condition below is met.

Do not mark TF boot complete based only on:

- Linux seeing the card;
- U-Boot finding `mmc1`;
- `vcc_sd` and `vccio_sd_s0` reading enabled;
- U-Boot being written to both media;
- the card being prepared and verified on the build host.

The acceptance condition is a reboot where all of the following are true:

```text
U-Boot can read mmc 1:1 /boot/boot.scr
Linux mounts /
findmnt -n -o SOURCE,FSTYPE /
```
The acceptance condition is a reboot where all of the following are true:

```text
U-Boot can read mmc 1:1 /boot/boot.scr
Linux mounts /
findmnt -n -o SOURCE,FSTYPE /
```

and the result is TF ext4 UUID `21e2f14a-ad69-4db5-872c-965c678ff425`, not
eMMC UUID `05d8ce93-2619-4837-8fc5-f2ed1f01a4df`.

## Next checks if card still reports no response

Do these in order. Step 0 must pass first, otherwise nothing below is
meaningful.

0. Insert a known-good TF card and confirm Linux itself enumerates it:

   ```bash
   lsblk | grep mmcblk1
   ```

   A card that Linux cannot see (`dwmmc_rockchip fe2c0000` stepping down
   400k -> 300k -> 200k with no response) says nothing about U-Boot.

1. In the U-Boot shell, confirm the SD supply chain fix took effect:

   ```text
   => mmc dev 1
   => mmc info
   ```

   `mmc info` reporting capacity means vqmmc/vmmc are correct.

2. Read the RK806 `pldo-reg5` and `dcdc-reg8` output state.

3. Confirm SCMI clock lookup/set-rate result for `sdmmc` clock index 1.

4. Compare the U-Boot SD controller register state with the vendor 5.10
   initial state during CMD0/CMD8.

5. Only after the card responds, remove all diagnostic bootargs and test the
   unmodified `boot_targets` path.

## Artifacts and recovery

- eMMC first 16 MiB backup:
  `/home/user/skysi-x5/backups/really-emmc-head-16m-20261115-1355.bin`
- Backup SHA-256:
  `82966b34fab2a9778cd995ab06b77ff49c61f43a4a1af067a44019137ee8750a`
- U-Boot artifact directory:
  `/home/user/skysi-x5/artifacts/really-tf-boot-1115/`

Do not use destructive Git operations when updating this repository.
