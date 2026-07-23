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

renders/
├── final/          # 可交付成片、sidecar 与 manifest
├── frames/         # 按 Episode 分目录的单帧审查图
├── contact-sheets/ # 七节拍等联络表
├── previews/       # 非最终视觉实验
├── smoke/          # 冒烟与框架测试产物
└── narration/      # 逐集音频、SRT 与响度报告
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
scripts/render_episode.sh content/episodes/smoke.json renders/smoke/episode-smoke.mp4
```

输出：

- MP4：3840×2160、30/60 FPS、H.264 视频，可带标准化 AAC 解说；
- JSON：比较指标、事件和各 Variant 的实验结果；
- manifest：配置、物理记录和视频的 SHA-256 及渲染环境。

脚本先顺序模拟所有 Variant，再把完整帧区间默认拆成两个独立回放 Worker。两个 Worker 读取同一份 RunRecord，按绝对视频时间绘制各自区间；PNG 合并后只进行一次编码。导演节奏和分片数量都不会改变已经产生的物理结果。

当前正片：

```bash
scripts/generate_narration.sh \
  content/episodes/s01e01-angle-sweep.json \
  content/episodes/s01e02-stretch-sweep.json
scripts/render_episode.sh content/episodes/s01e01-angle-sweep.json
scripts/render_episode.sh content/episodes/s01e02-stretch-sweep.json
```

`generate_narration.sh` 使用 mmx-cli 的 `speech-2.8-hd` 在同一次合成中生成 MP3 和精确 SRT。流水线会忽略排版空白后逐字符验证“讲稿正文 = SRT 正文”，再以两遍响度分析生成 `-16 ±1 LUFS`、不高于 `-1.5 dBTP`、48 kHz 单声道 24-bit PCM 母版。实验量统一使用阿拉伯数字，朗读字幕采用中文单位。Godot 根据同一份 SRT 绘制字幕，FFmpeg 将标准化母版编码为 AAC 并混入成片。编码完成后还会复测交付音轨，要求 `-16 ±1 LUFS`、不高于 `-1.0 dBTP`、48 kHz 单声道；讲稿、模型、音色、响度、时长和 SHA-256 都可追溯。

Episode 在渲染前会执行布局审计：每个阶段拥有独立 Plot Area，逐帧检查小鸟与速度箭头是否进入标题、图例、结果或字幕区域；字幕限制为最多 88 个字符和两条显式行。结果阶段使用左侧轨迹、右侧数据的分栏布局。弹弓拉伸、回弹、能量光点与小鸟的蓄力、飞行形变、眨眼和落地反馈都由视频时间确定性驱动，不改变物理记录。

视觉采用 Editorial Science Lab 规范：中性色负责画面结构，琥珀色只用于系列强调，实验组使用同一条“低值冷色 → 高值暖色”的有序数据色阶。数据色不会再填充面板或正文，胜者通过线宽、星标和光环表达，因此跨集保持相同颜色语义。

只调整配音时可以跳过 Godot 逐帧渲染，直接以 `-16 LUFS` 目标响度重新混入：

```bash
scripts/remux_narration.sh content/episodes/s01e01-angle-sweep.json
```

- S01E01：相同弹簧能量下比较 15°、30°、45°、60°、75° 的首次落地距离；
- S01E02：保持 45°，比较 0.3 m、0.6 m、0.9 m、1.2 m 拉伸距离。

单集 4K 渲染默认使用两个内部分片。批量入口默认串行处理 Episode，并把总 Godot Worker 数限制为 2；显式并行两集时，会自动将每集调整为一个 Worker，避免产生四个 4K 进程：

```bash
scripts/render_batch.sh
scripts/render_batch.sh --jobs 2 content/episodes/s01e01-angle-sweep.json content/episodes/s01e02-stretch-sweep.json
```

可通过 `EPISODE_RENDER_WORKERS` 调整单集期望分片数，通过 `RENDER_MAX_WORKERS` 设置整批任务的并发上限。少于 300 帧的短视频默认不分片；测试时可用 `EPISODE_SHARD_MIN_FRAMES` 调整阈值。

生成 Question、Explain、Setup、Launch、Mid-flight、Landing、Compare 七节拍审查表：

```bash
scripts/review_episode.sh renders/final/s01e01-angle-sweep.mp4
scripts/extract_frame.sh renders/final/s01e01-angle-sweep.mp4 23 long-subtitle
```

联络表默认写入 `renders/contact-sheets/<episode>/`；单帧统一写入
`renders/frames/<episode>/<episode>--<milliseconds>ms--<label>.png`。完整规则见
[`renders/README.md`](renders/README.md)。

## 传统单次实验

```bash
scripts/render.sh presets/default.json
```

输出：

- `renders/previews/default.mp4`：3840×2160、60 FPS、H.264 视频。
- `renders/previews/default.json`：本次实验的参数、帧数和碰撞 telemetry。

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
bash tests/test_render_paths.sh
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

Episode 原生输出 3840×2160，支持 30 或 60 FPS。“逻辑画布 1920×1080”只是一套设计坐标：布局中的 `x = 960` 表示画面水平中心，字号 30、线宽 4 和安全区也都以这套坐标描述。导出时根视口本身就是 3840×2160，Godot 将 Canvas 与 HUD 节点设为 2 倍缩放后直接在 4K 目标上绘制；它不会先生成一段 1080p 视频再交给 FFmpeg 放大。因此文字、曲线和程序化图形仍由引擎以 4K 像素栅格化，只是设计参数更容易阅读和维护。

项目内置 `Sarasa Gothic SC`、`Sarasa Mono SC` 与 `Smiley Sans`。Hero、Accent 两个短文案角色使用得意黑，并回退到更纱黑体；Display、Title、Section、Body、Subtitle、Data、DataMeta、Meta 继续使用更纱字体家族。得意黑只出现在片头问题与结果短强调，字幕、正文、公式、图例和实验数据保持清晰稳定。字体全部随项目嵌入，离线导出不依赖宿主机配置。当前 1 分钟以上的正片使用 30 FPS；冲突的分辨率或 FPS 会在渲染前被拒绝。

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
xvfb-run -a -s '-screen 0 3840x2160x24' \
  godot --path . \
  --rendering-method gl_compatibility \
  --write-movie /tmp/slingshot/frame.png \
  --resolution 3840x2160 \
  --fixed-fps 60 --disable-vsync \
  -- --preset presets/default.json --sidecar /tmp/slingshot/result.json
```

推荐始终使用 `scripts/render.sh`，因为它还负责临时目录、超时、FFmpeg、ffprobe、原子发布和失败日志保留。

## 许可证

本项目采用 [MIT License](LICENSE)。
