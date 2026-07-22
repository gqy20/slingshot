# Episode 视频系统

Episode 系统把物理实验与视频导演分成两个确定性阶段。

## 数据流

~~~text
Episode JSON
  -> EpisodeLoader
  -> ExperimentRunner（逐个 Variant 模拟）
  -> RunRecord JSON
  -> ResultAnalyzer + EpisodeDirector
  -> ReplayTrack + EpisodeCanvas + EpisodeHud + SRT
  -> native 4K PNG sequence + standardized mmx narration -> H.264/AAC MP4
~~~

模拟阶段决定发生了什么；分析阶段决定结果意味着什么；导演阶段决定何时展示；回放阶段只负责画面，不再修改物理状态。

## Episode 配置

每个 Episode 包含：

- 一个经过验证的基础 preset；
- 2 到 9 个仅覆盖单一参数的 Variant；
- 固定的模拟时长和 tick rate；
- 问题、镜头节拍、主比较指标及结论；
- Explain 概念卡、可版本化解说稿、mmx 模型与音色；
- 可复用的视觉主题；
- 固定 3840×2160 原生输出、可选 30/60 FPS。

Variant override 只允许修改 physics.* 和 scene.* 中已经存在的键。每个 Variant 会重新经过 preset 校验。

## 确定性导出

scripts/render_episode.sh 创建独立临时目录：

1. 使用无界面 Godot 顺序运行所有 Variant。
2. 写入带引擎版本的 RunRecord。
3. 重新启动 Godot，以 Movie Maker 模式回放记录。
4. 忽略排版空白后，逐字符验证讲稿正文与 mmx SRT 正文完全一致。
5. 对配音做两遍响度分析，生成 `-16 ±1 LUFS`、`≤ -1.5 dBTP`、48 kHz 单声道 PCM24 母版。
6. 读取同一份 SRT，在 Godot 4K 根视口中绘制字幕安全带和 2 倍矢量画面。
7. 使用 FFmpeg 编码 H.264，并将标准化母版编码为 AAC 后混入。
8. 复测 AAC 交付音轨，要求 `-16 ±1 LUFS`、`≤ -1.0 dBTP`、48 kHz 单声道。
9. 原子发布 MP4、分析 sidecar 与 provenance manifest。

视频 Manifest 记录 Episode、RunRecord、MP4、原始配音、标准化母版和字幕的 SHA-256，以及 Godot、渲染器、音视频流、实测 LUFS/真峰值和正文一致性结论。解说 Manifest 另外记录讲稿、mmx 模型、音色和真实音频时长。修改音频时可仅重新混音，不必重渲染 4K 画面。

## 扩展边界

- src/core/：配置、记录结构和结果分析。
- src/simulation/：真实刚体世界和逐 Variant 模拟。
- src/playback/：RunRecord 采样与插值。
- src/video/：时间映射、程序化画面、字幕安全区、HUD 和导出生命周期。
- src/scene/：传统单次演示仍在使用的场景节点。
- content/episodes/：单集内容。
- content/narration/：供 mmx-cli 合成的逐集讲稿。
- content/themes/：跨集共享的视觉规范。

新增视频模板时，应优先扩展 Director、Layout 或 Overlay，而不是让模拟层感知镜头。
