"""Genera un tbd con los simbolos de la libc que el SDK no entrega al enlazador.

Los SDK parcheados de Theos exponen la libc mediante re-exportaciones que el
enlazador del toolchain no resuelve, por lo que funciones como strcmp o strncmp
no se pueden enlazar. Este script reconstruye esas re-exportaciones como un tbd
con los simbolos directamente y la misma instalacion que libSystem.
"""

import argparse
import pathlib
import re

OMITIR = {
    "libunwind",
    "libcompiler_rt",
    "libdispatch",
    "libcommonCrypto",
    "libcorecrypto",
    "libdyld",
    "libmacho",
    "liblaunch",
    "libkeymgr",
    "libcache",
    "libcopyfile",
    "libremovefile",
    "libvminterpose",
    "libxpc",
}

PREFIJOS = ("libsystem_",)

SIMBOLOS_ESSENCIALES = (
    "_memcpy",
    "_memmove",
    "_memset",
    "_memcmp",
    "_memchr",
    "_strcmp",
    "_strncmp",
    "_strcpy",
    "_strchr",
    "_strlen",
    "_malloc",
    "_free",
    "_socket",
    "_connect",
    "_getaddrinfo",
)

SIMBOLOS_ESPECIALES = {
    "dyld_stub_binder",
    "___mh_execute_header",
    "___mh_dylib_header",
    "___mh_bundle_header",
}

SEPARADOR_ENTRADA = re.compile(r"(?m)^[ \t]*-[ \t]+")


def leer_texto(ruta):
    return ruta.read_text(encoding="utf-8", errors="replace")


def extraer_lista(texto, clave):
    posicion = texto.find(clave)
    if posicion < 0:
        return []
    inicio = texto.find("[", posicion)
    if inicio < 0:
        return []
    fin = texto.find("]", inicio)
    if fin < 0:
        return []
    cuerpo = texto[inicio + 1 : fin]
    return [elemento.strip() for elemento in cuerpo.split(",") if elemento.strip()]


def entradas_de_exports(texto):
    posicion = texto.find("exports:")
    if posicion < 0:
        return []
    cuerpo = texto[posicion + len("exports:") :]
    partes = SEPARADOR_ENTRADA.split(cuerpo)
    return [parte for parte in partes if parte.strip()]


def valor_simple(texto, clave, defecto):
    posicion = texto.find(clave)
    if posicion < 0:
        return defecto
    linea = texto[posicion:].splitlines()[0]
    _, _, valor = linea.partition(":")
    return valor.strip() or defecto


def rutas_de_reexport(entrada):
    for clave in ("re-exports:", "reexported-libraries:"):
        rutas = extraer_lista(entrada, clave)
        if rutas:
            return rutas
    return []


def recoger_simbolos(texto, por_arquitectura):
    for entrada in entradas_de_exports(texto):
        simbolos = extraer_lista(entrada, "symbols:")
        if not simbolos:
            continue
        for arquitectura in extraer_lista(entrada, "archs:"):
            por_arquitectura.setdefault(arquitectura, set()).update(simbolos)


def buscar_libsystem(usr_lib):
    for nombre in ("libSystem.tbd", "libSystem.B.tbd"):
        ruta = usr_lib / nombre
        if ruta.is_file():
            return ruta
    return None


def simbolos_de_sdk(sdk):
    usr_lib = sdk / "usr" / "lib"
    sistema = usr_lib / "system"
    por_arquitectura = {}
    if not sistema.is_dir():
        return por_arquitectura
    for origen in sorted(sistema.glob("*.tbd")):
        nombre = origen.stem
        if nombre in OMITIR:
            continue
        if not nombre.startswith(PREFIJOS):
            continue
        recoger_simbolos(leer_texto(origen), por_arquitectura)
    return por_arquitectura


def escribir_tbd(
    salida,
    instalacion,
    plataforma,
    version,
    compatibilidad,
    arquitecturas,
    por_arquitectura,
):
    lineas = ["---"]
    lineas.append("archs:                 [ {} ]".format(", ".join(arquitecturas)))
    lineas.append("platform:              {}".format(plataforma))
    lineas.append("install-name:          {}".format(instalacion))
    if version:
        lineas.append("current-version:       {}".format(version))
    lineas.append("compatibility-version: {}".format(compatibilidad))
    lineas.append("exports:")
    for arquitectura in sorted(por_arquitectura):
        simbolos = sorted(por_arquitectura[arquitectura])
        if not simbolos:
            continue
        trozos = []
        for indice in range(0, len(simbolos), 8):
            trozos.append(", ".join(simbolos[indice : indice + 8]))
        cuerpo = (",\n" + " " * 26).join(trozos)
        lineas.append("  - archs:              [ {} ]".format(arquitectura))
        lineas.append("    symbols:            [ {} ]".format(cuerpo))
    salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text("\n".join(lineas) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--extra-sdk")
    argumentos = parser.parse_args()

    sdk = pathlib.Path(argumentos.sdk)
    usr_lib = sdk / "usr" / "lib"
    principal = buscar_libsystem(usr_lib)
    if principal is None:
        raise SystemExit("No se encontro libSystem.tbd en {}".format(usr_lib))

    texto = leer_texto(principal)
    instalacion = valor_simple(texto, "install-name:", "/usr/lib/libSystem.B.dylib")
    plataforma = valor_simple(texto, "platform:", "ios")
    version = valor_simple(texto, "current-version:", "")
    compatibilidad = valor_simple(texto, "compatibility-version:", "1")

    por_arquitectura = {}
    for origen_sdk in [sdk] + (
        [pathlib.Path(argumentos.extra_sdk)] if argumentos.extra_sdk else []
    ):
        for arquitectura, simbolos in simbolos_de_sdk(origen_sdk).items():
            destino = por_arquitectura.setdefault(arquitectura, set())
            destino.update(
                simbolo for simbolo in simbolos if simbolo not in SIMBOLOS_ESPECIALES
            )

    if not por_arquitectura:
        raise SystemExit("No se reunieron simbolos de la libc en {}".format(sdk))

    faltantes = [
        simbolo
        for simbolo in SIMBOLOS_ESSENCIALES
        if not any(simbolo in simbolos for simbolos in por_arquitectura.values())
    ]
    if faltantes:
        raise SystemExit(
            "Faltan simbolos esenciales de la libc: {}".format(", ".join(faltantes))
        )

    arquitecturas = sorted(por_arquitectura)
    salida = pathlib.Path(argumentos.output)
    escribir_tbd(
        salida,
        instalacion,
        plataforma,
        version,
        compatibilidad,
        arquitecturas,
        por_arquitectura,
    )

    total = sum(len(simbolos) for simbolos in por_arquitectura.values())
    print(
        "tbd de {} con {} simbolos en {} arquitecturas".format(
            salida.name, total, len(arquitecturas)
        )
    )
    for arquitectura in arquitecturas:
        print(
            "  {}: {} simbolos".format(
                arquitectura, len(por_arquitectura[arquitectura])
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
