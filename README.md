# myndr-ffmpeg-lgpl

Static, **LGPL-only** `ffmpeg` builds for macOS (arm64 + x86_64), published as
immutable GitHub release assets. Myndr's `scripts/fetch-binaries.sh` pins a
release tag and downloads the per-arch binary at build time.

This repo exists because there is **no upstream prebuilt LGPL ffmpeg for macOS
arm64**: evermeet ships GPL+nonfree (and is non-redistributable due to `faac`),
BtbN has no macOS builds, and the maintained third-party servers offer only
rolling "latest" URLs (the SHA drifts) or stale/shared binaries. Building it
ourselves is the only way to get a versioned, immutable, provably-LGPL binary.

## License posture

ffmpeg is configured `--disable-gpl --disable-nonfree --enable-version3`. The
build **fails** (see `build.sh`'s guard) if either flag ever appears in
`ffmpeg -buildconf`. Concretely:

- **No** x264 / x265 / faac / fdk-aac (those force `--enable-gpl` or
  `--enable-nonfree`).
- **H.264 + H.265 encode** come from Apple **VideoToolbox** (`h264_videotoolbox`,
  `hevc_videotoolbox`) — the OS codec, hardware-accelerated, LGPL-clean.
- **AAC encode** = ffmpeg's native `aac` encoder.
- Extra LGPL/BSD codecs linked statically: libmp3lame (MP3), libopus, libvorbis,
  libvpx (VP8/VP9), libdav1d (AV1 decode). All decoders are native.

Each dependency's license text + ffmpeg's LGPL text ship inside every release
asset under `licenses/`, alongside `BUILDINFO.txt` (the full configure line).
Myndr surfaces these in its third-party-licenses view.

## Releasing a new build

1. Bump `FFMPEG_VERSION` (and any lib version) in `build.sh`.
2. Tag and push: `git tag n7.1.1-1 && git push origin n7.1.1-1`
   (tag = `n<ffmpeg-version>-<build-revision>`).
3. The `build-ffmpeg-lgpl` workflow builds + verifies both arches and creates a
   GitHub release with:
   - `ffmpeg-<ver>-macos-arm64.zip` (+ `.sha256`)
   - `ffmpeg-<ver>-macos-x86_64.zip` (+ `.sha256`)
4. Copy the two SHAs into myndr's `scripts/binaries.sha256` and set the tag
   (see below). PRs build both arches but do **not** release.

## Consuming from myndr

`scripts/binaries.sha256`:

```
ffmpeg.macos.tag      n7.1.1-1
ffmpeg.darwin.arm64   <sha256 of ffmpeg-7.1.1-macos-arm64.zip>
ffmpeg.darwin.amd64   <sha256 of ffmpeg-7.1.1-macos-x86_64.zip>
```

`scripts/fetch-binaries.sh` (darwin branches) builds the URL from the tag:

```
https://github.com/myndrai/myndr-ffmpeg-lgpl/releases/download/${TAG}/ffmpeg-${VER}-macos-${SLICE}.zip
```

where `SLICE` is `arm64` for darwin/arm64 and `x86_64` for darwin/amd64. The
existing `zip:ffmpeg` extractor finds the `ffmpeg` binary inside the zip
unchanged.

## Not built here (yet)

Linux/Windows ffmpeg still come from BtbN's genuine `*-lgpl` artifacts in myndr.
Linux/arm64 has no bundle today; it could be added to this matrix later
(Ubuntu arm64 runner, same `build.sh` with Linux package deps).
