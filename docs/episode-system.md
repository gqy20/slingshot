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

`display_hook` 只负责短屏幕标题；`question` 与 narration 负责完整表述。`beats` 是连续、无重叠的绝对时间线，每项包含 Phase、shot、focus、overlay、formula step 与 sfx cue。Loader 会拒绝时间缺口、重叠、重复 ID 和未覆盖完整时长的配置。

科学解释使用 `story.explanation` 描述 `relation`（变量关系）或 `derivation`（逐步推导）。每一步只保留一条公式和一句白话结论，条件固定显示在步骤轨道下方。公式主行、推导行、条件说明分别使用 `VideoFormulaMain`、`VideoFormulaStep`、`VideoFormulaMeta`，避免公式与普通正文争夺层级。

## 输出目录

- `renders/final/`：正式 Episode 的 MP4、JSON sidecar 与 manifest。
- `renders/frames/<episode>/`：通过 `scripts/extract_frame.sh` 生成的单帧。
- `renders/contact-sheets/<episode>/`：七节拍等联络表及采样说明。
- `renders/previews/`：不作为正式交付的视觉实验。
- `renders/smoke/`：框架和冒烟测试产物。
- `renders/narration/<episode>/`：原始配音、标准化母版、SRT 与响度报告。
- `renders/audio/<episode>/`：由 Beat cue 确定性生成的音效轨与 provenance。

最终 bundle 使用相同 basename；抽帧采用 `<episode>--<milliseconds>ms--<label>.png`。`renders/.gdignore` 阻止 Godot 把生成媒体当作项目资源导入。

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
3. 默认将完整帧区间拆成两个绝对时间分片，启动两个 Godot Movie Maker Worker 并行回放同一份记录。
4. 忽略排版空白后，逐字符验证讲稿正文与 mmx SRT 正文完全一致。
5. 验证 MiniMax `<#x#>` 停顿标记和发音表，对配音做两遍响度分析，生成 `-16 ±1 LUFS`、`≤ -1.5 dBTP`、48 kHz 单声道 PCM24 母版。
6. 读取同一份 SRT，在 3840×2160 根视口中，将 1920×1080 设计坐标按 2 倍直接绘制；不存在 1080p 视频放大步骤。
7. 将物理轨迹映射到分阶段 Plot Area，并逐帧审计小鸟、速度箭头与文字保留区的相交情况。
8. 校验分片帧数及相邻边界，按全局帧号合并 PNG，再使用一次 FFmpeg 编码 H.264；Beat 音效先由解说 sidechain 压低，再与标准化语音混合并编码为 AAC。
9. 复测 AAC 交付音轨，要求 `-16 ±1 LUFS`、`≤ -1.0 dBTP`、48 kHz 单声道。
10. 原子发布 MP4、分析 sidecar 与 provenance manifest。

视频 Manifest 记录 Episode、RunRecord、MP4、原始配音、标准化母版和字幕的 SHA-256，以及 Godot、渲染器、分片 Worker 数、音视频流、实测 LUFS/真峰值和正文一致性结论。解说 Manifest 另外记录讲稿、mmx 模型、音色和真实音频时长。修改音频时可仅重新混音，不必重渲染 4K 画面。

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

EpisodeLayout 为 Question、Explain、Setup、Flight、Compare 分别定义 Plot Area 和文字保留区。动画坐标使用等比映射，避免改变抛物线角度；Compare 阶段将轨迹压缩到左侧，右侧独占结果面板。渲染入口会对 RunRecord 的所有飞行帧执行主体包围盒审计。趣味动效只读取视频时间、速度和事件，作为物理位置之上的视觉变换层。

视觉系统采用 Editorial Science Lab token。背景、表面、分割线、正文、次级文字和品牌强调色由 `content/themes/laboratory.json` 集中定义；界面只使用中性色与单一琥珀强调色。每集的实验组颜色来自共享的低值冷色到高值暖色数据色阶，只允许出现在轨迹、小鸟、图例色条和结果色条中，胜者通过线宽、星标和光环表达。

排版使用项目内置的 Sarasa Gothic SC、Sarasa Mono SC 与 Smiley Sans。`assets/video_typography.tres` 定义 Hero、Accent、Display、Title、Section、Body、Subtitle、Data、DataMeta、Meta 以及三种 Formula 角色；HUD 只能选择角色，不得自行创建临时字号。Hero 与 Accent 使用得意黑表现片头问题和结果短强调，并以 Sarasa Gothic SC Bold 作为缺字回退；连续字幕、正文与解释标题使用 Gothic，公式、计时和实验数据使用 Mono。得意黑不得用于长段文字、字幕、图例或数据列。
