"""Check the installer patch against realistic XML and upgrades."""
from pathlib import Path
import re
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


LEGACY = """# libraries { ignored }
libraries {
    vendor_ns {
        path /vendor/lib/soundfx/libvendor_ns.so
    }
}
effects {
    oem_ns {
        library vendor_ns
        uuid oem-uuid
    }
}
pre_processing {
    voice_communication {
        oem_ns {}
    }
}
"""
legacy_patcher = PATCHER.with_name("patch-effects-conf.awk")


def patch_legacy(config, check=True):
    return subprocess.run(
        ["awk", "-v", f"uuid_in={INPUT_UUID}", "-v", f"uuid_out={OUTPUT_UUID}",
         "-v", "in_streams=mic voice_communication", "-v", "out_streams=music",
         "-v", "lib_path=/vendor/lib64/soundfx/libclarifae.so", "-f", str(legacy_patcher)],
        input=config, text=True, capture_output=True, check=check,
    )


first = patch_legacy(LEGACY).stdout
for conf in (first, patch_legacy(first).stdout):
    assert conf.count("voice_communication {") == 1
    assert conf.count("output_session_processing {") == 1
    assert conf.count("oem_ns {}") == 1
    assert conf.count("clarifae_ns {}") == 2
    assert conf.count(INPUT_UUID) == conf.count(OUTPUT_UUID) == 1
    assert f"library clarifae\n    uuid {INPUT_UUID}\n" in conf
    assert "path /vendor/lib64/soundfx/libclarifae.so\n" in conf
    assert re.search(r"music\s*\{\s*clarifae_out\s*\{\s*\}\s*\}", conf)
assert patch_legacy("libraries {", check=False).returncode != 0
print("Legacy configuration checks passed")


STOCK_NS = "c06c8400-8e06-11e0-9cb6-0002a5d5c51b"
STOCK_TYPES = ("mic", "camcorder", "voice_communication")


def patch_stock(xml, factory, check=True):
    return subprocess.run(
        ["awk", "-v", "engine=stock", "-v", f"factory={factory}",
         "-v", f"in_streams={' '.join(STOCK_TYPES)}", "-f", str(PATCHER)],
        input=xml, text=True, capture_output=True, check=check,
    )


for factory, effect in (("hidl", "ns"), ("aidl", "noise_suppression")):
    stock = STOCK.replace(
        "</effects>",
        f'<effect name="{effect}" library="oem" uuid="{STOCK_NS}"/></effects>',
    ).replace(
        '<apply effect="oem_proxy"/></stream>',
        f'<apply effect="oem_proxy"/><apply effect="{effect}"/></stream>',
    ).replace(
        "</preprocess>",
        '<stream type="unprocessed"/><stream type="voice_recognition"/></preprocess>',
    )
    overlay = patch_stock(stock, factory).stdout
    for text in (overlay, patch_stock(overlay, factory).stdout):
        root = ET.fromstring(text)
        assert effects(root, "preprocess", "voice_communication") == ["oem_proxy", effect]
        assert effects(root, "preprocess", "mic") == [effect]
        assert effects(root, "preprocess", "camcorder") == [effect]
        assert effects(root, "preprocess", "unprocessed") == []
        assert effects(root, "preprocess", "voice_recognition") == []
        assert effects(root, "postprocess", "music") == []
        assert len(root.findall("./{*}libraries/{*}library")) == 1

    native_after_stock = ET.fromstring(patch(overlay).stdout)
    assert effects(native_after_stock, "preprocess", "mic") == ["clarifae_ns"]
    assert effects(native_after_stock, "preprocess", "camcorder") == []
    stock_after_native = ET.fromstring(patch_stock(patch(stock).stdout, factory).stdout)
    assert effects(stock_after_native, "preprocess", "mic") == [effect]
    assert effects(stock_after_native, "postprocess", "music") == []

    unresolved = stock.replace('library="oem" uuid="' + STOCK_NS, 'library="missing" uuid="' + STOCK_NS)
    assert patch_stock(unresolved, factory, check=False).returncode != 0
assert patch_stock(STOCK, "hidl", check=False).returncode != 0
assert patch_stock(STOCK, "aidl", check=False).returncode != 0
# A recognized OEM proxy already in a source chain stays in that chain.
with_proxy = STOCK.replace(
    'name="oem_proxy" library="oem" uuid="native-proxy"',
    'name="ns" library="oem" uuid="5512a6a0-01b0-4d8c-b16b-88e266279baf"',
).replace(
    '<apply effect="oem_proxy"/>', '<apply effect="ns"/>',
).replace(
    "</effects>",
    f'<effect name="noise_suppression" library="oem" uuid="{STOCK_NS}"/></effects>',
)
root = ET.fromstring(patch_stock(with_proxy, "hidl").stdout)
assert effects(root, "preprocess", "voice_communication") == ["ns"]
assert effects(root, "preprocess", "mic") == ["noise_suppression"]
print("Stock noise suppression route checks passed on HIDL and AIDL fixtures")
