#!/system/bin/sh
# Read-only HyperOS/Android microphone routing diagnostic. No audio is recorded.
echo "=== Device ==="
for key in ro.product.device ro.product.model ro.build.version.release ro.build.version.incremental ro.vendor.build.version.sdk; do
  echo "$key=$(getprop "$key")"
done
echo "=== Audio effect configs (system and vendor) ==="
for dir in /vendor/etc /odm/etc /system/etc /system_ext/etc /product/etc; do
  [ -d "$dir" ] || continue
  find "$dir" -maxdepth 3 -type f \( -name 'audio_effects.xml' -o -name 'audio_effects.conf' \) 2>/dev/null
done
echo "=== Clarifae module registration ==="
for dir in /vendor/etc /odm/etc /system/etc /system_ext/etc /product/etc; do
  [ -d "$dir" ] || continue
  find "$dir" -maxdepth 3 -type f \( -name 'audio_effects.xml' -o -name 'audio_effects.conf' \) -exec grep -l -i clarifae '{}' \; 2>/dev/null
done
echo "=== Native library candidates ==="
for f in /vendor/lib64/soundfx/libclarifae.so /system/lib64/soundfx/libclarifae.so /odm/lib64/soundfx/libclarifae.so; do
  [ -f "$f" ] && ls -l "$f"
done
echo "=== AudioFlinger live effect state (start a recording before running) ==="
dumpsys media.audio_flinger 2>/dev/null | grep -i -C 5 -E 'clarifae|effect chain|record thread|pre-process' | head -n 180
echo "=== Audio policy capture routes ==="
dumpsys media.audio_policy 2>/dev/null | grep -i -C 2 -E 'active input|audio source|input profile|record client|effect' | head -n 140
echo "=== Clarifae logs (no microphone data) ==="
logcat -d -s Clarifae:* 2>/dev/null | tail -n 80
echo "=== End ==="
