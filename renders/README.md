# Render output layout

Generated media is not committed. Every output category has one stable home:

```text
renders/
├── final/                         publish-ready episode bundles
├── frames/<episode>/              individually extracted review frames
├── contact-sheets/<episode>/      seven-beat and other tiled reviews
├── previews/                      non-final visual experiments
├── smoke/                         framework and smoke-test artifacts
└── narration/<episode>/           speech, subtitles, loudness, provenance
```

Naming rules:

- final bundle: `<episode>.mp4`, `<episode>.json`, `<episode>.manifest.txt`
- frame: `<episode>--<milliseconds>ms--<label>.png`
- contact sheet: `<episode>--<review-kind>.png` with a matching `.txt`
- preview: `<subject>--<purpose>.mp4` with matching sidecars when present

Use `scripts/extract_frame.sh` instead of writing one-off frame names. The
`.gdignore` marker prevents Godot from creating `.import` files for generated
PNG, WAV, and MP4 files.
