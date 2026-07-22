# 弹弓物理演示视频

一个完全由 GDScript 构建画面的 2D 教学短片。程序自动完成蓄力、发射、抛体运动、碰撞慢动作和结果总结，并在画面中显示速度、动能、动量、碰撞冲量与平均力估计。

制作和渲染不需要打开 Godot 编辑器。

## 项目结构

```text
src/
├── app.gd       # 启动、参数解析和依赖组装
├── core/        # 不依赖场景树的配置、物理与 telemetry
└── scene/       # 场景节点、视觉节点和镜头状态机
```

`core/` 可以脱离运行场景进行测试；`scene/` 包含所有继承 Godot 节点的运行时组件。

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

## 一条命令生成视频

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

第一版固定输出 1920×1080、60 FPS。冲突的分辨率或 FPS 会在渲染前被拒绝，以免构图被裁切。

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
