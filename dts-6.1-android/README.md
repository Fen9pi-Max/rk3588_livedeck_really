# Really TVI2340R — 6.1 Android 设备树

本目录存放 **Android 侧**（vendor 6.1 / Android 16 EVB7）使用的设备树源。

## 文件

| 文件 | 说明 |
|---|---|
| `rk3588-really-android.dts` | Really 的 6.1 Android 设备树 |

## 与 dts-6.1-linux 的关系

两者同源，**唯一区别是末尾的 dtsi 包含**：

```diff
# dts-6.1-linux/rk3588-really.dts
- #include "rk3588-linux.dtsi"

# dts-6.1-android/rk3588-really-android.dts
+ #include "rk3588-android.dtsi"
```

两个 dtsi 的差异：

| 项目 | rk3588-linux.dtsi | rk3588-android.dtsi |
|---|---|---|
| bootargs | 含 `root=PARTUUID=... rw rootwait` | 无 root 参数（由 Android init 接管） |
| mmc aliases | 有（mmc0/1/2） | 无 |
| vendor-storage | 无 | **有**（`rockchip,vendor-storage-rm`） |
| 显示 | `disable-win-move` | `support-multi-area` |

**判断依据**：Android 16 已刷入设备的 resource DTB（191066 字节）
反编译后含 `vendor-storage-rm` 节点，证明 Android 侧确实必须用
`rk3588-android.dtsi`。

## 重要差异：LVDS 链路

| 项目 | 当前本目录版本 | 已刷入设备的 Android16 版 |
|---|---|---|
| panel-lvds dual-link | ✅ `dual-lvds-odd/even-pixels` | ❌ 单链路（port@0 + port@2） |
| LT9211 port@3 | ✅ 有 | ❌ 无 |
| DTB 大小 | 295964 | 191066 |

**已刷入的那版是单链路**，对应 mainline 侧曾出现的"只显示半幅桌面"
问题（见 `dts-7.3-linux/FIXES.md`）。本目录版本已按双链路生成。

## 编译

依赖 rockchip vendor 6.1 内核树（需含 `rk3588-android.dtsi`）：

```bash
K=<rockchip-vendor-6.1-tree>
cp rk3588-really-android.dts $K/arch/arm64/boot/dts/rockchip/
cd $K
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip/rk3588-really-android.dtb
```

已验证可编译的环境：

```text
/home/user/github/build/cache/sources/linux-kernel-worktree/6.1__rk35xx__arm64
（Armbian rockchip64 6.1.172 树，含 rk3588-android.dtsi）
```

注意：该树版本为 6.1.172，而设备 Android 内核是 6.1.145。
DTB 结构兼容，但若有 vendor 专有属性需求，应以
`/home/user/github/linux-rockchip-6.1.145` 为准（该树目前缺 rk3588 dts）。

## 产物校验

```text
rk3588-really-android.dtb
  size  295964
  sha256 f2801118cc36dc919cd33ec1beeca2275e8fea25cb29d861b92bd75bb86633dd
```
