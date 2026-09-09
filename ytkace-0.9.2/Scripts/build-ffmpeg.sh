#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THEOS="${THEOS:-$HOME/theos}"
SDK="${SDK:-$THEOS/sdks/iPhoneOS16.5.sdk}"
TOOLCHAIN="$THEOS/toolchain/linux/iphone/bin"
VERSION="${FFMPEG_VERSION:-8.1.2}"
BUILD="$ROOT/.build/ffmpeg"
SOURCE="$BUILD/ffmpeg-$VERSION"
OUTPUT="$ROOT/Vendor/FFmpeg"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)}"

mkdir -p "$BUILD" "$OUTPUT/lib"
if [[ ! -f "$BUILD/ffmpeg-$VERSION.tar.xz" ]]; then
    curl -L --fail "https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz" \
        -o "$BUILD/ffmpeg-$VERSION.tar.xz"
fi
if [[ ! -d "$SOURCE" ]]; then
    tar -xf "$BUILD/ffmpeg-$VERSION.tar.xz" -C "$BUILD"
fi

build_arch() {
    local arch="$1"
    local target="$2"
    local directory="$BUILD/build-$arch"
    local prefix="$BUILD/install-$arch"
    rm -rf "$directory" "$prefix"
    mkdir -p "$directory" "$prefix"
    cd "$directory"
    "$SOURCE/configure" \
        --prefix="$prefix" \
        --target-os=darwin \
        --arch=aarch64 \
        --enable-cross-compile \
        --sysroot="$SDK" \
        --cc="$TOOLCHAIN/clang" \
        --cxx="$TOOLCHAIN/clang++" \
        --ar="$TOOLCHAIN/ar" \
        --ranlib="$TOOLCHAIN/ranlib" \
        --nm="$TOOLCHAIN/nm" \
        --strip="$TOOLCHAIN/strip" \
        --extra-cflags="-target $target -miphoneos-version-min=16.0 -fPIC -fvisibility=hidden" \
        --extra-cxxflags="-target $target -miphoneos-version-min=16.0 -fPIC -fvisibility=hidden" \
        --extra-ldflags="-target $target -miphoneos-version-min=16.0" \
        --enable-static \
        --disable-shared \
        --enable-pic \
        --enable-small \
        --disable-asm \
        --disable-programs \
        --disable-doc \
        --disable-debug \
        --disable-autodetect \
        --disable-network \
        --disable-everything \
        --enable-avutil \
        --enable-avcodec \
        --enable-avformat \
        --disable-avdevice \
        --disable-avfilter \
        --disable-swscale \
        --disable-swresample \
        --enable-protocol=file \
        --enable-demuxer=mov \
        --enable-muxer=mp4 \
        --enable-bsf=aac_adtstoasc \
        --disable-iconv \
        --disable-zlib \
        --disable-bzlib \
        --disable-lzma \
        --disable-securetransport \
        --disable-videotoolbox \
        --disable-audiotoolbox \
        --disable-avfoundation
    make -j"$JOBS"
    make install
}

build_arch arm64 arm64-apple-ios16.0

rm -rf "$OUTPUT/include"
cp -R "$BUILD/install-arm64/include" "$OUTPUT/include"
for library in avformat avcodec avutil; do
    cp "$BUILD/install-arm64/lib/lib$library.a" "$OUTPUT/lib/lib$library.a"
done
cp "$SOURCE/COPYING.LGPLv2.1" "$OUTPUT/COPYING.LGPLv2.1"
cp "$SOURCE/COPYING.LGPLv3" "$OUTPUT/COPYING.LGPLv3"
