# Really Android 12 Touch Baseline

- Author: OpenAI Codex (GPT-5); executor: user
- Generated: 2026-11-15T18:30:00+08:00
- Device: Really TVI2340R / `22011211C`
- Android: 12 / SDK 32
- ADB: wireless debugging, paired and captured through `adb`
- Context: Android touch is fully functional; capture a baseline for the
  unresolved mainline Goodix GT9110 failure.

## Result

Android creates a working touchscreen:

```text
Name:    goodix-ts
Path:    /dev/input/event6
I2C:     /sys/bus/i2c/devices/4-0014
OF path: /i2c@feac0000/gt9xx@14
Driver:  Goodix-TS
```

The input device is reported as:

```text
PROP=2
EV=b
KEY=400 0 0 0 0 0
ABS=265000000000000

ABS_MT_POSITION_X: 0..1080
ABS_MT_POSITION_Y: 0..1920
```

This matches the physical portrait panel. The mainline DTS currently uses
`touchscreen-size-x = <1920>` and `touchscreen-size-y = <1080>`, which is
reversed and must be corrected independently of the I2C probe failure.

## Four-corner capture

The user touched top-left, top-right, bottom-right, bottom-left and center.
Two passes were captured:

```text
X=59   Y=79
X=1057 Y=93
X=1068 Y=1882
X=46   Y=1894
X=605  Y=905

X=52   Y=78
X=1023 Y=63
X=1049 Y=1871
X=57   Y=1855
X=567  Y=924
```

Raw files:

```text
getevent-corners.txt
touch-down-points.txt
```

The coordinate system is direct portrait orientation; no runtime display
rotation is needed for the touch controller itself.

## Android device-tree properties

`/i2c@feac0000/gt9xx@14`:

```text
compatible  = "goodix,gt9xx"
reg         = <0x14>
max-x       = <1920>
max-y       = <1080>
tp-size     = <9110>
status      = "okay"
```

GPIO properties:

```text
reset-gpio:
  phandle = 0xfc
  number  = 0x1b (27 -> GPIO1_D3)
  flags   = 0x1  (ACTIVE_LOW)

touch-gpio:
  phandle = 0x143
  number  = 0x08 (8 -> GPIO4_B0)
  flags   = 0x1  (ACTIVE_LOW)
```

Pinctrl:

```text
/pinctrl/tp/gt9xx-gpios
rockchip,pins =
  <1 27 0 0x18f>
  <4 8  0 0x18f>
```

The runtime `i2c@feac0000` node exposes `status=okay` and
`pinctrl-names=default`, but **no `clock-frequency` property** was present in
the captured runtime tree. In the running vendor 5.10 kernel,
`i2c_parse_timing()` therefore falls back to
`I2C_MAX_STANDARD_MODE_FREQ`, which is **100000 Hz**. The reconstructed vendor
source contains `clock-frequency = <400000>`, but that does not match the
runtime DTB. Android's confirmed-working touch baseline is therefore 100 kHz.

## Android boot behavior

```text
[6.472183] goodix_ts_probe() start
[6.472255] Goodix-TS 4-0014: supply tp not found, using dummy regulator
[6.644670] input: goodix-ts as /devices/platform/feac0000.i2c/i2c-4/4-0014/input/input6
```

Android does not use named `AVDD28`/`VDDIO` regulators for this node. Mainline
does. The earlier mainline test without supplies still failed, so this is not
sufficient by itself, but it remains a vendor/mainline difference.

## Mainline comparison candidates

The following differences should be tested one at a time:

1. **Axis size is wrong in mainline:** use X=1080, Y=1920.
2. Mainline currently sets I2C4 to 400 kHz, while Android runs the same bus at
   the 100 kHz default. A temporary 100 kHz mainline DTB is now the next
   evidence-based configuration test.
3. Vendor driver binding is `goodix,gt9xx`; mainline is `goodix,gt9110`.
4. Vendor uses `reset-gpio` / `touch-gpio`; mainline uses
   `reset-gpios` / `irq-gpios` plus an `interrupts` entry.
5. Vendor probe succeeds after a simple GPIO reset. Mainline currently logs
   `-ENXIO` from `0x8140`.
6. Verify mainline actually claims GPIO1_D3 and GPIO4_B0 during probe.

## Files

```text
getprop.txt
input-devices.txt
getevent-capabilities.txt
dumpsys-input.txt
dumpsys-display.txt
window-display.txt
dmesg.txt
logcat.txt
touch-sysfs.txt
touch-i2c.txt
device-tree-gt9xx.properties.txt
device-tree-gt9xx-pinctrl.txt
device-tree-i2c4.properties.txt
getevent-corners.txt
touch-down-points.txt
```
