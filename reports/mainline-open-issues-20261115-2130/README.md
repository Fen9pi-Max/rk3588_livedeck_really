# Really TVI2340R Mainline Open Issues

- Author: OpenAI Codex (GPT-5); executor: user
- Generated: 2026-11-15T21:45:00+08:00
- Context: final-state evidence capture after repeated mainline USB-C DP
  and Goodix touch experiments.
- Applicable branch: `/home/user/github/build`, `main`; Linux
  `7.3.4-edge-rockchip64`
- Environment: Really TVI2340R, RK3588, eMMC boot, running at
  `192.168.3.233`
- Original Android baseline: Android 11, Linux 5.10.110. Do not mix this
  board with the RK3566 Blackcat 4.19.232 baseline.
- Runtime kernel: `7.3.4-edge-rockchip64 #61`
- Runtime DTB:
  `/boot/dtb-7.3.4-edge-rockchip64/rockchip/rk3588-really.dtb`
- Runtime DTB SHA256:
  `98cb2541226cdc34ff269040f4b99cc30c21e159b15545d6709ef5688f4f9b84`

## 2026-11-16 closure update

- **CLOSED: GT9110 touch.** The missing shared 1.8 V enable path and the
  GT9110 2.8 V analog rail were restored. GT9110 now works at I2C4 `0x14`.
- **CLOSED: HYM8563 RTC.** HYM8563 now works at I2C4 `0x51`, confirming that
  the common board power/enable path was the root cause.
- **OPEN: USB-C DP.** Type-C partner/Alt Mode stability remains the only
  active subsystem-level issue in this report.

This report supersedes older statements that Type-C DP and mainline touch
were "finished". Historical isolated successes are retained below as
evidence, but they are not current acceptance results.

## Live display and Type-C snapshot

```text
/sys/class/drm/card1-LVDS-1/status      connected
/sys/class/drm/card1-DP-1/status        disconnected
/sys/class/drm/card1-HDMI-A-1/status    disconnected

/sys/class/typec/port0/data_role        [host] device
/sys/class/typec/port0/power_role       [source] sink
Type-C partner                          absent
```

The physical cable state cannot be inferred from an absent partner alone.
The reason this remains open is the behavior observed during inserted-cable
tests: after PD negotiation and VDM discovery, HUSB311 repeatedly detached
and restarted toggling.

Representative kernel sequence:

```text
rt1711h 6-004e: tcpm: state change SRC_SEND_CAPABILITIES -> SRC_READY
rt1711h 6-004e: tcpm: AMS POWER_NEGOTIATION finished
rt1711h 6-004e: tcpm: vdm discovery state changed:
                 VDM_DISCOVERY_UNKNOWN -> VDM_DISCOVERY_COMPLETE
rt1711h 6-004e: tcpm: CC1: 0 -> 0, CC2: 2 -> 0
                 [state SRC_READY, polarity 1, disconnected]
rt1711h 6-004e: tcpm: state change SRC_READY -> SNK_UNATTACHED
rt1711h 6-004e: tcpm: Start toggling
```

The sequence then repeats. This is earlier than stable DP video output and
must be fixed before treating lane assignment or EDID as the only problem.

## Current USB-C DP device-tree baseline

```text
sbu1-dc-gpios          GPIO3_A0, active high
sbu2-dc-gpios          GPIO1_B2, active high
rockchip,dp-lane-mux   <2 3>
USB/camera 5 V         GPIO4_A6
HUSB311                hynetek,husb311 at I2C6 0x4e
extcon bridge          linux,typec-extcon-bridge
DP controller          VOP2 VP1 -> DP0
```

Historical evidence:

- An earlier 2026-11-14 configuration produced `DP-1 connected`,
  Pin Assignment C and complete link training.
- That configuration was used successfully with a 3840x2160@30 display.
- 4K60 had right-half-screen corruption or link instability even during
  that successful period.

Current conclusion:

- AUX, PHY and lane-training code are not proven globally broken; they
  have completed successfully before.
- The current failure occurs around Type-C attach/PD-VDM/extcon stability.
- Do not claim DP is fixed based only on matching SBU GPIO or
  `rockchip,dp-lane-mux = <2 3>`.

## Mainline touch and RTC pre-closure snapshot

```text
Goodix input device                    absent
/sys/bus/i2c/devices/4-0014/driver     path absent
/sys/bus/i2c/devices/4-0051/driver     path absent
```

`i2cdetect -y -r 4`:

```text
20: -- -- -- -- -- -- -- -- -- -- -- -- -- UU -- --
```

Only `0x2d` is marked `UU`, meaning the LT9211 bridge driver owns that I2C
client. GT9110 at `0x14` and HYM8563 at `0x51` do not acknowledge.

Current experimental DTB:

```text
I2C4 clock          400 kHz
GT9110 address      0x14
GT9110 reset        GPIO1_D3
GT9110 IRQ          GPIO4_B0
touch size          1080 x 1920
HYM8563 address     0x51
HYM8563 IRQ         GPIO0_B0
```

The `1080 x 1920` coordinate correction is valid but does not address the
I2C probe failure.

## Android control result

Android 12 has a fully working Goodix touchscreen:

```text
Name       goodix-ts
Driver     Goodix-TS
OF path    /i2c@feac0000/gt9xx@14
raw X      0..1080
raw Y      0..1920
```

Raw evidence:

```text
../android-touch-baseline-20261115-1820/
```

This proves the touch module, panel, flex cable and touch power rails can
work. The failure is specific to the mainline initialization path or a
board state not recreated by mainline.

## Mainline experiments already rejected

Touch/RTC pre-fix diagnostics (closed; retained as historical method):

- I2C4 at 100 kHz and 400 kHz.
- GT9110 reset/IRQ ACTIVE_LOW and ACTIVE_HIGH.
- pinctrl pull-up and pull-none.
- userspace late-bind.
- factory `mipi_cam_pwen` GPIO1_A2 always-on supply.
- Touch coordinate correction to portrait `1080 x 1920`.

Type-C DP:

- `GPIO4_A6/A7` as SBU pair without separate USB 5 V ownership.
- Vendor-specified `GPIO3_A0/GPIO1_B2` SBU pair.
- USB camera 5 V on GPIO4_A6 versus disabling it.
- Forced `video=DP-1:3840x2160@30`.
- VOP1 clock-parent/rate experiments.
- HPD/extcon notification without a stable Type-C partner.

Do not describe these as fixes. They either regressed another function or
did not survive repeatable cold-boot/hot-plug testing.

## Recommended next diagnostics

USB-C DP:

1. Keep the DP monitor connected and capture `/sys/class/typec` every
   100 ms while HUSB311 cycles.
2. Record `data_role`, `power_role`, partner VDOs, displayport
   `configuration`, `pin_assignment` and `hpd` from first attach to loss.
3. Correlate `extcon changed ... dp=` with `dp-hpd=` and `DP-1` connector
   status.
4. Compare the working 2026-11-14 DTB and the current DTB property by
   property. Do not replace the current baseline wholesale.

Touch/RTC:

1. Compare Android and mainline GPIO/PMIC state after boot, especially
   supplies and enables shared by GT9110 and HYM8563.
2. Trace `regulator_enable`, `gpiod_direction_output`, reset pulses and
   I2C transfers during first probe.
3. Determine whether Android leaves a PMIC rail, GPIO expander state or
   Type-C mux state active that mainline never recreates.
4. Avoided further random polarity/frequency loops without new trace or
   power-rail evidence.

## 2026-11-16 follow-up

Reference:
[USB-C DisplayPort Alt Mode on Rockchip RK3588 and RK3576](https://www.collabora.com/news-and-blog/news-and-events/usb-c-displayport-alt-mode-on-rockchip-rk3588-and-rk3576-starting-with-the-flipper-one.html)

### Confirmed board facts

- The internal panel is dual-link LVDS behind LT9211. Port 2 carries odd
  pixels and port 3 carries even pixels.
- The established USB-C DP SBU mapping is:
  - SBU1: GPIO3_A0
  - SBU2: GPIO1_B2
- GPIO4_A6 is the USB camera/USB 5 V enable and must not be used as SBU.
- The earlier SBU/GPIO4_A6 conflict is already fixed in the current DTS.
- DP0 remains routed from VOP2 VP1 through USBDP PHY0.

### USB-C DP TODO

- [ ] Verify that the running DTB includes the corrected SBU mapping above.
- [ ] Capture the Type-C state every 100 ms from initial attach through the
      HUSB311 disconnect. Record `data_role`, `power_role`, partner VDOs,
      `configuration`, `pin_assignment`, `hpd`, and `irq_hpd`.
- [ ] Save the relevant TCPM debugfs log exactly once; reading it clears it.
- [ ] Classify the failure boundary:
  - partner disappears before DP Alt Mode/hotplug bridge: investigate
    CC/VBUS/PD power and data-role negotiation;
  - partner remains but `hpd=0`: investigate DP Alt Mode/HPD bridge;
  - `hpd=1` but DP AUX fails: investigate SBU direction, PHY mux and AUX;
  - link training succeeds but modes fail: investigate pixel clock/timing.
- [ ] Audit whether `try-power-role = "sink"` matches the board power design;
      the article's source-device example uses `try-power-role = "source"`.
- [ ] Audit the custom `linux,typec-extcon-bridge` against the standard
      TCPM/typec orientation-switch/mode-switch path. Remove it only as a
      controlled regression test, not as an unverified permanent change.
- [ ] Confirm that the kernel contains the Collabora USBDP PHY/DP bridge/HPD
      series. The article states that important PHY and DRM changes were still
      under review, so a vanilla Linux 7.3 tree may be incomplete.
- [ ] Do not alter the dual-link LVDS topology while debugging USB-C DP.

### Touch and RTC closure

Really uses the following Android 5.10 baseline on I2C4:

```text
controller       feac0000.i2c
pinmux           i2c4m1
address          0x14
compatible       goodix,gt9xx
reset            GPIO1_D3, active low, pull-none
interrupt        GPIO4_B0, active low, pull-none
supplies         not described in the factory touch node
```

The current 7.3 node instead uses:

```text
400 kHz, goodix,gt9110
reset GPIO1_D3 active-high, pull-none
irq   GPIO4_B0 active-high, pull-none
AVDD28 = vcc_3v3_s3
VDDIO  = vcc_1v8_s3
```

- [x] Keep the mainline ACTIVE_HIGH reset/IRQ semantics required by
      `goodix_reset_no_int_sync()` and the GT911 address-selection sequence.
      The polarity difference from the vendor `goodix,gt9xx` driver is not by
      itself a bug.
- [x] Tested and rejected as the primary fix the initialization-state
      combination used by the
      Chmayco-mainline fix: reset pinctrl pull-down and IRQ pinctrl pull-up,
      while retaining Really's own I2C4 and GPIO1_D3/GPIO4_B0 wiring.
      Do not copy Chmayco's I2C5 or GPIO3 pins.
- [x] Tested 100 kHz together with alternate pinctrl state. Earlier isolated tests
      changed frequency or pulls separately and did not cover the full
      combination.
- [x] Checked the fallback-compatible option. The verified fix uses
      `goodix,gt9110`; no `goodix,gt9xx` fallback was required.
- [x] Verified that both `vcc_3v3_s3` and `vcc_1v8_s3` remain enabled at the
      moment the Goodix driver enables them; they are shared rails and should
      be treated as consumers, not board-specific touch regulators.
- [x] Determined why HYM8563 at I2C4 `0x51` also lacked an ACK. LT9211 at
      `0x2d` responds on the same bus, so the controller and SCL/SDA pinmux
      are alive. Focus on a shared external power/enable/reset state rather
      than remapping I2C4.
- [x] Compared cold boot and shared-rail recovery. The verified power fix
      restored both devices without changing I2C4 or Goodix polarity.
- [x] Post-fix regression: GT9110 input and HYM8563 RTC are both working after
      restoring the shared board power/enable path.

### Linux 7.3 Goodix DTS references

The Linux 7.3 Rockchip DTS tree has no nodes using the exact compatible
strings `goodix,gt9110` or `goodix,gt9xx`. Existing boards use
`goodix,gt911`, which is handled by the same mainline Goodix driver family.

Relevant examples:

| Board | Bus | IRQ | Reset | Supplies | Pinctrl |
| --- | --- | --- | --- | --- | --- |
| RK3588 Tiger Haikou video demo | I2C6, 400 kHz | GPIO3_C3, active-high, level-low | PCA9670 GPIO, active-high | AVDD28/VDDIO | IRQ pull-none |
| RK3588S GameForce Ace | I2C3 | GPIO1_A6, active-high, level-low | GPIO1_A7, active-high | not declared | IRQ/reset pull-up |
| RK3566 PineTab2 | I2C1, 400 kHz | GPIO0_B0, active-high, edge-falling | GPIO0_C2, active-high | AVDD28/VDDIO | IRQ pull-up, reset pull-none |
| RK3568 Anbernic RG DS | I2C3/I2C5, 400 kHz | active-high, level-low | active-high | AVDD28/VDDIO | IRQ/reset pull-up |
| PX30 Cobra | I2C2, 100 kHz | GPIO0_A1, active-high, level-low | GPIO0_B5, active-high | AVDD28/VDDIO | IRQ/reset pull-none |

Implications for Really:

- `irq-gpios` and `reset-gpios` ACTIVE_HIGH are the normal mainline GT911
  convention; do not change them merely to match the old vendor properties.
- `AVDD28-supply` and `VDDIO-supply` are normal and should remain if they map
  to the correct board rails.
- Pinctrl bias is board-specific. Pull-none is also used by RK3588 Tiger and
  PX30 Cobra, so the Chmayco pull-down/pull-up values are not a universal fix.
- 400 kHz is valid for RK3588 and RK356x GT911 designs.
- During reset the driver drives IRQ high to select address `0x14`. If that
  strap is not established, GT911 can enumerate at `0x5D`; scan both addresses
  and inspect whether `irq-gpios` was successfully acquired and driven.
- The absence of both GT911 (`0x14`) and HYM8563 (`0x51`) while LT9211
  (`0x2d`) works still points more strongly to a shared power/enable/boot state
  than to a generic Goodix binding deficiency.

### Factory 5.10 power-tree audit

The factory Android DTB and boot log establish:

- The Android Goodix driver reports `supply tp not found, using dummy
  regulator`. The factory touch node therefore does not manage a named touch
  regulator; the board rails must already be powered.
- HYM8563 at I2C4 `0x51` also has no supply property, but probes successfully
  in Android.
- The factory board defines a switched `vcc1v8_sys` rail:

```text
GPIO0_C0, active-high, pinctrl vcc1v8_sys_en, function GPIO,
pull-up, regulator-always-on, regulator-boot-on
```

- The factory board also defines always-on `vcc28_dvp` at 2.8 V and
  `vcc12_dvp` at 1.2 V. The i.MX577 camera explicitly consumes
  `vcc28_dvp`; the touch node has no explicit phandle.
- LT9211 is supplied from the separate `vcc_1v8_s3` rail, explaining why it
  can still ACK on I2C4 while GT911/HYM8563 do not.

The current 7.3 DTS differs in two important ways:

1. `vcc1v8_sys` is represented only as a raw `gpio0` hog. The hog has no
   `pinctrl-0 = <&vcc1v8_sys_en>` and therefore does not reproduce the
   factory pinmux/enable dependency.
2. No `vcc28_dvp` regulator exists in the current tree. GT911 `AVDD28`
   is incorrectly pointed at the generic 3.3 V `vcc_3v3_s3` rail.

High-confidence correction to test:

- Restore `vcc1v8_sys` as a `regulator-fixed` on GPIO0_C0 with the factory
  GPIO function and pull-up pinctrl.
- Remove the competing `vcc1v8_sys_hog`.
- Point GT911 `VDDIO-supply` at `vcc1v8_sys`, not directly at
  `vcc_1v8_s3`.
- Restore an always-on 2.8 V `vcc28_dvp` fixed regulator and point GT911
  `AVDD28-supply` at it.

The factory DTB does not prove whether HYM8563 is physically connected to
`vcc1v8_sys` or another always-on rail, so measure GPIO0_C0 and the
GT911/HYM8563 supply pins at cold boot before declaring the shared-rail
question closed.

Other factory rails absent from the current tree include `vcc12_dvp`,
`vcc3v3_ext`, `vcc1v8_pmu_ddr_s3`, `vcc4v0_sys`, and several PCIe analog
rails. Their absence should not be conflated with the touch failure unless a
consumer or measurement ties them to GT911/HYM8563.
