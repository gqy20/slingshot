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
├── narration/      # 逐集语音、SRT 与响度报告
└── audio/          # 按 Beat 生成的确定性音效与记录
```

Episode 系统的完整边界和数据流见 [Episode 视频系统](docs/episode-system.md)。

## 环境

- Godot 4.7.1 标准版（无需 Mono/.NET）
- Xvfb
- FFmpeg 与 ffprobe
- mmx-cli 1.0.18 或更新版本（1.0.16 的重复发音表序列化与当前 T2A API 不兼容）
- Typst 0.15.1（仅在修改公式后重建 SVG 时需要）
- Linux 下可用的 OpenGL 3 兼容驱动

检查环境：

```bash
godot --version
ffmpeg -version | head -1
command -v xvfb-run ffprobe
typst --version
```

## 一条命令生成 Episode

```bash
scripts/render_episode.sh content/episodes/smoke.json renders/smoke/episode-smoke.mp4
```

首次克隆后安装项目内 Git hooks：

```bash
scripts/install_git_hooks.sh
```

提交信息采用 Conventional Commits，例如 `feat(audio): add timed speech controls`。项目 hook 会拒绝缺少类型、超长主题或不规范 scope 的提交标题。

输出：

- MP4：3840×2160、30/60 FPS、H.264 视频，可带标准化 AAC 解说；
- JSON：比较指标、事件和各 Variant 的实验结果；
- manifest：配置、物理记录和视频的 SHA-256 及渲染环境。

脚本先顺序模拟所有 Variant，再把完整帧区间默认拆成两个独立回放 Worker。两个 Worker 读取同一份 RunRecord，按绝对视频时间绘制各自区间；PNG 合并后只进行一次编码。导演节奏和分片数量都不会改变已经产生的物理结果。

当前正片：

```bash
scripts/build_formula_assets.sh
scripts/generate_narration.sh \
  content/episodes/s01e01-angle-sweep.json \
  content/episodes/s01e02-stretch-sweep.json
scripts/render_episode.sh content/episodes/s01e01-angle-sweep.json
scripts/render_episode.sh content/episodes/s01e02-stretch-sweep.json
```

`generate_narration.sh` 使用 mmx-cli 的 `speech-2.8-hd` 在同一次合成中生成 MP3 和句级 SRT。Episode 固定音色、0.5–2.0 范围内的语速、音量、-12–12 级的音高与难词发音表；讲稿使用 MiniMax `<#x#>` 标记精确控制 0.01–99.99 秒停顿。校验时会从讲稿和字幕中移除非朗读控制标记，再逐字符确认“实际朗读正文 = SRT 正文”。实验量统一使用阿拉伯数字，朗读字幕采用中文单位。

公式在 Episode JSON 中同时保存 Typst 源码与无障碍文本兜底。`build_formula_assets.sh` 使用固定的 Typst 0.15.1 和 New Computer Modern Math 生成双倍逻辑尺寸的透明 SVG；Godot 将 SVG 作为主公式层，只有资产缺失或无法加载时才显示更纱等宽文本。`assets/generated/` 是被 Git 忽略的构建目录，渲染入口会按源码哈希自动生成或复用公式，不把 SVG、哈希、manifest 和 `.import` 文件提交到仓库。

控制标记与模型兼容范围以 [MiniMax 同步语音合成 HTTP 文档](https://platform.minimaxi.com/docs/api-reference/speech-t2a-http) 为准。当前流水线固定句级字幕；`word_streaming` 只适合流式请求，不用于可复现的离线 Episode。

语音经过两遍响度分析，生成 `-16 ±1 LUFS`、不高于 `-1.5 dBTP`、48 kHz 单声道 24-bit PCM 母版。每集包含 12 秒循环的四音符小鸟主题 BGM，以及发射、落地、揭晓等 Beat 音效；混音时以解说作为 sidechain 自动压低音乐与音效，Godot 使用同一份 SRT 绘制字幕。AAC 编码后再复测交付音轨，要求 `-16 ±1 LUFS`、不高于 `-1.0 dBTP`、48 kHz 单声道。讲稿、MMX CLI 版本、模型、音色、控制参数、音乐、音效、响度、时长和 SHA-256 均写入 manifest。

Episode 在渲染前会执行布局审计：每个阶段拥有独立 Plot Area，逐帧检查小鸟与速度箭头是否进入标题、图例、结果或字幕区域；字幕限制为最多 88 个字符和两条显式行。结果阶段使用左侧轨迹、右侧数据的分栏布局。弹弓拉伸、回弹、能量光点与小鸟的蓄力、飞行形变、眨眼和落地反馈都由视频时间确定性驱动，不改变物理记录。

每集以连续的 `beats` 时间线组织约 2 分钟内容。Beat 精确声明镜头、聚焦实验组、Overlay、公式步骤和音效提示；`display_hook` 是短屏幕标题，完整 `question` 与旁白仍保留科学语义。Beat 必须从 0 秒无缝覆盖到 Episode 结束，分片 Worker 从任意绝对帧启动都会得到同一状态。

视觉采用 Editorial Science Lab 规范：中性色负责画面结构，琥珀色只用于系列强调，实验组使用同一条“低值冷色 → 高值暖色”的有序数据色阶。数据色不会再填充面板或正文，胜者通过线宽、星标和光环表达，因此跨集保持相同颜色语义。

只调整配音时可以跳过 Godot 逐帧渲染，直接以 `-16 LUFS` 目标响度重新混入：

```bash
scripts/remux_narration.sh content/episodes/s01e01-angle-sweep.json
```

- S01E01：相同弹簧能量下比较 15°、30°、45°、60°、75° 的首次落地距离；
- S01E02：保持 45°，比较 0.3 m、0.6 m、0.9 m、1.2 m 拉伸距离。

单集默认使用两个内部分片。批量入口把总 Godot Worker 数限制为 4；显式并行两集时，每集使用两个绝对帧区间 Worker，正好覆盖当前 6 核 CPU 的有效并行区间：

```bash
scripts/render_batch.sh
scripts/render_batch.sh --jobs 2 content/episodes/s01e01-angle-sweep.json content/episodes/s01e02-stretch-sweep.json
```

可通过 `EPISODE_RENDER_WORKERS` 调整单集期望分片数，通过 `RENDER_MAX_WORKERS` 设置整批任务的并发上限。少于 300 帧的短视频默认不分片；测试时可用 `EPISODE_SHARD_MIN_FRAMES` 调整阈值。每个渲染任务会创建隔离的临时项目视图，用 `override.cfg` 在 Movie Maker 初始化前设置真实帧缓冲尺寸，因此 1080p 不再暗中生成 4K PNG，4K 也不经过低分辨率放大。

批量脚本会按实际分辨率路由输出：4K 写入 `renders/final/<episode>.mp4`，1080p 自动写入 `renders/previews/<episode>--1080p-preview.mp4`，避免审查片覆盖正式成片。

结构审查可用 `EPISODE_RENDER_WIDTH=1920 EPISODE_RENDER_HEIGHT=1080` 输出 1080p；在最终 MMX 旁白尚未生成时，可附加 `EPISODE_SKIP_NARRATION=1` 生成无声预览。正式交付仍使用 Episode 声明的 3840×2160。

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
bash tests/test_formula_assets.sh
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
