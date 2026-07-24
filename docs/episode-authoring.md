# Episode 创作指南

## 1. 创建骨架

```bash
scripts/create_episode.sh s01e03-angle-demo \
  --template angle \
  --season 1 \
  --episode 3 \
  --title "更低的角度一定飞得更近吗？"
```

`angle` 生成发射角对比起点，使用 `angle_components` 解释模块；`stretch` 生成拉伸量对比起点，使用 `spring_energy` 模块。命令拒绝覆盖已有 Episode，同时生成：

- `content/episodes/<id>.json`
- `content/narration/<id>.txt`

## 2. 只编辑内容层

新 Episode 默认使用 `editorial_comparison_v1`：

```json
{
  "beat_template": "editorial_comparison_v1",
  "beat_overrides": {
    "hook": {"headline": "先看两个矛盾的结果"},
    "flight": {"focus": "angle-45"},
    "takeaway": {"focus": "angle-45"}
  }
}
```

模板根据 `question_sec`、`explain_sec`、`setup_sec`、`flight_sec`、`compare_sec` 和公式步骤数生成完整时间线。标准 Beat ID 为：

- `hook`、`controls`、`question`
- `explain-1` 至 `explain-N`
- `setup`、`prediction`
- `launch`、`flight`、`landing`
- `ranking`、`counterpoint`、`takeaway`

模板自动提供 phase、shot、mode、camera action、camera reason、intent、primary subject、layers 和连续时间。`beat_overrides` 用于改文案、焦点、提示和少量呈现参数，不能改 Beat 的 ID、阶段或时间边界。需要逐秒调优的正式成片仍可使用完整显式 `beats`，但不能和 `beat_template` 同时声明。

## 3. 选择解释模块

```json
{
  "story": {
    "explanation": {
      "kind": "relation",
      "module": "angle_components",
      "steps": []
    }
  }
}
```

当前模块：

- `angle_components`：真实回放速度方向、水平/竖直分量和滞空时间。
- `spring_energy`：弹簧拉伸尺寸、平方关系和能量柱。

新增模块时，在 `src/video/explanations/` 实现 `draw(canvas)` 与 `hides_physical_stage()`，在 `src/core/explanation_catalog.gd` 声明 ID，再在 `explanation_registry.gd` 注册实现。Canvas 不依赖 Overlay 名称选择模块。

## 4. 写作与验证

讲稿应像共同讨论问题：先描述看见的现象，再提出判断，最后说明模型边界。不要把屏幕上的公式逐字朗读，也不要先宣布结论再展示证据。

```bash
scripts/validate_episode.sh content/episodes/s01e03-angle-demo.json
godot --headless --path . --script res://tests/run_tests.gd
```

## 5. 预览与交付

```bash
EPISODE_RENDER_WIDTH=1920 EPISODE_RENDER_HEIGHT=1080 \
  scripts/render_episode.sh content/episodes/s01e03-angle-demo.json

scripts/review_dense.sh renders/previews/s01e03-angle-demo.mp4
```

预览始终覆盖 `renders/previews/<id>.mp4`、`.json` 和 `.manifest.txt`。确认结构、字幕和关键帧后，再按 Episode 声明的 3840×2160 生成正式交付。
