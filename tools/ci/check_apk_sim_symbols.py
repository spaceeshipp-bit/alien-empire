#!/usr/bin/env python3
"""Checks the sim library in an APK will load on a phone.

Android refuses to load a library that imports a symbol nothing provides,
and the phone is the first place that would show it. This finds every symbol
the APK's sim library imports and checks it is defined by the APK's own C++
runtime (lib/arm64-v8a/libc++_shared.so, which Godot ships) or by Android's
libc, libm or libdl for the app's minimum API level (the NDK's stub libraries).
Weak imports may stay unresolved, as Android's loader allows.

  tools/ci/check_apk_sim_symbols.py build/android/aetd-m0-debug.apk \\
      "$ANDROID_HOME/ndk/<version>" 24

Needs `readelf` (GNU binutils), which reads arm64 libraries on any host.
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ABI = "arm64-v8a"
RUNTIME = f"lib/{ABI}/libc++_shared.so"
SIM_PREFIX = f"lib/{ABI}/libaetd_sim."
SYSTEM_LIBS = ("libc.so", "libm.so", "libdl.so")
# A --dyn-syms row: Num: Value Size Type Bind Vis Ndx Name[@version]
ROW = re.compile(r"^\s*\d+:\s+[0-9a-f]+\s+\d+\s+(\w+)\s+(\w+)\s+\w+\s+(\S+)\s+(\S+)")


def dynamic_symbols(library: Path) -> tuple[set[str], set[str], set[str]]:
    """(defined, strong imports, weak imports), without version suffixes."""
    out = subprocess.run(["readelf", "--dyn-syms", "-W", str(library)], check=True,
                         capture_output=True, text=True).stdout
    defined, strong, weak = set(), set(), set()
    for line in out.splitlines():
        m = ROW.match(line)
        if not m:
            continue
        kind, bind, ndx, name = m.groups()
        name = name.split("@")[0]
        if not name or kind == "SECTION":
            continue
        if ndx == "UND":
            (weak if bind == "WEAK" else strong).add(name)
        else:
            defined.add(name)
    return defined, strong, weak


def missing_imports(sim: Path, providers: list[Path]) -> list[str]:
    _, strong, _ = dynamic_symbols(sim)
    available: set[str] = set()
    for provider in providers:
        available |= dynamic_symbols(provider)[0]
    return sorted(strong - available)


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    apk, ndk, api = Path(argv[0]), Path(argv[1]), argv[2]
    stubs = ndk / "toolchains" / "llvm" / "prebuilt" / "linux-x86_64" / "sysroot" / "usr" / "lib" / "aarch64-linux-android" / api
    system = [stubs / name for name in SYSTEM_LIBS]
    for path in system:
        if not path.exists():
            print(f"error: no {path}: is the NDK installed?", file=sys.stderr)
            return 2
    with tempfile.TemporaryDirectory() as tmp, zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        sims = [n for n in names if n.startswith(SIM_PREFIX) and n.endswith(".so")]
        if RUNTIME not in names or not sims:
            print(f"error: {apk} lacks {RUNTIME} or the sim library", file=sys.stderr)
            return 1
        runtime = Path(archive.extract(RUNTIME, tmp))
        failed = False
        for name in sims:
            missing = missing_imports(Path(archive.extract(name, tmp)), [runtime, *system])
            if missing:
                failed = True
                print(f"error: {name} imports {len(missing)} symbols nothing in the APK or Android {api}'s libc provides:")
                for symbol in missing[:40]:
                    print(f"  {symbol}")
            else:
                print(f"ok       {name}: every import resolves against {RUNTIME} and Android {api}'s libc, libm and libdl")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
