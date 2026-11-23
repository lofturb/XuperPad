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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERADOR="$SCRIPT_DIR/generator_libsystem_tbd.py"
PYTHON="${PYTHON:-python3}"
TARGET="armv7-apple-ios9.0"
MIN_IOS="9.0"
LIBC_TBD="libxuperlibc.tbd"
LIBC_FLAG="-lxuperlibc"

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
  "$LIBC_FLAG"
  "-lSystem $LIBC_FLAG"
  "-lobjc -framework Foundation -framework CoreFoundation $LIBC_FLAG"
)

FRAMEWORK_VARIANTS=(
  "-lobjc -framework Foundation -framework UIKit -framework CoreGraphics -framework AVFoundation -framework AVKit $LIBC_FLAG"
)

SDK_USED=""
LD_EXTRA_USED=""
DRIVER_USED=""

STARTUP_OBJECTS=(crt1.o crt1.3.1.o dylib1.o bundle1.o gcrt1.o lazydylib1.o)

complete_startup_objects() {
  local sdk="$1" obj copied=0
  [ -d "$sdk/usr/lib" ] || return 0
  for obj in "${STARTUP_OBJECTS[@]}"; do
    if [ ! -f "$sdk/usr/lib/$obj" ] && [ -f "$SDK9/usr/lib/$obj" ]; then
      cp "$SDK9/usr/lib/$obj" "$sdk/usr/lib/$obj"
      copied=1
    fi
  done
  if [ "$copied" = 1 ]; then
    log "Se completaron los objetos de arranque de $(basename "$sdk") con los del SDK 9.3"
  fi
}

generar_libc_tbd() {
  local sdk="$1" salida="$2"
  "$PYTHON" "$GENERADOR" --sdk "$sdk" --extra-sdk "$3" --output "$salida"
}

complete_startup_objects "$SDK10"
complete_startup_objects "$SDK9"

cat > "$WORK/frameworks.m" <<'EOF'
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

int main(void)
{
    @autoreleasepool {
        NSLog(@"%@ %@ %@ %@", NSStringFromClass([NSObject class]),
              NSStringFromClass([UIView class]),
              NSStringFromClass([AVPlayer class]),
              NSStringFromClass([AVPlayerViewController class]));
    }
    return 0;
}
EOF

for SDK_CANDIDATE in "$SDK9" "$SDK10"; do
  if [ ! -f "$SDK_CANDIDATE/usr/lib/libSystem.tbd" ]; then
    log "El SDK $(basename "$SDK_CANDIDATE") no tiene usr/lib/libSystem.tbd"
    continue
  fi
  if [ ! -f "$SDK_CANDIDATE/usr/lib/crt1.o" ]; then
    log "El SDK $(basename "$SDK_CANDIDATE") no tiene usr/lib/crt1.o"
    continue
  fi

  EXTRA_SDK="$SDK10"
  [ "$SDK_CANDIDATE" = "$SDK10" ] && EXTRA_SDK="$SDK9"
  if ! generar_libc_tbd "$SDK_CANDIDATE" "$SDK_CANDIDATE/usr/lib/$LIBC_TBD" "$EXTRA_SDK"; then
    log "No se pudo preparar la libc de $(basename "$SDK_CANDIDATE")"
    continue
  fi

  LIBC_OK=0
  for DRIVER_CANDIDATE in "$CC" "$CXX"; do
    [ -n "$DRIVER_CANDIDATE" ] || continue
    for LD_EXTRA in "${LINK_VARIANTS[@]}"; do
      log "Probando $DRIVER_CANDIDATE con $(basename "$SDK_CANDIDATE") y [$LD_EXTRA]"
      if "$DRIVER_CANDIDATE" -target "$TARGET" -arch armv7 -isysroot "$SDK_CANDIDATE" \
        -miphoneos-version-min="$MIN_IOS" $LD_EXTRA -Wl,-dynamic,-search_paths_first \
        "$WORK/probe.c" -o "$WORK/probe" > "$WORK/probe.log" 2>&1; then
        LIBC_OK=1
        DRIVER_USED="$DRIVER_CANDIDATE"
        break 2
      fi
      log "El enlace con [$(basename "$SDK_CANDIDATE")][$LD_EXTRA] fallo"
      cat "$WORK/probe.log" >&2 || true
    done
  done

  if [ "$LIBC_OK" != 1 ]; then
    log "El SDK $(basename "$SDK_CANDIDATE") no resuelve la libc de armv7"
    continue
  fi

  FRAMEWORKS_OK=0
  for LD_EXTRA in "${FRAMEWORK_VARIANTS[@]}"; do
    log "Probando los frameworks de $(basename "$SDK_CANDIDATE") con [$LD_EXTRA]"
    if "$DRIVER_USED" -target "$TARGET" -arch armv7 -isysroot "$SDK_CANDIDATE" \
      -miphoneos-version-min="$MIN_IOS" -fobjc-arc -x objective-c \
      $LD_EXTRA -Wl,-dynamic,-search_paths_first \
      "$WORK/frameworks.m" -o "$WORK/frameworks" > "$WORK/frameworks.log" 2>&1; then
      FRAMEWORKS_OK=1
      LD_EXTRA_USED="$LD_EXTRA"
      break
    fi
    log "Los frameworks de $(basename "$SDK_CANDIDATE") no se enlazan"
    cat "$WORK/frameworks.log" >&2 || true
  done

  if [ "$FRAMEWORKS_OK" != 1 ]; then
    log "El SDK $(basename "$SDK_CANDIDATE") no enlaza los frameworks de iOS"
    continue
  fi

  SDK_USED="$SDK_CANDIDATE"
  break
done

[ -n "$SDK_USED" ] || fail "Ningun SDK resuelve la libc y los frameworks de armv7"

log "Enlace valido con $DRIVER_USED, $(basename "$SDK_USED") y [$LD_EXTRA_USED]"

for FRAMEWORK in Foundation UIKit CoreGraphics AVFoundation AVKit; do
  if [ ! -d "$SDK_USED/System/Library/Frameworks/$FRAMEWORK.framework" ]; then
    log "AVISO: el SDK elegido no trae $FRAMEWORK.framework"
  fi
done

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

PIC_RESULT="$(SDK9="$SDK9" SDK10="$SDK10" TOOLCHAIN="$TOOLCHAIN" WORK="$WORK/pic" bash "$SCRIPT_DIR/diagnostico_pic.sh" 2>&1)" || {
  printf '%s\n' "$PIC_RESULT" >&2
  fail "El diagnostico de PIE fallo"
}
printf '%s\n' "$PIC_RESULT"
PIC_FLAGS="$(printf '%s\n' "$PIC_RESULT" | sed -n 's/^BANDERAS_PIC=//p' | tail -n 1)"
case "$PIC_FLAGS" in
  ""|NINGUNA) fail "Ninguna bandera produce objetos armv7 compatibles con PIE" ;;
esac
log "Banderas PIE para armv7: $PIC_FLAGS"
printf 'XUPER_PIC_FLAGS := %s\n' "$PIC_FLAGS" > "$OUT/picflags.mk"

CFLAGS_TARGET="-target $TARGET -arch armv7 -isysroot $SDK_USED -miphoneos-version-min=$MIN_IOS -O3 $PIC_FLAGS -fno-optimize-sibling-calls"
LDFLAGS_TARGET="-target $TARGET -arch armv7 -isysroot $SDK_USED -miphoneos-version-min=$MIN_IOS"
CFLAGS_FFMPEG="$CFLAGS_TARGET -mfpu=neon -I$OUT/include"
LDFLAGS_FFMPEG="$LDFLAGS_TARGET -L$OUT/lib $LIBC_FLAG"

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

log "Aplicando optimizacion: omitir boundary strengths cuando se salta el deblocking"
HEVCDEC="$WORK/ffmpeg/libavcodec/hevcdec.c"
perl -0pi -e 's/if \(!s->sh\.disable_deblocking_filter_flag\)/if (!s->sh.disable_deblocking_filter_flag \&\& s->avctx->skip_loop_filter < AVDISCARD_ALL)/g' "$HEVCDEC"
BS_GUARDS="$(grep -c 'skip_loop_filter < AVDISCARD_ALL' "$HEVCDEC" || true)"
[ "$BS_GUARDS" = 4 ] || fail "El parche de boundary strengths aplico $BS_GUARDS de 4 sitios"
log "Parche aplicado en $BS_GUARDS sitios"

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
  --enable-pic
  --enable-neon
  --disable-debug
  --disable-doc
  --disable-programs
  --disable-securetransport
  --disable-everything
  --disable-videotoolbox
  --disable-audiotoolbox
  --disable-iconv
  --disable-zlib
  --enable-avcodec
  --enable-avformat
  --enable-avutil
  --enable-swscale
  --enable-swresample
  --enable-network
  --enable-protocol=file,tcp,tls,http,https
  --enable-demuxer=mpegts
  --enable-decoder=hevc,aac,dvbsub
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

LD_FLAGS="$LDFLAGS_FFMPEG"
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
#include <mbedtls/ssl.h>

__typeof__(&avformat_open_input) abrir = &avformat_open_input;
__typeof__(&sws_scale) escalar = &sws_scale;
__typeof__(&swr_convert) convertir = &swr_convert;

int main(void)
{
    const AVCodec *codec = avcodec_find_decoder(AV_CODEC_ID_HEVC);
    AVFormatContext *formato = avformat_alloc_context();
    mbedtls_ssl_context ssl;

    mbedtls_ssl_init(&ssl);
    mbedtls_ssl_free(&ssl);
    avformat_free_context(formato);

    return (codec != NULL && formato != NULL && abrir != NULL && escalar != NULL && convertir != NULL) ? 0 : 1;
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
if ! "$CC" $CFLAGS_FFMPEG $LD_FLAGS "$WORK/prueba.c" -o "$WORK/prueba" "${LINK_LIBS[@]}" -lm > "$WORK/link.log" 2>&1; then
  cat "$WORK/link.log" >&2
  fail "No se pudo enlazar una prueba contra FFmpeg"
fi
if grep -q "PIE disabled" "$WORK/link.log"; then
  grep "PIE disabled" "$WORK/link.log" >&2
  fail "Las librerias de FFmpeg usan direccionamiento absoluto y no permiten PIE"
fi
if ! "$PYTHON" - "$WORK/prueba" <<'PY'
import struct
import sys

data = open(sys.argv[1], "rb").read()
magic = data[:4]
if magic == b"\xce\xfa\xed\xfe":
    endian = "<"
elif magic == b"\xfe\xed\xfa\xce":
    endian = ">"
else:
    raise SystemExit("Mach-O no reconocido")
cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags = struct.unpack(
    endian + "6I", data[4:28]
)
if not flags & 0x200000:
    raise SystemExit("El binario de prueba no tiene MH_PIE")
print("Prueba de FFmpeg con MH_PIE")
PY
then
  fail "El binario de prueba contra FFmpeg no es PIE"
fi
file "$WORK/prueba"

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
