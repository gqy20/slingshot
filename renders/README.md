# Render output layout

Generated media is not committed. Every output category has one stable home:

```text
renders/
├── final/                         publish-ready episode bundles
├── frames/<episode>/              individually extracted review frames
│   └── dense-2fps/                 2 samples/second plus index and manifest
├── contact-sheets/<episode>/      seven-beat and other tiled reviews
│   └── dense-2fps/                 24 samples/page, 12 seconds/page
├── previews/                      non-final visual experiments
├── smoke/                         framework and smoke-test artifacts
├── narration/<episode>/           speech, subtitles, loudness, provenance
├── audio/<episode>/               deterministic beat SFX and provenance
└── archive/
    ├── releases/<version>/         recoverable superseded episode bundles
    ├── validation/                 equivalence and pipeline evidence
    └── legacy/                     historical outputs without full provenance
```

Naming rules:

- final bundle: `<episode>.mp4`, `<episode>.json`, `<episode>.manifest.txt`
- frame: `<episode>--<milliseconds>ms--<label>.png`
- contact sheet: `<episode>--<review-kind>.png` with a matching `.txt`
- preview bundle: `<episode>.mp4`, `<episode>.json`, `<episode>.manifest.txt`;
  every review render replaces the same three files
- dense sample: `<episode>--<milliseconds>ms--sample.png`

Use `scripts/extract_frame.sh` instead of writing one-off frame names. The
`.gdignore` marker prevents Godot from creating `.import` files for generated
PNG, WAV, and MP4 files.

Use `scripts/review_dense.sh <episode.mp4>` for the required 2 fps review. A
120-second episode produces 240 full-resolution samples, one TSV row per
sample, and 10 contact-sheet pages.
