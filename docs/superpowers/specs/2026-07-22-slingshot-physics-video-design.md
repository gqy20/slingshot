# Slingshot Physics Video Design

## Purpose

Build a short, deterministic 2D educational video in Godot that shows a cartoon bird launched from a slingshot, its projectile motion, and the physical response when it strikes a target. Authoring and rendering must be controllable from the command line without opening the Godot editor.

The first deliverable is a 1920×1080, 60 FPS, 12-second MP4 generated from code and a JSON preset. FFprobe may report a duration that differs by at most one video frame because of container time-base rounding.

## Goals

- Create every visible object at runtime with GDScript; use no required raster artwork.
- Combine an appealing cartoon presentation with physically meaningful annotations.
- Render deterministically through Godot Movie Maker and FFmpeg.
- Allow shot parameters to be changed through JSON without editing scenes.
- Produce a valid MP4 and machine-readable render metadata in one CLI command.
- Test the analytical physics calculations independently from rendering.

## Non-goals

- Interactive gameplay or mouse-controlled aiming.
- A general-purpose video editor.
- Photorealistic rendering or a 3D scene.
- Narration, music, localization, or externally sourced art in the first version.
- Claiming an exact instantaneous collision force from a discrete physics simulation.

## Visual Direction

The video uses a clean, colorful, side-view composition inspired by a classroom demonstration rather than copying a specific commercial game. The bird and target are friendly geometric characters drawn with `CanvasItem._draw()`. Scientific overlays use restrained dark panels, high-contrast labels, colored vector arrows, and dotted trajectories.

The scene is divided into three visual zones:

- Left: slingshot, launch parameters, and starting position.
- Center: projectile trajectory and live velocity/gravity vectors.
- Right: target stack, collision visualization, and post-impact motion.

The camera remains mostly fixed for legibility. Impact uses a brief zoom, shake, hit flash, shock ring, and slow-motion segment. These effects decorate the physical event without changing the reported measurements.

## Timeline

| Time | Sequence |
| --- | --- |
| 0.0–2.0 s | Establish the scene. Introduce bird mass, target mass, gravity, launch angle, and scale. |
| 2.0–3.5 s | Pull the sling automatically. Show stretch distance, spring energy, predicted launch speed, and a dotted analytical trajectory. |
| 3.5–6.0 s | Release the bird. Show its trail, velocity vector, velocity components, height, kinetic energy, and momentum. |
| 6.0–8.0 s | Detect impact. Enter visual slow motion, show before/after velocity, impulse, momentum change, estimated average force, and energy transfer. |
| 8.0–11.0 s | Follow the target's translation and rotation. Compare pre-impact and post-impact energy bars. |
| 11.0–12.0 s | Freeze on a concise result card, then exit cleanly so Movie Maker finalizes the output. |

Exact phase boundaries are derived from the configured launch and collision events where appropriate. The preset's `duration_sec` remains the hard upper bound.

## Units and Physics Model

The simulation uses a fixed visual scale of 100 pixels per meter. Godot's 2D gravity is configured as 981 pixels per second squared, corresponding to 9.81 meters per second squared.

Default quantities:

- Bird mass: 1.0 kg.
- Target mass: 3.0 kg.
- Launch angle: 45 degrees.
- Launch speed: approximately 10.31 m/s with the default preset, derived from the configured sling.
- Physics tick rate: 120 Hz.
- Video frame rate: 60 FPS.

The sling is an explanatory launch model, not a simulated deformable band. Its stored elastic energy is:

```text
E_s = 1/2 k x²
```

The configured efficiency converts elastic energy to bird kinetic energy:

```text
1/2 m v² = efficiency × 1/2 k x²
v = x × sqrt(efficiency × k / m)
```

The launch is applied to the bird as an initial linear velocity or equivalent central impulse. The predicted trajectory uses the same initial state and gravity as the simulation:

```text
x(t) = x₀ + v₀ cos(θ)t
y(t) = y₀ - v₀ sin(θ)t + 1/2 gt²
```

The screen coordinate conversion accounts for Godot's positive-down Y axis.

Displayed flight quantities are:

```text
kinetic energy: E_k = 1/2 m|v|²
momentum:       p = mv
```

Collision telemetry samples the bird and target velocities around the first valid contact. The displayed bird impulse is derived from momentum change:

```text
J = Δp = m(v_after - v_before)
```

An average-force estimate may be shown as `F_avg ≈ |J| / Δt`, where `Δt` is the explicitly displayed sampling interval. The UI labels this value as an estimate. It does not call it instantaneous force.

Energy accounting reports translational and rotational kinetic energy where available. The difference is labeled as energy transferred to deformation, sound, heat, and unresolved contact effects; it is not presented as numerical error alone.

## Architecture

### Minimal Godot Project

`project.godot` contains resolution, renderer, physics tick, gravity, and main-scene settings. `main.tscn` contains only a root `Node2D` with the application script. All production visual and physics nodes are created at runtime.

### Application

`src/app.gd` owns startup and shutdown. It parses user arguments after `--`, loads and validates the preset, constructs the scene services, starts the director, reports fatal errors to stderr, and exits with a nonzero code when setup fails.

### Preset Loader

`src/core/preset_loader.gd` converts JSON into a normalized configuration. It validates required types and ranges, fills documented defaults, rejects non-finite numbers, and reports unknown keys as warnings. The renderer never depends directly on unvalidated JSON dictionaries.

### Physics Model

`src/core/shot_model.gd` contains pure analytical calculations: sling energy, launch speed, velocity components, projectile samples, momentum, kinetic energy, impulse, and average-force estimate. It has no dependency on the scene tree and is the main unit-test target.

### Runtime Bodies

`src/scene/bird_body.gd` and `src/scene/target_body.gd` create their collision shapes and draw their cartoon appearance. The bird records velocity samples. A contact monitor captures the first bird-target collision and sends a structured event to telemetry.

### Director

`src/scene/shot_director.gd` is a state machine with `INTRO`, `AIM`, `FLIGHT`, `IMPACT`, `AFTERMATH`, and `SUMMARY` phases. It is the only component allowed to change cinematic time scale, camera framing, and phase visibility. It exits the tree normally when the summary ends or the duration safety limit is reached.

Slow motion affects simulation presentation consistently. Telemetry uses the physics step's actual simulation interval rather than wall-clock render time.

### Visual Layers

- `src/scene/world_canvas.gd`: sky, terrain, slingshot, target decorations, trajectory, trails, arrows, and impact effects.
- `src/scene/hud.gd`: numeric readouts, formulas, energy bars, phase titles, and result card.
- `src/scene/camera_rig.gd`: impact zoom and deterministic procedural shake.

Visual nodes consume read-only snapshots from telemetry. They do not calculate authoritative physics values.

### Telemetry

`src/core/telemetry.gd` publishes a typed dictionary snapshot for each video frame and stores the collision record. It converts pixels to meters and formats SI values. It also writes a final JSON sidecar containing preset identity, collision time, speeds, impulse, energy values, frame count, and render duration.

### CLI Orchestration

`scripts/render.sh` is the supported entry point:

```text
scripts/render.sh presets/default.json [output.mp4]
```

It performs these steps:

1. Resolve absolute input and output paths.
2. Validate required commands and create a unique temporary render directory.
3. Run Godot under Xvfb with `--write-movie`, fixed FPS, and the preset argument.
4. Encode the PNG sequence to H.264 MP4 with `yuv420p` pixel format and `+faststart`.
5. Validate resolution, frame rate, duration, and video stream with `ffprobe`.
6. Atomically move the completed MP4 and sidecar into place.
7. Preserve diagnostic logs on failure and clean temporary frame files on success.

PNG sequence is the first-version intermediate because it is lossless, easy to inspect, and robust if encoding must be retried. A later optimization may add OGV previews or a custom MovieWriter without changing the scene architecture.

## Preset Schema

The initial preset supports:

```json
{
  "id": "basic-shot",
  "seed": 20260722,
  "duration_sec": 12.0,
  "video": {"width": 1920, "height": 1080, "fps": 60},
  "physics": {
    "pixels_per_meter": 100.0,
    "gravity_mps2": 9.81,
    "bird_mass_kg": 1.0,
    "target_mass_kg": 3.0,
    "spring_k_npm": 160.0,
    "stretch_m": 0.9,
    "efficiency": 0.82,
    "launch_angle_deg": 45.0
  },
  "scene": {
    "ground_y_m": 9.2,
    "launch_position_m": [2.4, 7.6],
    "target_position_m": [13.2, 7.6],
    "bird_color": "#E94F37",
    "accent_color": "#35C2FF",
    "target_color": "#73C66A"
  }
}
```

Resolution is fixed to 1920×1080 in the first deliverable even though it appears in the schema. A conflicting value fails validation rather than producing a cropped composition.

Scene coordinates are expressed in meters from the viewport's top-left origin, with positive Y pointing downward to match Godot. The default launch and target centers share the same elevation. With the default sling parameters, the ideal no-drag range is approximately 10.84 meters, placing the target in the descending collision region after accounting for body radii and discrete integration.

## Determinism

- Godot runs with fixed video FPS and a fixed 120 Hz physics tick.
- All procedural variation comes from a seeded `RandomNumberGenerator` owned by the director or a named substream.
- No behavior reads wall-clock time.
- The same Godot version, preset, and renderer should produce the same measured telemetry. Minor pixel differences across rendering drivers are acceptable.
- Tests compare analytical quantities with tolerances rather than requiring byte-identical video frames.

## Error Handling

- Missing or invalid preset: print a precise error, exit nonzero, and do not invoke FFmpeg.
- Unsupported resolution/FPS: reject during preset validation.
- Godot crash or timeout: terminate the render, retain its log, and do not publish a partial MP4.
- Missing frame sequence: treat as render failure.
- FFmpeg or ffprobe failure: retain frames and logs for diagnosis.
- No collision before the safety deadline: continue to the summary with a visible `no collision` result and mark the sidecar accordingly.
- Movie mode shutdown: always use `SceneTree.quit()` so audio/video writers finalize correctly.

## Testing

### Headless Unit Tests

A GDScript test runner verifies:

- Elastic-energy and launch-speed calculations.
- Pixel/meter and velocity conversions.
- Projectile position at known times.
- Momentum, kinetic energy, impulse, and average force.
- Preset defaults and validation failures.
- Director phase transitions that do not require rendering.

Run with:

```text
godot --headless --path . --script res://tests/run_tests.gd
```

### Render Smoke Test

A short preset renders approximately one second under Xvfb. The test checks that frames exist, FFmpeg creates an MP4, and ffprobe reports 1920×1080 at 60 FPS with a nonzero duration.

### Full Acceptance Render

The default preset must produce:

- A playable 1920×1080 H.264 MP4 at 60 FPS and 12 seconds, within one frame of duration tolerance.
- A normal clean Godot exit without script errors.
- Visible aim, flight, impact, aftermath, and summary phases.
- A collision sidecar with finite values and consistent units.
- A predicted trajectory that visually agrees with the pre-impact path within the effects of numerical integration.
- No user interaction and no editor launch.

## Delivery Boundary

The first implementation is complete when one command renders the default 12-second video and all unit, smoke, and acceptance checks pass. Audio, multiple targets, alternate bird types, richer destruction, and batch catalogs remain follow-up work.
