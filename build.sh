#!/usr/bin/env bash
# build.sh — compile a static, LGPL-only ffmpeg for ONE macOS arch.
#
#   ./build.sh <arm64|x86_64>
#
# Runs natively on a matching GitHub runner (macos-14 = arm64,
# macos-13 = x86_64), so host arch == target arch and no meson/autotools
# cross files are needed. Output: dist-<arch>/{ffmpeg,licenses/,BUILDINFO.txt}.
#
# License posture: NO --enable-gpl, NO --enable-nonfree. H.264/H.265 ENCODE
# comes from Apple VideoToolbox (OS codec, LGPL-clean, no x264/x265). AAC
# encode is ffmpeg's native encoder. Everything decodes natively. A
# post-build guard greps `-buildconf` and FAILS if gpl/nonfree ever appear.
set -euo pipefail

ARCH="${1:?usage: build.sh <arm64|x86_64>}"
case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "build.sh: bad arch '$ARCH' (want arm64|x86_64)" >&2; exit 1 ;;
esac

# --- pinned versions (bump deliberately; mirror FFMPEG_VERSION in the git tag) ---
FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"
OGG_VERSION=1.3.5
VORBIS_VERSION=1.3.7
LAME_VERSION=3.100
OPUS_VERSION=1.5.2
VPX_VERSION=1.14.1
DAV1D_VERSION=1.4.3

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/work-$ARCH"
PREFIX="$WORK/prefix"
SRC="$WORK/src"
DIST="$ROOT/dist-$ARCH"
rm -rf "$WORK" "$DIST"
mkdir -p "$PREFIX/lib/pkgconfig" "$SRC" "$DIST/licenses"

export MACOSX_DEPLOYMENT_TARGET=11.0
export CFLAGS="-arch $ARCH -mmacosx-version-min=11.0 -O2 -fPIC"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch $ARCH -mmacosx-version-min=11.0"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
# GNU config.sub does not recognise Apple's "arm64" spelling; use the canonical
# "aarch64". Autotools libs get --build==--host=<this> so they configure as a
# native build (build==host, not cross) with a triple config.sub accepts.
case "$ARCH" in
  arm64)  GNU_TRIPLE="aarch64-apple-darwin" ;;
  x86_64) GNU_TRIPLE="x86_64-apple-darwin" ;;
esac
NPROC="$(sysctl -n hw.ncpu)"

fetch() { # <url> <outfile>
  echo "==> fetch $1"
  curl -fL --retry 3 --retry-delay 2 -o "$2" "$1"
}

# ---------------------------------------------------------------- libogg
cd "$SRC"
fetch "https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.gz" ogg.tgz
tar xf ogg.tgz && cd "libogg-$OGG_VERSION"
./configure --build="$GNU_TRIPLE" --host="$GNU_TRIPLE" --prefix="$PREFIX" --enable-static --disable-shared
make -j"$NPROC"
make install
cp COPYING "$DIST/licenses/libogg.LICENSE"

# -------------------------------------------------------------- libvorbis
cd "$SRC"
fetch "https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.gz" vorbis.tgz
tar xf vorbis.tgz && cd "libvorbis-$VORBIS_VERSION"
# Modern Apple ld rejects libvorbis 1.3.7's Darwin-only -force_cpusubtype_ALL
# linker flag ("ld: unknown options: -force_cpusubtype_ALL"); strip it.
sed -i.bak 's/-force_cpusubtype_ALL//g' configure
./configure --build="$GNU_TRIPLE" --host="$GNU_TRIPLE" --prefix="$PREFIX" --enable-static --disable-shared \
  --with-ogg="$PREFIX"
make -j"$NPROC"
make install
cp COPYING "$DIST/licenses/libvorbis.LICENSE"

# ------------------------------------------------------------- libmp3lame
cd "$SRC"
fetch "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" lame.tgz
tar xf lame.tgz && cd "lame-$LAME_VERSION"
# lame's bundled config.guess predates Apple Silicon; --host pins the triple.
./configure --build="$GNU_TRIPLE" --host="$GNU_TRIPLE" --prefix="$PREFIX" --enable-static --disable-shared \
  --disable-frontend
make -j"$NPROC"
make install
cp COPYING "$DIST/licenses/libmp3lame.LICENSE"

# ----------------------------------------------------------------- libopus
cd "$SRC"
fetch "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" opus.tgz
tar xf opus.tgz && cd "opus-$OPUS_VERSION"
./configure --build="$GNU_TRIPLE" --host="$GNU_TRIPLE" --prefix="$PREFIX" --enable-static --disable-shared
make -j"$NPROC"
make install
cp COPYING "$DIST/licenses/libopus.LICENSE"

# ------------------------------------------------------------------ libvpx
cd "$SRC"
fetch "https://github.com/webmproject/libvpx/archive/refs/tags/v$VPX_VERSION.tar.gz" vpx.tgz
tar xf vpx.tgz && cd "libvpx-$VPX_VERSION"
./configure --prefix="$PREFIX" --enable-static --disable-shared --enable-pic \
  --enable-vp8 --enable-vp9 \
  --disable-examples --disable-tools --disable-docs --disable-unit-tests \
  --extra-cflags="-mmacosx-version-min=11.0"
make -j"$NPROC"
make install
cp LICENSE "$DIST/licenses/libvpx.LICENSE"

# ------------------------------------------------------------------- dav1d
cd "$SRC"
fetch "https://code.videolan.org/videolan/dav1d/-/archive/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.gz" dav1d.tgz
tar xf dav1d.tgz && cd "dav1d-$DAV1D_VERSION"
meson setup builddir --prefix="$PREFIX" --buildtype=release \
  --default-library=static -Denable_tools=false -Denable_tests=false \
  -Dc_args="-arch $ARCH -mmacosx-version-min=11.0" \
  -Dc_link_args="-arch $ARCH -mmacosx-version-min=11.0"
ninja -C builddir
ninja -C builddir install
cp COPYING "$DIST/licenses/libdav1d.LICENSE"

# ------------------------------------------------------------------ ffmpeg
cd "$SRC"
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" ffmpeg.txz
tar xf ffmpeg.txz && cd "ffmpeg-$FFMPEG_VERSION"
./configure \
  --prefix="$PREFIX" \
  --arch="$ARCH" \
  --disable-gpl --disable-nonfree --enable-version3 \
  --enable-static --disable-shared --enable-pic \
  --disable-doc --disable-debug --disable-ffplay \
  --enable-videotoolbox --enable-audiotoolbox \
  --enable-libmp3lame --enable-libopus --enable-libvorbis \
  --enable-libvpx --enable-libdav1d \
  --pkg-config-flags=--static \
  --extra-cflags="-I$PREFIX/include" \
  --extra-ldflags="-L$PREFIX/lib"
make -j"$NPROC"
cp ffmpeg "$DIST/ffmpeg"
cp COPYING.LGPLv2.1 COPYING.LGPLv3 LICENSE.md "$DIST/licenses/" 2>/dev/null || true

# ----------------------------------------------------- LGPL-compliance guard
# This is the load-bearing check: prove the binary is genuinely LGPL and the
# right arch before it can ever be released. Fails the build otherwise.
"$DIST/ffmpeg" -version | head -n 3
BUILDCONF="$("$DIST/ffmpeg" -buildconf)"
if grep -qi -- '--enable-gpl' <<<"$BUILDCONF"; then
  echo "FATAL: ffmpeg built with --enable-gpl (must be LGPL)" >&2; exit 1
fi
if grep -qi -- '--enable-nonfree' <<<"$BUILDCONF"; then
  echo "FATAL: ffmpeg built with --enable-nonfree (non-redistributable)" >&2; exit 1
fi
if ! lipo -archs "$DIST/ffmpeg" | tr ' ' '\n' | grep -qx "$ARCH"; then
  echo "FATAL: ffmpeg is not $ARCH (got: $(lipo -archs "$DIST/ffmpeg"))" >&2; exit 1
fi

{
  echo "ffmpeg $FFMPEG_VERSION — macOS $ARCH — static, LGPL (--disable-gpl --disable-nonfree)"
  echo
  echo "$BUILDCONF"
} > "$DIST/BUILDINFO.txt"

echo "build.sh: OK -> $DIST/ffmpeg ($ARCH, LGPL)"
