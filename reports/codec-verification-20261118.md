# 硬解栈验证结果（2026-11-18）

## 硬件设备全部在线 ✅
| 设备 | 驱动 | 功能 | 状态 |
|---|---|---|---|
| /dev/video0 | rockchip-rga (RGA3) | 2D 加速(缩放/旋转/合成) | ✅ 注册 |
| /dev/video4 | rkvdec | H.264/HEVC/VP9 解码 | ✅ 注册, NV12 输出 |
| /dev/video5 | hantro (rk3328-vpu) | H.264/VP8/MPEG2 解码 | ✅ 注册 |
| /dev/video6 | vepu121-enc | JPEG 编码 (8192x8192) | ✅ 注册 |
| /dev/video7 | av1-vpu-dec | AV1 解码 | ✅ 注册 |

## 用户态验证
- JPEG 编码: ffmpeg 软编工作正常 (16KB 测试帧)
- H.264 硬解: **rkvdec 使用 V4L2 stateless API (request)**,
  stock ffmpeg 不支持 → 需要 Collabora ffmpeg 补丁
- GStreamer: plugins-bad 已装但 v4l2codecp(stateless) 不在发行版构建中

## 结论
**硬件全部就绪, 差用户态工具**。rkvdec 等使用 V4L2 request API,
需以下方案之一:
1. 打补丁的 ffmpeg (Collabora/ChromeOS v4l2-request patch)
2. GStreamer + v4l2codecp 插件 (需自行编译)
3. Rockchip MPP + librockchip-mpp (vendor 方案)

DeepSeek 原镜像已解决此问题(自定义 ffmpeg/mpv ~1.5GB 编译产物),
见 REPRO-BUILD-20261117.md §4 未复现项。
