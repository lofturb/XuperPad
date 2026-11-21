#!/usr/bin/env bash
set -euo pipefail

THEOS="${THEOS:-${GITHUB_WORKSPACE:-$PWD}/theos}"
SDK9="${SDK9:-$THEOS/sdks/iPhoneOS9.3.sdk}"
SDK10="${SDK10:-$THEOS/sdks/iPhoneOS10.3.sdk}"
TOOLCHAIN="${TOOLCHAIN:-$THEOS/toolchain/linux/iphone}"
TARGET="armv7-apple-ios9.0"
MIN_IOS="9.0"
WORK="${WORK:-${RUNNER_TEMP:-/tmp}/xuper-pic}"
PYTHON="${PYTHON:-python3}"

CC="$TOOLCHAIN/bin/clang"
if [ ! -x "$CC" ]; then
  echo "No hay clang en $TOOLCHAIN/bin" >&2
  exit 1
fi

SDK=""
for CANDIDATE in "$SDK9" "$SDK10"; do
  if [ -f "$CANDIDATE/usr/lib/libSystem.tbd" ] && [ -f "$CANDIDATE/usr/lib/crt1.o" ]; then
    SDK="$CANDIDATE"
    break
  fi
done
if [ -z "$SDK" ]; then
  echo "No hay SDK de iOS utilizable" >&2
  exit 1
fi

mkdir -p "$WORK"

cat > "$WORK/prueba.c" <<'EOF'
static int primero = 1;
static int segundo = 2;

const void *const tabla[] = { &primero, &segundo, 0 };

int main(void)
{
    return tabla[0] == 0 ? 1 : 0;
}
EOF

comprobar_pie() {
  "$PYTHON" - "$1" <<'PY'
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
print("1" if flags & 0x200000 else "0")
PY
}

CANDIDATOS=(
  "-fPIC"
  "-fPIE"
  ""
  "-fno-pic"
  "-mdynamic-no-pic"
)

LIBC="-lxuperlibc"
if [ ! -f "$SDK/usr/lib/libxuperlibc.tbd" ]; then
  LIBC="-lSystem"
fi

ELEGIDA=""
for BANDERAS in "${CANDIDATOS[@]}"; do
  ETIQUETA="${BANDERAS:-sin banderas}"
  NOMBRE="$(printf '%s' "$ETIQUETA" | tr -cd '[:alnum:]' | cut -c1-20)"
  [ -n "$NOMBRE" ] || NOMBRE="defecto"
  LOG="$WORK/$NOMBRE.log"
  BINARIO="$WORK/$NOMBRE"
  if ! "$CC" -target "$TARGET" -arch armv7 -isysroot "$SDK" \
    -miphoneos-version-min="$MIN_IOS" $BANDERAS \
    "$WORK/prueba.c" -o "$BINARIO" \
    -L"$SDK/usr/lib" $LIBC -Wl,-dynamic,-search_paths_first > "$LOG" 2>&1; then
    echo "[pic] $ETIQUETA: no compila o no enlaza"
    sed -n '1,6p' "$LOG" | sed 's/^/[pic]   /'
    continue
  fi
  PIE="$(comprobar_pie "$BINARIO")"
  if grep -q "PIE disabled" "$LOG"; then
    echo "[pic] $ETIQUETA: MH_PIE=$PIE con direccionamiento absoluto"
    grep "PIE disabled" "$LOG" | sed 's/^/[pic]   /'
    continue
  fi
  echo "[pic] $ETIQUETA: MH_PIE=$PIE"
  if [ -z "$ELEGIDA" ]; then
    ELEGIDA="$BANDERAS"
  fi
done

if [ -z "$ELEGIDA" ]; then
  echo "BANDERAS_PIC=NINGUNA"
  exit 1
fi

echo "BANDERAS_PIC=$ELEGIDA"
