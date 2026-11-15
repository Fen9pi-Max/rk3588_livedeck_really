# Really TVI2340R Linux 7.3 mainline board enablement log

Author: Codex (GPT-5); executor: user

Generated: 2026-11-14T21:50:00+08:00

Last updated: 2026-11-15T21:45:00+08:00

Context: Board-level hardware enablement and validation on the Really
TVI2340R, starting from the reconstructed vendor DTB and the mainline
RK3588 device-tree bindings.

Applicable branch: `/home/user/github/build`, `main`, Armbian edge,
Linux 7.3.y rockchip64.

Environment: Really TVI2340R, RK3588, eMMC boot, 15.6-inch portrait
dual-link LVDS panel behind a Lontium LT9211, HDMI output, Type-C DP
Alt Mode, AP6275P Wi-Fi/Bluetooth and ES8388 audio.

The board also defines eDP0 as an optional factory-supported internal
panel route. The default image keeps the fitted DSI1/LT9211/LVDS path;
the same DTS also describes VP2/eDP0 with normal HPD/AUX detection.

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
- The factory play/pause key is on SARADC channel 3, threshold 200 mV,
  key-up threshold 1.8 V and key code `KEY_PLAYPAUSE`.

Validated result: ES8388 playback and capture enumerate, the speaker path
produces audio, and the amplifier is switched off after playback stops.
The play/pause ADC input registers as a second `adc-keys` input device.

### USB and Type-C

- DWC3 is configured for dual-role operation in the shared rockchip64
  edge kernel configuration.
- Type-C PD/mux is provided by HUSB311/RT1711H.
- Type-C VBUS enable is GPIO1_D1, active high.
- USB-A host power is controlled from GPIO3_A5.
- DP uses two Type-C lanes while USB3 uses the other two lanes.

Validated result: Type-C USB2 hub and USB-A keyboard enumerate. Type-C DP
reached 3840x2160@30 in an earlier test configuration, but this is not a
closed result for the current baseline. Current runs repeatedly leave
`DP-1` disconnected and cycle the HUSB311 partner through
`SRC_READY -> disconnected -> TOGGLING`.

### PCIe, Wi-Fi and Bluetooth

- M.2/5G 3.3 V switch: GPIO3_B3, active high.
- M.2/5G reset: GPIO2_C5, active high.
- M.2/5G DPR control: GPIO3_D5, active high. It is represented as an
  independently controllable regulator and remains disabled unless a
  consumer requests it.
- AP6275P remains on its independent PCIe 2.0 x1 link.
- The AP6275P 32.768 kHz LFO is described as an always-on fixed clock so
  Wi-Fi/Bluetooth probe does not depend on HYM8563 I2C probe succeeding.

The fixed-clock change is present in DTS but still needs validation with a
correctly packaged full image. A hand-built kernel must retain the
`7.3.4-edge-rockchip64` module release suffix.

### Accelerometer

- The STK8BAXX accelerometer is on I2C6 address `0x18`.
- IRQ is GPIO4_B7.
- It uses the upstream `sensortek,stk8ba50` IIO driver.
- Runtime manual instantiation produced an `stk8ba50` IIO device and live
  X/Y/Z readings.
- The 7.3 DTS now contains `accelerometer@18` and its pinctrl entry.
- Automatic USB-camera rotation is not implemented. The current camera keeps
  a fixed GStreamer `videoflip` direction; any gravity-following behavior must
  be implemented in userspace with hysteresis.

### Display

- VOP2 VP0 -> HDMI1.
- VOP2 VP1 -> DP0 -> USB-C DP Alt Mode.
- VOP2 VP3 -> four-lane DSI1 -> LT9211 -> dual-link 24-bit VESA LVDS.
- LT9211 port 2 carries odd pixels and port 3 carries even pixels. The
  panel sink exposes the matching `dual-lvds-odd-pixels` and
  `dual-lvds-even-pixels` properties.
- The LT9211/DSI controller scans 1920x1080@60 at 148.5 MHz; the physical
  15.6-inch panel is mounted portrait.  The panel node declares
  `rotation = <270>` so DRM reports the correct portrait orientation and
  Mutter presents a 1080x1920 logical desktop.
- The early kernel console does not consume panel orientation, so board
  bootargs add `fbcon=rotate:3` to rotate fbcon as well.
- LVDS panel supply enable is GPIO3_B6, active high and always-on.
- LVDS backlight enable is GPIO3_B4; PWM is PWM12 with normal polarity.
- This panel's brightness decreases as the PWM high-level duty cycle rises.
  The mainline user-facing curve therefore reverses the factory 256-step
  values. Logical brightness 255 produces the minimum PWM level and lower
  logical values produce progressively longer high-level pulses.
- New images default to logical brightness 154, the first stable ~40% PWM
  point validated on the panel. The range remains `0..255`; zero powers the
  backlight off.
- The temporary `lontium,dsi-mode-flags` override patch has been retired.
  The Really dual-link mainline topology uses the upstream driver's
  non-burst defaults directly.
- The vendor value `2051` (`VIDEO | BURST | LPM`) was tested after the
  dual-link conversion and produced vertical-line striping/flicker.
  Removing the override eliminated the artifact on 2026-11-15.
- Vendor mode 3 writes `0x8237 = 0x2a`, `0x823b = 0xb8` and
  `0x855c = 0x07`. The upstream dual-link path now writes the same
  channel-enable mask through
  `0015-lt9211-enable-dual-link-lvds-channels.patch`.

Validated result: HDMI output works. Type-C DP previously reached 4K30, but
the current final baseline does not maintain a Type-C partner/Alt Mode
connection. DP must be documented as open until a repeated cold-boot and
hot-plug regression passes.

### Optional internal eDP panel

- Factory data defines eDP0 on VP2, with PWM6 backlight, backlight enable
  GPIO4_B6 and panel enable GPIO1_D0.
- The production LVDS path remains DSI1 on VP3 through LT9211.
- The same board DTS enables eDP0 and exposes an `edp-panel` on its AUX
  bus. It deliberately uses normal HPD/AUX detection without
  `force-hpd` or `no-hpd`, so an unpopulated eDP assembly is reported as
  disconnected instead of creating a phantom display.
- The panel description assumes EDID. A panel without EDID needs its exact
  model, power sequence and timing.
- No eDP panel has yet been fitted for physical validation.

### Touch and RTC

- GT9110: I2C4 `0x14`, reset GPIO1_D3, IRQ GPIO4_B0. The factory DTB uses
  active-low polarity; the current experimental DTS was changed to
  active-high while comparing probe behavior. Both polarities have been
  tested and neither resolves the current I2C failure.
- HYM8563: I2C4 `0x51`, IRQ GPIO0_B0.
- Userspace late-bind services are installed for both devices because they
  can miss the first built-in probe during cold boot.

Current live result (2026-11-15T21:30+08:00): there is no Goodix input device,
I2C4 `0x14` and `0x51` do not acknowledge, and neither device has a bound
driver. The bus controller itself is alive because LT9211 at `0x2d` remains
bound. Android 12 has a working `goodix-ts` device with raw range
`0..1080 x 0..1920`, proving the panel hardware and wiring are valid.

Already tested without success: I2C4 at 100 kHz and 400 kHz; reset/IRQ
ACTIVE_LOW and ACTIVE_HIGH; pull-up and pull-none; late-bind; and the
factory `mipi_cam_pwen` supply enable. The root cause is still open.

### Ethernet, fans, keys and power

- GMAC0 uses RGMII, PHY address 1, GPIO2_C4 reset and `tx_delay = 0x44`.
- YT8531 PHY LEDs are configured through `ledtrig-netdev`.
- PWM2 drives the fan with a 40000 ns period (25 kHz) and inverted
  polarity.
- SARADC channel 1 provides volume-up, volume-down, menu and back;
  channel 3 provides play/pause.
- The GL3523 USB2 hub can enumerate the Riitek `1997:2535` receiver while
  leaving its HID endpoint silent after reboot. A delayed systemd timer
  re-authorizes only that receiver after boot; `evtest` confirmed that this
  restores real key events without rebooting the board.
- Internal RK3588 watchdog and external GPIO0_D3 watchdog remain disabled.

## Electronically validated facts

Original Android DTB and the extracted vendor 5.10 kernel establish:

- LVDS output is dual-link. A single-link graph displays only half of the
  1920-pixel scan and produces severe aliasing.
- LVDS mapping is `vesa-24`.
- The DSI input is four lanes and RGB888.
- The vendor LT9211 `output-mode = <3>` selects the dual LVDS path.
- The vendor DSI flags are `2051` (video, burst and LPM), but they do not
  map cleanly to the mainline dual-link driver path. Really intentionally
  uses the upstream non-burst defaults.
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
4. GT9110 and HYM8563 remain unresolved on mainline. The current system does
   not create a Goodix input device, I2C4 `0x14` and `0x51` do not ACK, and
   late-bind still fails. Android 12 provides a working touch baseline, so
   continue with the mainline I2C4 power/enable/controller comparison.
5. HDMI output can remain logically connected after cable removal, causing
   EDID I2C retries and a compositor stall. The image currently starts HDMI
   disabled by default.
6. Type-C DP is open, not merely limited to 4K30. Current `DP-1` is
   disconnected and the HUSB311 Type-C partner repeatedly detaches. Previous
   two-lane 4K30 success must not be used as a final validation claim.
7. TF boot is still unresolved at U-Boot runtime despite correct aliases and
   SD regulators. See `../u-boot-mainline/TF-BOOT-STATUS.md`; do not trust the
   old claim that TF boot already works.

## Relevant build-tree files

```text
patch/kernel/archive/rockchip64-7.3/dt/rk3588-really.dts
config/kernel/linux-rockchip64-edge.config
userpatches/customize-image.sh
```
