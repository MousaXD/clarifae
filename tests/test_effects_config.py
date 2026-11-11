"""Check the installer patch against realistic XML and upgrades."""
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

PATCHER = Path(__file__).resolve().parents[1] / "common" / "patch-effects.awk"
INPUT_UUID = "c1a71fae-0001-4a5e-9b10-43578768aaf3"
OUTPUT_UUID = "c1a71fae-0002-4a5e-9b10-43578768aaf3"
STOCK = """<?xml version="1.0"?>
<audio_effects_conf xmlns="http://schemas.android.com/audio/audio_effects_conf/v2_0">
    <!-- <libraries/> <apply effect="clarifae_ns"/> -->
    <libraries><library name="oem" path="liboem.so"/></libraries>
    <effects>
        <effectProxy name="oem_proxy" library="oem" uuid="native-proxy">
            <libsw library="oem" uuid="native-sw"/><libhw library="oem" uuid="native-hw"/>
        </effectProxy>
    </effects>
    <preprocess><stream
      type = 'voice_communication'><apply effect="oem_proxy"/></stream><stream type="mic"/>
    </preprocess>
    <postprocess/>
</audio_effects_conf>"""


def patch(xml, targets="mic voice_communication", playback="music", check=True):
    return subprocess.run(
        ["awk", "-v", f"uuid_in={INPUT_UUID}", "-v", f"uuid_out={OUTPUT_UUID}",
         "-v", f"in_streams={targets}", "-v", f"out_streams={playback}", "-f", str(PATCHER)],
        input=xml, text=True, capture_output=True, check=check,
    )


def effects(root, direction, stream):
    return [
        apply.attrib["effect"] for node in root.findall(f"./{{*}}{direction}/{{*}}stream")
        if node.get("type") == stream for apply in node.findall("{*}apply")
    ]


patched = patch(STOCK).stdout
assert "<!-- <libraries/> <apply effect=\"clarifae_ns\"/> -->" in patched
for xml in (patched, patch(patched).stdout):
    root = ET.fromstring(xml)
    assert effects(root, "preprocess", "voice_communication") == ["oem_proxy", "clarifae_ns"]
    assert effects(root, "preprocess", "mic") == ["clarifae_ns"]
    assert effects(root, "postprocess", "music") == ["clarifae_out"]
    assert len(root.findall("./{*}libraries/{*}library")) == 2
    assert root.find("./{*}effects/{*}effectProxy/{*}libhw").get("uuid") == "native-hw"

changed = ET.fromstring(patch(patched, targets="camcorder", playback="").stdout)
assert effects(changed, "preprocess", "voice_communication") == ["oem_proxy"]
assert effects(changed, "preprocess", "mic") == []
assert effects(changed, "preprocess", "camcorder") == ["clarifae_ns"]
assert effects(changed, "postprocess", "music") == []

missing = ET.fromstring(patch("<audio_effects_conf><libraries/><effects/></audio_effects_conf>").stdout)
assert effects(missing, "preprocess", "mic") == ["clarifae_ns"]
assert effects(missing, "postprocess", "music") == ["clarifae_out"]
assert patch("<audio_effects_conf><libraries/></audio_effects_conf>", check=False).returncode != 0
assert patch(STOCK.replace("</stream>", "</wrong>"), check=False).returncode != 0
print("Installer XML checks passed")
