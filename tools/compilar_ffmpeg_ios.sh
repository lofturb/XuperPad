#!/usr/bin/env bash
# Compila FFmpeg y mbedTLS para armv7/iOS 9 con el toolchain de Theos.
# Deja cabeceras y librerias estaticas en app/vendor/ffmpeg.
set -euo pipefail

FFMPEG_TAG="${FFMPEG_TAG:-n4.4.4}"
MBEDTLS_TAG="${MBEDTLS_TAG:-v2.28.10}"
THEOS="${THEOS:-${GITHUB_WORKSPACE:-$PWD}/theos}"
SDK="${SDK:-$THEOS/sdks/iPhoneOS9.3.sdk}"
TOOLCHAIN="${TOOLCHAIN:-$THEOS/toolchain/linux/iphone}"
OUT="${OUT:-app/vendor/ffmpeg}"
WORK="${WORK:-${RUNNER_TEMP:-/tmp}/xuper-ffmpeg}"
TARGET="armv7-apple-ios9.0"
MIN_IOS="9.0"

log() { printf '[ffmpeg] %s\n' "$*"; }
fail() { printf '[ffmpeg] ERROR: %s\n' "$*" >&2; exit 1; }

case "$OUT" in
  /*) ;;
  *) OUT="$PWD/$OUT" ;;
esac

pick_tool() {
  local tool="$1" candidate
  for candidate in "$TOOLCHAIN/bin/$tool" "$TOOLCHAIN/bin/llvm-$tool"; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

CC="$(pick_tool clang)" || fail "No hay clang en $TOOLCHAIN/bin"
AR="$(pick_tool ar)" || fail "No hay ar en $TOOLCHAIN/bin"
NM="$(pick_tool nm)" || NM=""
RANLIB="$(pick_tool ranlib)" || RANLIB=""
STRIP="$(pick_tool strip)" || STRIP=""

[ -d "$SDK/System/Library/Frameworks" ] || fail "SDK incompleto: $SDK"
[ -f "$SDK/usr/lib/crt1.o" ] || fail "El SDK no trae usr/lib/crt1.o"

log "Toolchain: $CC"
log "SDK: $SDK"
log "FFmpeg: $FFMPEG_TAG, mbedTLS: $MBEDTLS_TAG"

CFLAGS_TARGET="-target $TARGET -arch armv7 -isysroot $SDK -miphoneos-version-min=$MIN_IOS -O2 -fPIC"
LDFLAGS_TARGET="-target $TARGET -arch armv7 -isysroot $SDK -miphoneos-version-min=$MIN_IOS"

mkdir -p "$WORK" "$OUT/lib" "$OUT/include"

clone_tag() {
  local url="$1" tag="$2" dir="$3"
  if [ -d "$dir/.git" ]; then
    log "Se reutiliza $dir"
    return 0
  fi
  rm -rf "$dir"
  git clone --depth 1 --branch "$tag" "$url" "$dir"
}

clone_tag "https://github.com/FFmpeg/FFmpeg.git" "$FFMPEG_TAG" "$WORK/ffmpeg"
clone_tag "https://github.com/Mbed-TLS/mbedtls.git" "$MBEDTLS_TAG" "$WORK/mbedtls"

log "Compilando mbedTLS"
MBED_MAKE_ARGS=(CC="$CC" AR="$AR" CFLAGS="$CFLAGS_TARGET" LDFLAGS="$LDFLAGS_TARGET")
if [ -n "$RANLIB" ]; then
  MBED_MAKE_ARGS+=(RANLIB="$RANLIB")
fi
make -C "$WORK/mbedtls" -j"$(nproc)" "${MBED_MAKE_ARGS[@]}" lib

for lib in libmbedtls libmbedx509 libmbedcrypto; do
  [ -f "$WORK/mbedtls/library/$lib.a" ] || fail "mbedTLS no genero $lib.a"
  cp "$WORK/mbedtls/library/$lib.a" "$OUT/lib/"
done
rm -rf "$OUT/include/mbedtls"
cp -R "$WORK/mbedtls/include/mbedtls" "$OUT/include/"

mkdir -p "$WORK/pkgconfig"
cat > "$WORK/pkgconfig/mbedtls.pc" <<EOF
prefix=$OUT
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: mbedtls
Description: mbed TLS
Version: 2.28.10
Cflags: -I\${includedir} $CFLAGS_TARGET
Libs: -L\${libdir} $LDFLAGS_TARGET -lmbedtls -lmbedx509 -lmbedcrypto
EOF

log "Configurando FFmpeg"
FF_ARGS=(
  --prefix="$OUT"
  --target-os=darwin
  --arch=arm
  --cpu=armv7-a
  --enable-cross-compile
  --cc="$CC"
  --ar="$AR"
  --pkg-config=pkg-config
  --extra-cflags="$CFLAGS_TARGET"
  --extra-ldflags="$LDFLAGS_TARGET"
  --pkg-config-flags=--static
  --enable-static
  --disable-shared
  --disable-asm
  --disable-x86asm
  --disable-debug
  --disable-doc
  --disable-programs
  --disable-securetransport
  --disable-everything
  --enable-avcodec
  --enable-avformat
  --enable-avutil
  --enable-swscale
  --enable-swresample
  --enable-network
  --enable-protocol=file,tcp,tls,http,https
  --enable-demuxer=mpegts
  --enable-decoder=hevc,aac
  --enable-parser=hevc,aac
  --enable-mbedtls
  --enable-version3
)
if [ -n "$NM" ]; then
  FF_ARGS+=(--nm="$NM")
fi
if [ -n "$RANLIB" ]; then
  FF_ARGS+=(--ranlib="$RANLIB")
fi
if [ -n "$STRIP" ]; then
  FF_ARGS+=(--strip="$STRIP")
fi

cd "$WORK/ffmpeg"
PKG_CONFIG_PATH="$WORK/pkgconfig" PKG_CONFIG_LIBDIR="$WORK/pkgconfig" \
  ./configure "${FF_ARGS[@]}"

grep -q '^#define CONFIG_MBEDTLS 1' config.h || fail "FFmpeg no habilito mbedTLS"
grep -q '^#define CONFIG_HTTPS_PROTOCOL 1' config.h || fail "FFmpeg no habilito https"
grep -q '^#define CONFIG_HEVC_DECODER 1' config.h || fail "FFmpeg no habilito el decodificador HEVC"
grep -q '^#define CONFIG_AAC_DECODER 1' config.h || fail "FFmpeg no habilito el decodificador AAC"
grep -q '^#define CONFIG_MPEGTS_DEMUXER 1' config.h || fail "FFmpeg no habilito el demuxer MPEG-TS"

log "Compilando FFmpeg"
make -j"$(nproc)"
make install

for lib in libavcodec libavformat libavutil libswscale libswresample; do
  [ -f "$OUT/lib/$lib.a" ] || fail "FFmpeg no genero $lib.a"
done

log "Probando el enlace estatico"
cat > "$WORK/prueba.c" <<'EOF'
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

int main(void)
{
    return (avcodec_version() > 0 && avformat_version() > 0) ? 0 : 1;
}
EOF
LINK_LIBS=(
  "$OUT/lib/libavformat.a"
  "$OUT/lib/libavcodec.a"
  "$OUT/lib/libswscale.a"
  "$OUT/lib/libswresample.a"
  "$OUT/lib/libavutil.a"
  "$OUT/lib/libmbedtls.a"
  "$OUT/lib/libmbedx509.a"
  "$OUT/lib/libmbedcrypto.a"
)
if ! "$CC" $CFLAGS_TARGET "$WORK/prueba.c" -o "$WORK/prueba" $LDFLAGS_TARGET "${LINK_LIBS[@]}" -lm > "$WORK/link.log" 2>&1; then
  cat "$WORK/link.log" >&2
  if ! "$CC" $CFLAGS_TARGET -fuse-ld="$TOOLCHAIN/bin/ld" "$WORK/prueba.c" -o "$WORK/prueba" $LDFLAGS_TARGET "${LINK_LIBS[@]}" -lm > "$WORK/link.log" 2>&1; then
    cat "$WORK/link.log" >&2
    fail "No se pudo enlazar una prueba contra FFmpeg"
  fi
fi
file "$WORK/prueba"

log "Comprobando simbolos"
require_symbol() {
  local archive="$1" symbol="$2"
  [ -n "$NM" ] || fail "nm no disponible para comprobar $archive"
  "$NM" --defined-only "$archive" 2>/dev/null | grep -q "$symbol" || fail "Falta $symbol en $archive"
}
require_symbol "$OUT/lib/libavcodec.a" "avcodec_find_decoder"
require_symbol "$OUT/lib/libavformat.a" "avformat_open_input"
require_symbol "$OUT/lib/libswscale.a" "sws_scale"
require_symbol "$OUT/lib/libswresample.a" "swr_convert"
require_symbol "$OUT/lib/libmbedtls.a" "mbedtls_ssl_init"

CHECK_DIR="$WORK/check"
rm -rf "$CHECK_DIR"
mkdir -p "$CHECK_DIR"
cd "$CHECK_DIR"
"$AR" x "$OUT/lib/libavcodec.a"
for obj in "$CHECK_DIR"/*.o; do
  file "$obj"
  break
done

cd "$WORK"
log "Listo"
du -sh "$OUT/lib" "$OUT/include"
