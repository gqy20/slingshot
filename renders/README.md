# Render output layout

Generated media is not committed. Every output category has one stable home:

```text
renders/
├── work/<id>/
│   ├── previews/                  non-final visual experiments
│   └── review/                    extracted frames, sheets, and reports
├── masters/<id>/
│   ├── picture-clean-4k.mp4       subtitle-free picture master
│   ├── program-master-4k.mp4      current approved program master
│   ├── audio/                     narration and sound-design stems
│   └── subtitles/                 optional separated subtitle masters
├── deliveries/<id>/<platform>/   self-contained upload packages
├── archive/<id>/                  recoverable superseded milestones
└── cache/                         temporary captures and Godot cache
```

Naming rules:

- current master: `masters/<id>/program-master-4k.mp4`
- clean picture master: `masters/<id>/picture-clean-4k.mp4`
- publishing package: `deliveries/<id>/<platform>/video.mp4`, `cover.png`,
  `publish-copy.md`, release manifest, checksums, and `extras/`
- preview bundle: `work/<id>/previews/episode-preview.mp4` plus sidecars
- review frame: `work/<id>/review/frames/<id>--<milliseconds>ms--<label>.png`
- dense sample: `work/<id>/review/frames/dense-2fps/<id>--<milliseconds>ms--sample.png`

All default paths are derived from the Episode JSON `id`. Adding a new course
number automatically creates a separate `work`, `masters`, `deliveries`, and
`archive` namespace.

Use `scripts/extract_frame.sh` instead of writing one-off frame names. The
`.gdignore` marker prevents Godot from creating `.import` files for generated
PNG, WAV, and MP4 files.

Use `scripts/review_dense.sh <episode.mp4>` for the required 2 fps review. A
120-second episode produces 240 full-resolution samples, one TSV row per
sample, and 10 contact-sheet pages.

Use `scripts/package_episode_release.ps1` after the final render, cover export,
and publishing copy are ready. The package copies canonical inputs instead of
moving them, so rendering and source-document paths remain stable.
