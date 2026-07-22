# 弹弓物理演示视频

一个由 GDScript 驱动的程序化物理视频系统。它可以展开多个平行实验，分别记录确定性物理结果，再用统一的导演、回放和视觉模板生成对比视频。

制作和渲染不需要打开 Godot 编辑器。

## 项目结构

```text
src/
├── app.gd          # 传统单次实验入口
├── episode_app.gd  # 多变体 Episode 入口
├── core/           # 配置、物理、记录与结果分析
├── simulation/     # 真实物理模拟
├── playback/       # 记录采样与插值
├── video/          # 导演、画面、HUD 与回放生命周期
└── scene/          # 可复用场景节点

content/
├── episodes/       # 单集配置
├── narration/      # 可版本化的中文解说稿
└── themes/         # 系列视觉主题
```

Episode 系统的完整边界和数据流见 [Episode 视频系统](docs/episode-system.md)。

## 环境

- Godot 4.7.1 标准版（无需 Mono/.NET）
- Xvfb
- FFmpeg 与 ffprobe
- Linux 下可用的 OpenGL 3 兼容驱动

检查环境：

```bash
godot --version
ffmpeg -version | head -1
command -v xvfb-run ffprobe
```

## 一条命令生成 Episode

```bash
scripts/render_episode.sh content/episodes/smoke.json renders/episode-smoke.mp4
```

输出：

- MP4：1920×1080、30/60 FPS、H.264 视频，可带 AAC 解说；
- JSON：比较指标、事件和各 Variant 的实验结果；
- manifest：配置、物理记录和视频的 SHA-256 及渲染环境。

脚本先顺序模拟所有 Variant，再启动独立回放进程录制视频。导演节奏不会改变已经产生的物理结果。

当前正片：

```bash
scripts/generate_narration.sh \
  content/episodes/s01e01-angle-sweep.json \
  content/episodes/s01e02-stretch-sweep.json
scripts/render_episode.sh content/episodes/s01e01-angle-sweep.json
scripts/render_episode.sh content/episodes/s01e02-stretch-sweep.json
```

`generate_narration.sh` 使用 mmx-cli 的 `speech-2.8-hd` 同时生成 MP3 和精确 SRT。Godot 根据 SRT 绘制字幕，FFmpeg 将同一音轨混入成片；讲稿、模型、音色、时长和 SHA-256 都可追溯。

只调整配音时可以跳过 Godot 逐帧渲染，直接以 `-16 LUFS` 目标响度重新混入：

```bash
scripts/remux_narration.sh content/episodes/s01e01-angle-sweep.json
```

- S01E01：相同弹簧能量下比较 15°、30°、45°、60°、75° 的首次落地距离；
- S01E02：保持 45°，比较 0.3 m、0.6 m、0.9 m、1.2 m 拉伸距离。

批量渲染默认使用 2 路并行。Ryzen 5 4600U 实测日常使用 2 路、设备空闲时 3 路较合适；其他设备可通过 `--jobs N` 调整：

```bash
scripts/render_batch.sh --jobs 2
scripts/render_batch.sh --jobs 3 content/episodes/s01e01-angle-sweep.json content/episodes/s01e02-stretch-sweep.json
```

生成 Question、Explain、Setup、Launch、Mid-flight、Landing、Compare 七节拍审查表：

```bash
scripts/review_episode.sh renders/episodes/s01e01-angle-sweep.mp4
```

## 传统单次实验

```bash
scripts/render.sh presets/default.json renders/slingshot-physics.mp4
```

输出：

- `renders/slingshot-physics.mp4`：1920×1080、60 FPS、H.264 视频。
- `renders/slingshot-physics.json`：本次实验的参数、帧数和碰撞 telemetry。

渲染使用 Godot Movie Maker 逐帧生成无损 PNG，再由 FFmpeg 编码 MP4。渲染速度可以低于实时速度，但固定时间步保证最终视频不掉帧。

## 测试

运行 1 秒端到端渲染：

```bash
bash scripts/smoke_test.sh
bash scripts/episode_smoke_test.sh
```

运行全部 GDScript 单元测试：

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

验证 Xvfb 下的项目启动与 preset 解析：

```bash
bash tests/test_boot.sh
```

Xvfb 环境中出现“无法创建输入法上下文”或“不支持切换 V-Sync”的警告不影响离线渲染。渲染脚本仍会把 `SCRIPT ERROR` 和引擎错误视为失败。

## 修改实验参数

复制 `presets/default.json` 后可以修改：

- `bird_mass_kg`、`target_mass_kg`：质量，单位 kg。
- `spring_k_npm`：弹簧刚度，单位 N/m。
- `stretch_m`：拉伸距离，单位 m。
- `efficiency`：弹性势能转为发射动能的效率，范围 `(0, 1]`。
- `launch_angle_deg`：发射角，范围 `(0, 90)`。
- `launch_position_m`、`target_position_m`：以画面左上角为原点的米制坐标。
- `bird_color`、`target_color`、`accent_color`：HTML 十六进制颜色。
- `seed`：镜头震动等程序效果的确定性种子。

Episode 固定输出 1920×1080，支持 30 或 60 FPS。当前 1 分钟以上的正片使用 30 FPS，在软件 OpenGL 设备上可以把逐帧渲染量减半；冲突的分辨率或 FPS 会在渲染前被拒绝，以免构图被裁切。

## 物理口径

发射速度来自弹性势能：

```text
Eₛ = 1/2 kx²
1/2 mv² = efficiency × Eₛ
```

碰撞数据使用动量变化计算冲量：

```text
J = Δp = m(v_after - v_before)
```

画面中的“平均力估计”为：

```text
F_avg ≈ |J| / Δt
```

其中 `Δt` 是明确记录在 sidecar 中的物理采样间隔。该数值不是材料接触过程中的精确瞬时峰值力。

## CLI 参数

Godot 也可以直接启动：

```bash
xvfb-run -a -s '-screen 0 1920x1080x24' \
  godot --path . \
  --rendering-method gl_compatibility \
  --write-movie /tmp/slingshot/frame.png \
  --fixed-fps 60 --disable-vsync \
  -- --preset presets/default.json --sidecar /tmp/slingshot/result.json
```

推荐始终使用 `scripts/render.sh`，因为它还负责临时目录、超时、FFmpeg、ffprobe、原子发布和失败日志保留。

## 许可证

本项目采用 [MIT License](LICENSE)。
