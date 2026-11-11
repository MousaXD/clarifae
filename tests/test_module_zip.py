"""Validate the shipped Android ELF and root module entries."""
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import zipfile

MACHINE = {"arm64-v8a": 183, "armeabi-v7a": 40, "x86_64": 62, "x86": 3}
with zipfile.ZipFile(sys.argv[1]) as archive, tempfile.TemporaryDirectory() as tmp:
    assert archive.testzip() is None
    names = set(archive.namelist())
    assert {"module.prop", "customize.sh", "common/patch-effects.awk", "common/patch-effects-conf.awk",
            "scripts/diagnose-hyperos.sh", "webroot/index.html"} <= names
    assert not any(n.startswith((".git", "android-companion/", "native/")) for n in names)
    libraries = sorted(n for n in names if re.fullmatch(r"lib/[^/]+/libclarifae\.so", n))
    assert libraries
    for name in libraries:
        data = archive.read(name)
        assert data[:4] == b"\x7fELF" and data[5] == 1
        abi = name.split("/")[1]
        assert struct.unpack_from("<H", data, 18)[0] == MACHINE[abi]
        lib = Path(tmp) / "libclarifae.so"
        lib.write_bytes(data)
        symbols = subprocess.check_output(["readelf", "--dyn-syms", "--wide", lib], text=True)
        symbol = next(line.split() for line in symbols.splitlines() if line.endswith(" AELI"))
        assert symbol[3:6] == ["OBJECT", "GLOBAL", "DEFAULT"]
        address = int(symbol[1], 16)
        headers = subprocess.check_output(["readelf", "--program-headers", "--wide", lib], text=True)
        found_aeli = False
        for line in headers.splitlines():
            if not line.strip().startswith("LOAD "):
                continue
            fields = line.split()
            offset, base, length = (int(fields[i], 16) for i in (1, 2, 4))
            if data[4] == 2:
                assert int(fields[-1], 16) >= 16384, f"{abi} lacks 16 KiB page support"
            if base <= address < base + length:
                start = offset + address - base
                assert struct.unpack_from("<II", data, start) == (0x41454C54, 0x00030000)
                found_aeli = True
        assert found_aeli, f"AELI has no load segment in {abi}"
        print(f"{abi}: exported AELI, Android tag and library version verified")
