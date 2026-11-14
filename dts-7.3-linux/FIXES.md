# Really TVI2340R Linux 7.3 mainline board enablement log

Author: Codex (GPT-5); executor: user

Generated: 2026-11-14T21:50:00+08:00

Last updated: 2026-11-14T23:05:00+08:00

Context: Board-level hardware enablement and validation on the Really
TVI2340R, starting from the reconstructed vendor DTB and the mainline
RK3588 device-tree bindings.

Applicable branch: `/home/user/github/build`, `main`, Armbian edge,
Linux 7.3.y rockchip64.

Environment: Really TVI2340R, RK3588, eMMC boot, 15.6-inch portrait
dual-link LVDS panel behind a Lontium LT9211, HDMI output, Type-C DP
Alt Mode, AP6275P Wi-Fi/Bluetooth and ES8388 audio.

## Integrated board changes

### Serial console

- UART2 stays on M0 at `0xfeb50000`, `1500000 8N1`.
- UART0 is not used for the Linux console because its M2 pins conflict
  with the RK806 PMIC connection on SPI2-CS0.

### Audio

- ES8388 uses I2S1 M0 to avoid the UART2 M0 pin conflict.
- MCLK is GPIO4_A0 at 12.288 MHz.
- The card exposes speaker, headphone and microphone DAPM paths.
- Speaker amplifier enable is GPIO4_B2, active low.
- Headphone amplifier enable is GPIO4_B4, active high.
- Headphone detect is GPIO4_B3, active high.

Validated result: ES8388 playback and capture enumerate, the speaker path
produces audio, and the amplifier is switched off after playback stops.

### USB and Type-C

- DWC3 is configured for dual-role operation in the shared rockchip64
  edge kernel configuration.
- Type-C PD/mux is provided by HUSB311/RT1711H.
- Type-C VBUS enable is GPIO1_D1, active high.
- USB-A host power is controlled from GPIO3_A5.
- DP uses two Type-C lanes while USB3 uses the other two lanes.

Validated result: Type-C USB2 hub and USB-A keyboard enumerate. Type-C DP
output works at 3840x2160@30.

### PCIe, Wi-Fi and Bluetooth

- M.2/5G 3.3 V switch: GPIO3_B3, active high.
- M.2/5G reset: GPIO2_C5, active high.
- AP6275P remains on its independent PCIe 2.0 x1 link.
- The AP6275P 32.768 kHz LFO is described as an always-on fixed clock so
  Wi-Fi/Bluetooth probe does not depend on HYM8563 I2C probe succeeding.

The fixed-clock change is present in DTS but still needs validation with a
correctly packaged full image. A hand-built kernel must retain the
`7.3.4-edge-rockchip64` module release suffix.

### Display

- VOP2 VP0 -> HDMI1.
- VOP2 VP1 -> DP0 -> USB-C DP Alt Mode.
- VOP2 VP3 -> four-lane DSI1 -> LT9211 -> dual-link 24-bit VESA LVDS.
- LT9211 port 2 carries odd pixels and port 3 carries even pixels. The
  panel sink exposes the matching `dual-lvds-odd-pixels` and
  `dual-lvds-even-pixels` properties.
- The LT9211/DSI controller scans 1920x1080@60 at 148.5 MHz; the physical
  15.6-inch panel is mounted portrait and the compositor rotates the output
  left to a 1080x1920 logical desktop.
- LVDS panel supply enable is GPIO3_B6, active high and always-on.
- LVDS backlight enable is GPIO3_B4; PWM is PWM12.
- LT9211 optional DSI mode flags are board-configurable.
- Really uses `lontium,dsi-mode-flags = <2051>`:
  `MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_BURST | MIPI_DSI_MODE_LPM`.
- Vendor mode 3 writes `0x8237 = 0x2a`, `0x823b = 0xb8` and
  `0x855c = 0x07`. The upstream dual-link path now writes the same
  channel-enable mask through
  `0015-lt9211-enable-dual-link-lvds-channels.patch`.

Validated result: HDMI and Type-C DP output work. Type-C DP 4K30 is stable;
4K60 is not reliable with the two-lane USB3-sharing configuration.

### Touch and RTC

- GT9110: I2C4 `0x14`, reset GPIO1_D3 active high, IRQ GPIO4_B0.
- HYM8563: I2C4 `0x51`, IRQ GPIO0_B0.
- Userspace late-bind services are installed for both devices because they
  can miss the first built-in probe during cold boot.

Current cold boot still occasionally leaves both devices without an I2C ACK;
the late-bind service then fails. This remains open.

### Ethernet, fans, keys and power

- GMAC0 uses RGMII, PHY address 1, GPIO2_C4 reset and `tx_delay = 0x44`.
- YT8531 PHY LEDs are configured through `ledtrig-netdev`.
- PWM2 drives the fan with a 40000 ns period (25 kHz) and inverted
  polarity.
- SARADC keys provide volume-up, volume-down, menu and back.
- Internal RK3588 watchdog and external GPIO0_D3 watchdog remain disabled.

## Electronically validated facts

Original Android DTB and the extracted vendor 5.10 kernel establish:

- LVDS output is dual-link. A single-link graph displays only half of the
  1920-pixel scan and produces severe aliasing.
- LVDS mapping is `vesa-24`.
- The DSI input is four lanes and RGB888.
- The vendor LT9211 `output-mode = <3>` selects the dual LVDS path.
- The vendor DSI flags are `2051` (video, burst and LPM).
- The panel power enable is GPIO3_B6 active high.

The physical board voltage selectors are separate:

- `LVDS 3V3 / 5V / 12V`: panel-side voltage selection, currently 12 V.
- `LVDS_BLTTL`: backlight control-level selection, currently 5 V.

These jumpers are static and do not explain the Android boot-time speaker
click. The click is more likely ES8388/amplifier power-on or mute timing.

## Open issues

1. Dual-link output has been validated on hardware: the full 1920x1080
   scan is now visible instead of only one half. Residual pixel-column
   jitter is being closed using the vendor `0x855c = 0x07` sequence.
2. The vendor 5.10 kernel has been reversed and confirms the dual-link
   PLL/channel values. A live Android dump is no longer required to
   establish single-vs-dual mode.
3. Panel-side 12 V, backlight power and LVDS common-mode/swing have not been
   measured with a meter or oscilloscope.
4. HYM8563/GT9110 cold-boot I2C availability is intermittent.
5. HDMI output can remain logically connected after cable removal, causing
   EDID I2C retries and a compositor stall. The image currently starts HDMI
   disabled by default.
6. Type-C DP and USB3 cannot both have four lanes. Keep DP capped at 4K30 for
   the two-lane configuration.

## Relevant build-tree files

```text
patch/kernel/archive/rockchip64-7.3/dt/rk3588-really.dts
userpatches/kernel/archive/rockchip64-7.3/0014-lt9211-allow-board-specific-dsi-mode-flags.patch
config/kernel/linux-rockchip64-edge.config
userpatches/customize-image.sh
```
