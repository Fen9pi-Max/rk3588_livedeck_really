# Really TVI2340R workaround audit and cleanup

| Item | Value |
|---|---|
| Author | OpenAI Codex; executor: user |
| Generated | 2026-11-16T23:55:00+08:00 |
| Context | Audit and remove user-space workarounds after TF boot and native I2C4 probing became reliable |
| Applicable branch | Armbian `edge`, Linux `7.3.4-edge-rockchip64` |
| Build tree | `/home/user/github/build` |
| Device | Really TVI2340R, RK3588, booting from TF `/dev/mmcblk1p1` |

## Removed from the image build

- `really-touch-late-bind`
- `really-rtc-late-bind`
- `really-wifi-late-load`
- `really-usb-hid-recovery.timer` and its forced USB re-authorization script
- `really-phy-leds.service` and its polling helper script

The first three services were disabled together and the board was cold
booted. The following devices still bound during their initial kernel probe:

```text
Goodix-TS 4-0014: ID 9110, version: 1050
rtc-hym8563 4-0051: registered as rtc0
4-002d -> lt9211
4-0014 -> Goodix-TS
4-0051 -> rtc-hym8563
brcmfmac 0004:41:00.0 -> wlP4p65s0, connected to HUAWEI-7409_5G
```

No userspace rebind, PCIe rescan, or delayed module load is required.

## U-Boot power sequencing

The previous generic Rockchip `board.c` patch forced four rails from
`board_init()`:

```text
vcc5v0_sys
vcc28_dvp
vcc1v8_sys
lvds_pwr_en
```

That was broader than the hardware needs:

- `vcc5v0_sys` is the always-on 5 V upstream;
- `vcc28_dvp` is fixed and has no controllable enable in the U-Boot DTS;
- `lvds_pwr_en` belongs to the Linux display power sequence;
- only `vcc1v8_sys` has an enable GPIO that must be raised early.

The patch was deleted. The final implementation changes only the board DTS:

```dts
&gpio0 {
	vcc1v8-sys-en-hog {
		gpio-hog;
		gpios = <16 0>;
		output-high;
		line-name = "vcc1v8_sys_en";
	};
};
```

The board defconfig enables the generic `CONFIG_GPIO_HOG` mechanism. The
final U-Boot DTB contains this hog and the Linux GPIO state still reports:

```text
gpio-16 (regulator-vcc1v8-sys) out hi
```

## USB input idle policy

The old timer re-authorized `1997:2535` 30 seconds after every boot. It
created a second complete HID input set and did not protect against later
idle disconnects.

The replacement is a narrow udev rule that keeps the receiver and its
specific Genesys Logic `05e3:0610` USB2 hub out of runtime suspend:

```text
1-1    control=on autosuspend_delay_ms=-1000
1-1.2  control=on autosuspend_delay_ms=-1000
```

After cold boot there is exactly one mini-keyboard input set:

```text
input6 keyboard
input7 mouse
input8 system control
input9 consumer control
```

Final acceptance still needs a long idle soak where a key event is accepted
without physically reconnecting the receiver.

## PHY LEDs

The board DTS already defines both YT8531 PHY LED children and selects the
`netdev` trigger. Linux currently reports:

```text
green:  device_name=end0 offloaded=1 link_1000=1 full_duplex=1
yellow: device_name=end0 offloaded=1 rx=1 tx=1
```

The standard PHY LED binding has no property for arbitrary netdev trigger
rules. DTS therefore owns trigger selection and netdev association; a
one-shot udev rule sets the hardware green-link and yellow-activity rules.
Writing the trigger itself from udev was rejected because it can make the
udev change event self-sustaining.

## TF boot

TF boot is closed. The P743c U-Boot payload was written at `0x8000`,
read back and compared byte-for-byte, then cold booted successfully:

```text
/dev/mmcblk1p1 ext4
UUID 7faf7863-d5d5-419e-81bd-902914de6883
```

The previous first 16 MiB of the TF card is saved on the device at
`/root/really-tf-uboot-backup-20261116.bin`.
