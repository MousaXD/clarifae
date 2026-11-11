"""Exercise installed root CLI behavior with isolated files and property writes."""
import json
import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as temp:
    base = Path(temp)
    config = base / "config.conf"
    props = base / "properties"
    for source, name in (
        ("common/functions.sh", "functions.sh"),
        ("common/clarifae-ctl", "clarifae-ctl"),
    ):
        (base / name).write_text((ROOT / source).read_text().replace("/data/adb/clarifae", temp))
    resetprop = base / "resetprop"
    resetprop.write_text(
        """#!/bin/sh
printf '%s=%s\n' "$3" "$4" >> "$PROP_LOG"
[ "$3" != "$FAIL_PROP" ]
"""
    )
    resetprop.chmod(0o755)
    env = dict(os.environ, PATH=f"{temp}:{os.environ['PATH']}", PROP_LOG=str(props), FAIL_PROP="")

    def ctl(*args, check=True, fail_prop=""):
        return subprocess.run(
            ["sh", str(base / "clarifae-ctl"), *args],
            env=dict(env, FAIL_PROP=fail_prop), text=True, capture_output=True, check=check,
        )

    assert json.loads(ctl("get-json").stdout)["out_targets"] == "music,voice_call"
    ctl("set", "out_targets", "")
    assert json.loads(ctl("get-json").stdout)["out_targets"] == ""
    assert "persist.vendor.clarifae.out_targets=\n" in props.read_text()

    previous = config.read_text()
    for bad in ("music|alarm", "music,,ring", "unknown", "music\nring", "music,"):
        assert ctl("set-many", "enabled=0", f"out_targets={bad}", check=False).returncode != 0
    assert ctl("set-many", "enabled=0", "broken", check=False).returncode != 0
    assert config.read_text() == previous

    with ThreadPoolExecutor() as pool:
        results = [
            pool.submit(ctl, "set", "strength", "73"),
            pool.submit(ctl, "set", "atten_db", "17"),
            pool.submit(ctl, "set", "vad", "44"),
        ]
        for result in results:
            result.result()
    settings = json.loads(ctl("get-json").stdout)
    assert (settings["strength"], settings["atten_db"], settings["vad"]) == (73, 17, 44)

    props.write_text("")
    result = ctl(
        "set-many", "enabled=0", "strength=68", check=False, fail_prop="persist.clarifae.enabled"
    )
    assert result.returncode != 0 and "Settings saved" in result.stderr
    assert "persist.vendor.clarifae.enabled=0\n" in props.read_text()
    assert "persist.vendor.clarifae.strength=68\n" in props.read_text()
    ctl("apply")
    assert json.loads(ctl("get-json").stdout)["enabled"] is False
    assert ctl("reset", check=False, fail_prop="persist.clarifae.enabled").returncode != 0
    ctl("reset")
    assert json.loads(ctl("get-json").stdout)["out_targets"] == "music,voice_call"
print("Module settings tests passed")
