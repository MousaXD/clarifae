"""Check that the stock module ships only the config installer and diagnostics."""
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None
    payload = {name for name in archive.namelist() if not name.endswith("/")}
    assert payload == {
        "META-INF/com/google/android/update-binary",
        "META-INF/com/google/android/updater-script",
        "module.prop",
        "customize.sh",
        "common/functions.sh",
        "common/patch-effects.awk",
        "scripts/diagnose-hyperos.sh",
        "uninstall.sh",
    }
    properties = dict(
        line.split("=", 1) for line in archive.read("module.prop").decode().splitlines()
    )
    assert properties["id"] == "clarifae"
    assert properties["version"].endswith("-stock")
    assert properties["name"] == "Clarifae Stock Mic"
    assert 'engine=stock' in archive.read("customize.sh").decode()
print("Stock module payload verified")
