# Really TVI2340R Mainline Open Issues

- Author: OpenAI Codex (GPT-5); executor: user
- Generated: 2026-11-15T21:45:00+08:00
- Context: final-state evidence capture after repeated mainline USB-C DP
  and Goodix touch experiments.
- Applicable branch: `/home/user/github/build`, `main`; Linux
  `7.3.4-edge-rockchip64`
- Environment: Really TVI2340R, RK3588, eMMC boot, running at
  `192.168.3.233`
- Runtime kernel: `7.3.4-edge-rockchip64 #61`
- Runtime DTB:
  `/boot/dtb-7.3.4-edge-rockchip64/rockchip/rk3588-really.dtb`
- Runtime DTB SHA256:
  `98cb2541226cdc34ff269040f4b99cc30c21e159b15545d6709ef5688f4f9b84`

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

## Mainline touch and RTC snapshot

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

Touch/RTC:

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
4. Avoid further random polarity/frequency loops without new trace or
   power-rail evidence.
