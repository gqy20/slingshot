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
  -> PNG sequence + mmx narration -> H.264/AAC MP4
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
- 固定 1920×1080、可选 30/60 FPS 输出规格。

Variant override 只允许修改 physics.* 和 scene.* 中已经存在的键。每个 Variant 会重新经过 preset 校验。

## 确定性导出

scripts/render_episode.sh 创建独立临时目录：

1. 使用无界面 Godot 顺序运行所有 Variant。
2. 写入带引擎版本的 RunRecord。
3. 重新启动 Godot，以 Movie Maker 模式回放记录。
4. 读取 mmx 生成的 SRT，在 Godot 中绘制避开实验主体的字幕安全带。
5. 使用 FFmpeg 编码 H.264，并将对应 MP3 重采样、编码为 AAC。
6. 原子发布 MP4、分析 sidecar 与 provenance manifest。

视频 Manifest 记录 Episode、RunRecord、MP4、配音和字幕的 SHA-256，以及 Godot、渲染器和音视频流信息。解说 Manifest 另外记录讲稿、mmx 模型、音色和真实音频时长。修改字幕、布局或主题后可以复用 RunRecord；当前 CLI 为保持简单，每次执行都会重新模拟。

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
