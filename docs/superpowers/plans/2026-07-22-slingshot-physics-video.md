# Slingshot Physics Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic, pure-GDScript 2D slingshot physics demonstration that renders a validated 12-second 1080p60 MP4 from one CLI command.

**Architecture:** A minimal root scene delegates to a preset loader, a pure analytical physics module, runtime-created rigid bodies, a phase director, telemetry, and code-drawn visuals. Godot writes a lossless PNG sequence under Xvfb; a shell wrapper encodes it with FFmpeg, validates it with ffprobe, and atomically publishes the MP4 and JSON sidecar.

**Tech Stack:** Godot 4.7.1, GDScript, Godot Physics 2D, Bash, Xvfb, FFmpeg/ffprobe, JSON.

---

## File Map

- `project.godot` — fixed resolution, physics, renderer, and main-scene settings.
- `main.tscn` — minimal root `Node2D` that attaches `src/app.gd`.
- `presets/default.json` — accepted 12-second shot configuration.
- `presets/smoke.json` — one-second render configuration for pipeline tests.
- `src/app.gd` — CLI parsing, dependency construction, error exit, and sidecar path wiring.
- `src/core/preset_loader.gd` — JSON parsing, defaults, type/range checks, normalization.
- `src/core/shot_model.gd` — pure formulas and unit conversions.
- `src/scene/bird_body.gd` — runtime bird rigid body, collision geometry, code-drawn character.
- `src/scene/target_body.gd` — runtime target rigid body, collision geometry, code-drawn character.
- `src/scene/world_canvas.gd` — background, ground, sling, trajectory, vectors, trail, and impact effects.
- `src/scene/hud.gd` — titles, formulas, readouts, energy bars, and summary panel.
- `src/scene/camera_rig.gd` — deterministic impact zoom and shake.
- `src/core/telemetry.gd` — live SI-unit snapshot, collision record, and sidecar serialization.
- `src/scene/shot_director.gd` — intro/aim/flight/impact/aftermath/summary state machine.
- `tests/run_tests.gd` — dependency-free headless test runner.
- `tests/test_shot_model.gd` — numerical physics tests.
- `tests/test_preset_loader.gd` — preset validation tests.
- `tests/test_director.gd` — phase timing tests independent of rendering.
- `scripts/render.sh` — production render, encode, probe, and atomic publication.
- `scripts/smoke_test.sh` — short end-to-end render assertion.
- `.gitignore` — Godot imports, render products, logs, and temporary files.
- `README.md` — install, test, preview, and production render commands.

## Task 1: Establish a Parseable Godot Project and Test Harness

**Files:**
- Create: `.gitignore`
- Create: `project.godot`
- Create: `main.tscn`
- Create: `src/app.gd`
- Create: `tests/run_tests.gd`

- [ ] **Step 1: Write the minimal test runner before the project exists**

```gdscript
extends SceneTree

var passed := 0
var failed := 0

func check(condition: bool, message: String) -> void:
    if condition:
        passed += 1
    else:
        failed += 1
        push_error("FAIL: " + message)

func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
    check(absf(actual - expected) <= tolerance,
        "%s (actual=%f expected=%f)" % [message, actual, expected])

func _initialize() -> void:
    print("TESTS: %d passed, %d failed" % [passed, failed])
    quit(0 if failed == 0 else 1)
```

- [ ] **Step 2: Run the test command and verify the project is absent**

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: FAIL because `project.godot` does not exist.

- [ ] **Step 3: Add the minimal project and root scene**

`project.godot` must set `run/main_scene`, 1920×1080 viewport size, canvas-items stretch, 60 rendered FPS, 120 physics ticks, 981 px/s² gravity, GL Compatibility rendering, and transparent-background-disabled Movie Maker output.

`main.tscn` contains only:

```text
[gd_scene load_steps=2 format=3]

[ext_resource path="res://src/app.gd" type="Script" id="1"]

[node name="SlingshotVideo" type="Node2D"]
script = ExtResource("1")
```

The initial `src/app.gd` prints a startup marker and exits after two process frames when `--smoke-boot` is passed.

- [ ] **Step 4: Run parser and harness checks**

Run: `godot --headless --path . --editor --quit`

Expected: exit 0 with no `SCRIPT ERROR`.

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: `TESTS: 0 passed, 0 failed` and exit 0.

- [ ] **Step 5: Commit the skeleton**

```bash
git add .gitignore project.godot main.tscn src/app.gd tests/run_tests.gd
git commit -m "build: scaffold CLI Godot video project"
```

## Task 2: Implement the Pure Physics Model with TDD

**Files:**
- Create: `tests/test_shot_model.gd`
- Create: `src/core/shot_model.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Add failing numerical tests**

The test case loads `shot_model.gd` and checks:

```gdscript
func run(t) -> void:
    t.check_close(ShotModel.spring_energy(160.0, 0.9), 64.8, 0.0001, "spring energy")
    var speed := ShotModel.launch_speed(160.0, 0.9, 1.0, 0.82)
    t.check_close(speed, 10.3088, 0.0002, "launch speed")
    var velocity := ShotModel.launch_velocity(speed, 45.0)
    t.check_close(velocity.x, 7.2894, 0.0002, "horizontal velocity")
    t.check_close(velocity.y, -7.2894, 0.0002, "vertical velocity")
    var p := ShotModel.projectile_position(Vector2(2.4, 7.6), velocity, 9.81, 1.0)
    t.check_close(p.x, 9.6894, 0.0002, "projectile x")
    t.check_close(p.y, 5.2156, 0.0002, "projectile y")
    t.check_close(ShotModel.kinetic_energy(1.0, velocity), 53.136, 0.002, "kinetic energy")
    t.check(ShotModel.momentum(1.0, Vector2(3, 4)) == Vector2(3, 4), "momentum")
    t.check(ShotModel.impulse(1.0, Vector2(4, 0), Vector2(1, 0)) == Vector2(-3, 0), "impulse")
    t.check_close(ShotModel.average_force(Vector2(3, 4), 0.01), 500.0, 0.001, "average force")
    t.check(ShotModel.meters_to_pixels(Vector2(2, 3), 100.0) == Vector2(200, 300), "meters to pixels")
```

Register `preload("res://tests/test_shot_model.gd").new()` in `run_tests.gd`.

- [ ] **Step 2: Run tests to verify failure**

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: parser/load failure because `src/core/shot_model.gd` is missing.

- [ ] **Step 3: Implement exact pure functions**

`shot_model.gd` extends `RefCounted` and exposes static functions `spring_energy`, `launch_speed`, `launch_velocity`, `projectile_position`, `kinetic_energy`, `rotational_energy`, `momentum`, `impulse`, `average_force`, `meters_to_pixels`, `pixels_to_meters`, and `velocity_px_to_mps`. Invalid mass, stiffness, scale, efficiency, or sample time returns `NAN` or `Vector2(INF, INF)` consistently and is covered by tests.

- [ ] **Step 4: Run tests to verify pass**

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: all physics checks pass and exit 0.

- [ ] **Step 5: Commit physics model**

```bash
git add src/core/shot_model.gd tests/test_shot_model.gd tests/run_tests.gd
git commit -m "feat: add deterministic slingshot physics model"
```

## Task 3: Validate and Normalize JSON Presets with TDD

**Files:**
- Create: `tests/test_preset_loader.gd`
- Create: `src/core/preset_loader.gd`
- Create: `presets/default.json`
- Create: `presets/smoke.json`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Add failing preset tests**

Tests call `validate_dict()` with the accepted schema and verify the normalized `launch_position_m` and colors. Separate cases reject 1280×720, FPS 30, nonpositive mass, efficiency above 1, malformed coordinate arrays, invalid colors, and missing `id`. A final test loads `res://presets/default.json` and checks `duration_sec == 12.0`.

- [ ] **Step 2: Run tests to verify failure**

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: parser/load failure because `preset_loader.gd` is missing.

- [ ] **Step 3: Implement loader and presets**

The loader returns this stable result contract:

```gdscript
{"ok": bool, "error": String, "warnings": Array[String], "preset": Dictionary}
```

It requires `id`, fixes the first version at 1920×1080 and 60 FPS, accepts duration 1–120 seconds, validates finite positive physical values, requires efficiency in `(0, 1]`, converts scene coordinate arrays to `Vector2`, and converts HTML strings to `Color`. It warns on unknown top-level keys but rejects malformed known sections.

`smoke.json` uses the same physics and scene values as the default preset but a one-second duration. The director's summary rule (`time >= duration_sec - 1.0`) therefore displays the summary immediately and exits cleanly without requiring collision.

- [ ] **Step 4: Run tests to verify pass**

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: physics and preset tests pass.

- [ ] **Step 5: Commit configuration support**

```bash
git add src/core/preset_loader.gd presets tests
git commit -m "feat: add validated render presets"
```

## Task 4: Build Code-Drawn Bodies and Scene Visuals

**Files:**
- Create: `src/scene/bird_body.gd`
- Create: `src/scene/target_body.gd`
- Create: `src/scene/world_canvas.gd`
- Create: `src/scene/hud.gd`
- Create: `src/scene/camera_rig.gd`
- Create: `tests/test_visual_nodes.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Add a failing construction test**

The test instantiates each script, calls its public setup method, and verifies:

- Bird has one `CollisionShape2D`, mass 1.0, frozen initial state, and contact monitoring enabled.
- Target has one `CollisionShape2D`, mass 3.0, frozen initial state, and a finite inertia after entering the tree.
- World canvas accepts a normalized preset and a trajectory point array.
- HUD accepts a telemetry snapshot without mutating it.
- Camera rig returns to zero offset after `reset_effects()`.

- [ ] **Step 2: Run tests to verify missing scripts fail**

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: load failure for the first missing visual script.

- [ ] **Step 3: Implement focused visual nodes**

`BirdBody` extends `RigidBody2D`, creates a circular collision shape with 28 px radius, draws body/wing/eye/beak primitives, and exposes `setup(position_px, mass_kg, color)` plus `launch(velocity_px_s)`.

`TargetBody` extends `RigidBody2D`, creates a 110×150 px rectangular collider, draws a rounded-looking stacked crate character with eyes and a bullseye, and exposes `setup(position_px, mass_kg, color)`.

`WorldCanvas` extends `Node2D` and draws sky, clouds, ground, sling forks/band, an analytical dotted path, bird trail, velocity and gravity arrows, impact shock rings, and vector labels. Its public state is updated through `set_snapshot(snapshot)` and `set_phase(phase)`.

`HUD` extends `CanvasLayer`, creates all `Label`, `Panel`, and `ProgressBar` nodes in code using Noto Sans CJK SC when available, and switches content by phase. It formats SI values to two decimals and marks force as `平均力估计`.

`CameraRig` extends `Camera2D`; seeded sine components create shake without wall-clock time. `trigger_impact()` starts zoom/shake and `reset_effects()` restores `zoom = Vector2.ONE` and `offset = Vector2.ZERO`.

- [ ] **Step 4: Run headless construction tests and parser check**

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: all construction checks pass.

Run: `godot --headless --path . --editor --quit`

Expected: exit 0 without script errors.

- [ ] **Step 5: Commit code-drawn presentation**

```bash
git add src/world src/visuals tests
git commit -m "feat: add code-drawn slingshot scene"
```

## Task 5: Add Telemetry and the Phase Director with TDD

**Files:**
- Create: `src/core/telemetry.gd`
- Create: `src/scene/shot_director.gd`
- Create: `tests/test_director.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write failing phase and collision tests**

Tests verify that deterministic timestamps map to `INTRO`, `AIM`, `FLIGHT`, `IMPACT`, `AFTERMATH`, and `SUMMARY`; the first collision record cannot be overwritten; `J = m(v_after-v_before)` is preserved; and a no-collision render produces `collision.detected == false` rather than missing fields.

- [ ] **Step 2: Run tests to verify failure**

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: load failure for director or telemetry.

- [ ] **Step 3: Implement telemetry snapshots and state machine**

`Telemetry` stores scale, masses, live position/velocity, sling quantities, energies, frame index, and one collision dictionary. `record_collision(before, after, target_before, target_after, sample_dt)` calculates impulse and average-force estimate through `ShotModel`. `write_sidecar(path, preset_id, duration)` writes JSON only after ensuring the parent directory exists.

`ShotDirector` exposes a `phase_changed(phase)` signal, phase enum, `configure(preset, dependencies)`, `advance_for_test(time)`, and runtime `_process`. It performs:

- Intro until 2.0 seconds.
- Aim from 2.0 to 3.5 seconds.
- Launch exactly once at 3.5 seconds.
- Impact phase when the first valid collision occurs.
- Aftermath 2.0 simulation seconds after collision.
- Summary for the final second.
- Normal `get_tree().quit()` at the preset duration.

The director samples pre-contact velocity continuously and samples post-contact velocity on the next physics frame. It changes `Engine.time_scale` only during the impact presentation and restores it before summary or shutdown.

- [ ] **Step 4: Run all headless tests**

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: all physics, preset, visual, telemetry, and director tests pass.

- [ ] **Step 5: Commit orchestration logic**

```bash
git add src/telemetry src/director tests
git commit -m "feat: orchestrate shot phases and telemetry"
```

## Task 6: Integrate the Runtime Application

**Files:**
- Modify: `src/app.gd`
- Modify: `project.godot`
- Create: `tests/test_boot.sh`

- [ ] **Step 1: Add a failing CLI boot test**

`tests/test_boot.sh` runs the main scene under Xvfb with `--preset presets/smoke.json --boot-only`, captures stdout/stderr, requires exit 0, requires `[app] preset=smoke-shot`, and rejects `SCRIPT ERROR` or a line beginning with `ERROR:`.

- [ ] **Step 2: Run boot test to verify failure**

Run: `bash tests/test_boot.sh`

Expected: FAIL because the app does not yet construct dependencies or parse `--preset`.

- [ ] **Step 3: Wire the complete runtime**

`app.gd` parses `--preset`, `--sidecar`, and `--boot-only`; defaults to `res://presets/default.json`; validates the preset; applies gravity and physics tick settings; instantiates world canvas, bird, target, camera, HUD, telemetry, and director; connects body contact and phase signals; precomputes trajectory samples with `ShotModel`; and adds children in deterministic order.

On setup error it prints one `[app:error]` line and calls `get_tree().quit(2)`. In boot-only mode it prints normalized key values and exits after two frames without starting the shot.

- [ ] **Step 4: Run boot and unit tests**

Run: `bash tests/test_boot.sh`

Expected: `BOOT TEST: passed`.

Run: `godot --headless --path . --script res://tests/run_tests.gd`

Expected: all tests pass.

- [ ] **Step 5: Commit runtime integration**

```bash
git add src/app.gd project.godot tests/test_boot.sh
git commit -m "feat: integrate deterministic slingshot runtime"
```

## Task 7: Implement the CLI Render and End-to-End Smoke Test

**Files:**
- Create: `scripts/render.sh`
- Create: `scripts/smoke_test.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Write a failing smoke test around the missing renderer**

`scripts/smoke_test.sh` creates a unique temporary directory, calls `scripts/render.sh presets/smoke.json <temp>/smoke.mp4`, requires an MP4 and sidecar, and validates with ffprobe:

```text
codec_name=h264
width=1920
height=1080
avg_frame_rate=60/1
duration between 0.95 and 1.10 seconds
```

- [ ] **Step 2: Run the smoke test to verify failure**

Run: `bash scripts/smoke_test.sh`

Expected: FAIL because `scripts/render.sh` does not exist.

- [ ] **Step 3: Implement production render orchestration**

`render.sh` uses `set -euo pipefail`, resolves the project root, checks `godot`, `xvfb-run`, `ffmpeg`, and `ffprobe`, validates input/output suffixes, makes a unique temporary directory, and installs an EXIT trap. It invokes:

```bash
xvfb-run -a godot --path "$PROJECT_ROOT" \
  --rendering-method gl_compatibility \
  --write-movie "$FRAME_DIR/frame.png" \
  --fixed-fps 60 --disable-vsync \
  -- --preset "$PRESET_ABS" --sidecar "$SIDECAR_TMP"
```

It rejects missing frames, encodes `frame%08d.png` with `libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart`, probes the output, then moves the MP4 and JSON sidecar to final names only after validation. On success it removes temporary frames; on failure it prints the preserved diagnostic directory.

- [ ] **Step 4: Run the end-to-end smoke render**

Run: `bash scripts/smoke_test.sh`

Expected: `RENDER SMOKE: passed`, exit 0, valid MP4 and JSON.

- [ ] **Step 5: Commit the rendering pipeline**

```bash
git add scripts .gitignore
git commit -m "feat: render and validate video from CLI"
```

## Task 8: Render and Review the Full 12-Second Acceptance Video

**Files:**
- Modify if the acceptance evidence exposes a defect: `src/app.gd`
- Modify if the acceptance evidence exposes a defect: `src/scene/shot_director.gd`
- Modify if the acceptance evidence exposes a defect: `src/core/telemetry.gd`
- Modify if the acceptance evidence exposes a defect: `src/scene/world_canvas.gd`
- Modify if the acceptance evidence exposes a defect: `src/scene/hud.gd`
- Modify if the acceptance evidence exposes a defect: `scripts/render.sh`
- Create: `renders/.gitkeep`

- [ ] **Step 1: Render the accepted default preset**

Run: `scripts/render.sh presets/default.json renders/slingshot-physics.mp4`

Expected: a validated 1920×1080 60 FPS MP4 and `renders/slingshot-physics.json`.

- [ ] **Step 2: Generate an eight-frame contact sheet for visual inspection**

Use FFmpeg's `fps=2/3,scale=480:-1,tile=4x2` filters to create `renders/slingshot-physics-contact-sheet.png`. Inspect it for all six phases, unclipped Chinese text, readable vectors, target collision, and a visible summary.

- [ ] **Step 3: Inspect telemetry and media metadata**

Run: `ffprobe -v error -show_entries stream=codec_name,width,height,avg_frame_rate -show_entries format=duration -of json renders/slingshot-physics.mp4`

Expected: H.264, 1920×1080, 60/1, duration within one frame of 12 seconds.

Run: `jq . renders/slingshot-physics.json`

Expected: finite collision time, speeds, impulse, energies, frame count, and `collision.detected: true`.

- [ ] **Step 4: Re-run the complete verification suite**

Run:

```bash
godot --headless --path . --script res://tests/run_tests.gd
bash tests/test_boot.sh
bash scripts/smoke_test.sh
git diff --check
```

Expected: every command exits 0; no test failures or whitespace errors.

- [ ] **Step 5: Commit acceptance corrections and render placeholder**

Do not commit generated MP4, PNG frames, contact sheets, logs, or sidecars. Commit only source corrections and `renders/.gitkeep`:

```bash
git add src presets scripts tests renders/.gitkeep
git commit -m "feat: complete slingshot physics video"
```

## Task 9: Document the CLI Workflow

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write usage documentation**

Document requirements, installed Godot version, test commands, preset fields, one-second smoke render, full render, output files, Xvfb's harmless input-method/V-Sync warnings, and the distinction between collision impulse and estimated average force.

- [ ] **Step 2: Verify every documented command**

Run the exact test and render commands copied from the README. Expected: all exit 0 and paths match the documented outputs.

- [ ] **Step 3: Commit documentation**

```bash
git add README.md
git commit -m "docs: explain CLI video workflow"
```

## Final Verification Gate

- [ ] `godot --version` reports `4.7.1.stable.official`.
- [ ] Headless GDScript suite reports zero failures.
- [ ] Xvfb boot test exits zero without script errors.
- [ ] One-second render smoke test passes ffprobe validation.
- [ ] Full render is H.264, 1920×1080, 60 FPS, and 12 seconds within one-frame tolerance.
- [ ] Sidecar records a collision with finite SI-unit telemetry.
- [ ] Contact sheet visibly contains aim, flight, impact, aftermath, and summary content.
- [ ] `git diff --check` is clean.
- [ ] Generated media remains ignored and uncommitted.
