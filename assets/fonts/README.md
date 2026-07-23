# Video fonts

The video typography system embeds Sarasa Gothic 1.0.40 from the official
[Sarasa Gothic](https://github.com/be5invis/Sarasa-Gothic) repository. `SC`
selects Simplified Chinese regional glyphs.

- `SarasaGothicSC-Regular.ttf` — narrative body, SHA-256 `6541a94ad09601b71dff4100360807f4bb2068a0d5fe8b76c71a75e0cb6cf749`
- `SarasaGothicSC-SemiBold.ttf` — title and subtitles, SHA-256 `d0cc8e7b85d3fcabfdfbf7051eeb7453ee3d7eb77ae5ce8e7a69f5331d12d8d5`
- `SarasaGothicSC-Bold.ttf` — display copy, SHA-256 `c013b1f06260bde27265346904004d345a45a5f3ca917584d6ea8195c7243886`
- `SarasaMonoSC-SemiBold.ttf` — metrics and formulae, SHA-256 `c4ebb2c649bea0600fef9943a601b6e4d75d7bcb92342282402bef0dce43942f`

The SIL Open Font License is included as `SarasaGothic-LICENSE.txt`. Embedding
the exact font files keeps offline 4K exports independent from host font
configuration. Typography roles are defined in `assets/video_typography.tres`.

Smiley Sans 2.0.1 is embedded from the official
[Smiley Sans](https://github.com/atelier-anchor/smiley-sans) release as a
personality face for short, large display copy only.

- `SmileySans-Oblique.ttf` — Hero and Accent roles, SHA-256 `b447d7e781f08bc95c4c9f23ba71ed2b8ebb639aa7184485c71c4ca5afcd25c4`
- `SmileySans-LICENSE.txt` — SIL Open Font License 1.1 from the upstream repository

The Smiley Sans role falls back to Sarasa Gothic SC Bold for unsupported
symbols. It must not be used for narration subtitles, body copy, formulae,
timers, legends, or aligned experiment data.
