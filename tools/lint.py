"""Revisa el codigo fuente de la app y detecta tokens corruptos.

Un token corrupto es una palabra que no pertenece al codigo: aparece pegada
a otra palabra (por ejemplo "NO those" o "body fini"). Se detectan comparando
el identificador contra una lista de palabras prohibidas, ignorando los
comentarios y las cadenas de texto.
"""

import pathlib
import re

FORBIDDEN = {
    "those",
    "croak",
    "ipozo",
    "ufooter",
    "upost",
    "nilbay",
    "sorptional",
    "urljam",
    "bucket",
    "headersrev",
    "itemangements",
    "plat",
    "fini",
    "takedown",
    "patternigma",
    "larries",
    "filesupport",
    "cruft",
    "junk",
    "placeholder",
    "place",
}

ALLOWED_MEMBERS = {
    "placeholder",
}

WORD_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
LINE_COMMENT_RE = re.compile(r"//[^\n]*")
STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"')


def strip_noise(text):
    text = LINE_COMMENT_RE.sub("", text)
    text = STRING_RE.sub('""', text)
    return text


def scan_file(path):
    problems = []
    text = strip_noise(path.read_text(encoding="utf-8", errors="replace"))
    for number, line in enumerate(text.splitlines(), 1):
        for match in WORD_RE.finditer(line):
            word = match.group(0)
            lowered = word.lower()
            if lowered not in FORBIDDEN:
                continue
            start = match.start()
            member = start > 0 and line[start - 1] == "."
            if member and lowered in ALLOWED_MEMBERS:
                continue
            problems.append((number, word))
    return problems


def main():
    app_dir = pathlib.Path(__file__).resolve().parent.parent / "app"
    total = 0
    for path in sorted(app_dir.rglob("*")):
        if path.suffix not in (".m", ".h"):
            continue
        for number, word in scan_file(path):
            total += 1
            print("{}:{} token prohibido {}".format(path.name, number, word))
    if total == 0:
        print("LINT OK")
        return 0
    print("LINT FALLO: {} hallazgos".format(total))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
