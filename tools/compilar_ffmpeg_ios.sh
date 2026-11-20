#!/usr/bin/env bash
# Compila FFmpeg y mbedTLS para armv7/iOS 9 con el toolchain de Theos.
# Deja cabeceras y librerias estaticas en app/vendor/ffmpeg.
set -euo pipefail

FFMPEG_TAG="${FFMPEG_TAG:-n4.4.4}"
MBEDTLS_TAG="${MBEDTLS_TAG:-v2.28.10}"
THEOS="${THEOS:-${GITHUB_WORKSPACE:-$PWD}/theos}"
SDK9="${SDK9:-$THEOS/sdks/iPhoneOS9.3.sdk}"
SDK10="${SDK10:-$THEOS/sdks/iPhoneOS10.3.sdk}"
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
CXX="$(pick_tool clang++)" || CXX=""
AR="$(pick_tool ar)" || fail "No hay ar en $TOOLCHAIN/bin"
NM="$(pick_tool nm)" || NM=""
RANLIB="$(pick_tool ranlib)" || RANLIB=""
STRIP="$(pick_tool strip)" || STRIP=""

log "Toolchain: $CC"
log "FFmpeg: $FFMPEG_TAG, mbedTLS: $MBEDTLS_TAG"

mkdir -p "$WORK" "$OUT/lib" "$OUT/include"

cat > "$WORK/probe.c" <<'EOF'
#include <string.h>

static volatile unsigned long TAMANO = 16;
static volatile int OBJETIVO = 1;

int main(void)
{
    static volatile char origen[32] = { 1, 2, 3, 4 };
    char destino[32];
    unsigned long n = TAMANO;
    int objetivo = OBJETIVO;

    memcpy(destino, (const void *)origen, n);
    memmove(destino + 1, destino, n - 1);
    if (memcmp(destino, (const void *)origen, n) != 0) {
        return 1;
    }
    if (memchr(destino, objetivo, n) == NULL) {
        return 2;
    }
    memset(destino, 0, n);
    if (strcmp(destino, (const char *)origen) == 0) {
        return 3;
    }
    if (strncmp(destino, (const char *)origen, n) == 0) {
        return 4;
    }
    if (strchr(destino, objetivo) == NULL) {
        return 5;
    }
    return 0;
}
EOF

LINK_VARIANTS=(
  ""
  "-lSystem"
  "-lobjc -framework Foundation -framework CoreFoundation"
)

SDK_USED=""
LD_EXTRA_USED=""
DRIVER_USED=""
for SDK_CANDIDATE in "$SDK10" "$SDK9"; do
  if [ ! -f "$SDK_CANDIDATE/usr/lib/crt1.o" ] || [ ! -f "$SDK_CANDIDATE/usr/lib/libSystem.tbd" ]; then
    log "El SDK $(basename "$SDK_CANDIDATE") no tiene crt1.o o libSystem.tbd"
    continue
  fi
  for DRIVER_CANDIDATE in "$CC" "$CXX"; do
    [ -n "$DRIVER_CANDIDATE" ] || continue
    for LD_EXTRA in "${LINK_VARIANTS[@]}"; do
      log "Probando $DRIVER_CANDIDATE con $(basename "$SDK_CANDIDATE") y [$LD_EXTRA]"
      if "$DRIVER_CANDIDATE" -target "$TARGET" -arch armv7 -isysroot "$SDK_CANDIDATE" \
        -miphoneos-version-min="$MIN_IOS" $LD_EXTRA -Wl,-dynamic,-search_paths_first \
        "$WORK/probe.c" -o "$WORK/probe" > "$WORK/probe.log" 2>&1; then
        SDK_USED="$SDK_CANDIDATE"
        LD_EXTRA_USED="$LD_EXTRA"
        DRIVER_USED="$DRIVER_CANDIDATE"
        break 3
      fi
      tail -n 6 "$WORK/probe.log" >&2 || true
    done
  done
done

[ -n "$SDK_USED" ] || fail "Ninguna variante de enlace resuelve la libc de armv7"

log "Enlace valido con $DRIVER_USED, $(basename "$SDK_USED") y [$LD_EXTRA_USED]"

if [ "$DRIVER_USED" != "$CC" ]; then
  CLANG_BIN="$CC"
  WRAPPER="$WORK/cc-wrap"
  cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  if [ "\$arg" = "-c" ]; then
    exec "$CLANG_BIN" "\$@"
  fi
done
exec "$DRIVER_USED" "\$@"
EOF
  chmod +x "$WRAPPER"
  CC="$WRAPPER"
  log "Se usa un envoltorio que compila con clang y enlaza con $DRIVER_USED"
fi

CFLAGS_TARGET="-target $TARGET -arch armv7 -isysroot $SDK_USED -miphoneos-version-min=$MIN_IOS -O2 -fPIC"
LDFLAGS_TARGET="-target $TARGET -arch armv7 -isysroot $SDK_USED -miphoneos-version-min=$MIN_IOS"
CFLAGS_FFMPEG="$CFLAGS_TARGET -I$OUT/include"
LDFLAGS_FFMPEG="$LDFLAGS_TARGET -L$OUT/lib"

SDK_VERSION="$(basename "$SDK_USED" .sdk)"
SDK_VERSION="${SDK_VERSION#iPhoneOS}"
printf 'XUPER_FFMPEG_SDK_VERSION := %s\n' "$SDK_VERSION" > "$OUT/ldconfig.mk"
log "SDK elegido para enlazar: $SDK_VERSION"

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

log "pkg-config detecta mbedTLS en $WORK/pkgconfig"
PKG_CONFIG_PATH="$WORK/pkgconfig" PKG_CONFIG_LIBDIR="$WORK/pkgconfig" \
  pkg-config --cflags --libs mbedtls || fail "el archivo mbedtls.pc no es valido"

cd "$WORK/ffmpeg"
FF_ARGS=(
  --prefix="$OUT"
  --target-os=darwin
  --arch=arm
  --cpu=armv7-a
  --enable-cross-compile
  --cc="$CC"
  --ar="$AR"
  --pkg-config=pkg-config
  --extra-cflags="$CFLAGS_FFMPEG"
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

LD_FLAGS="$LDFLAGS_FFMPEG $LD_EXTRA_USED"
log "Configurando FFmpeg con $LD_FLAGS"
if ! PKG_CONFIG_PATH="$WORK/pkgconfig" PKG_CONFIG_LIBDIR="$WORK/pkgconfig" \
  ./configure "${FF_ARGS[@]}" --extra-ldflags="$LD_FLAGS"; then
  log "Ultimas lineas de ffbuild/config.log"
  tail -n 80 ffbuild/config.log >&2 || true
  fail "FFmpeg no se pudo configurar"
fi

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
if ! "$CC" $CFLAGS_TARGET $LD_FLAGS "$WORK/prueba.c" -o "$WORK/prueba" "${LINK_LIBS[@]}" -lm > "$WORK/link.log" 2>&1; then
  cat "$WORK/link.log" >&2
  fail "No se pudo enlazar una prueba contra FFmpeg"
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
