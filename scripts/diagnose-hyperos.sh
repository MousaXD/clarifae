#!/system/bin/sh
# Run as root during an unrelated app's recording. Reads state only.
if [ "$(id -u)" != 0 ]; then
  echo "Run with root to inspect audio service mount namespaces." >&2
  exit 1
fi

echo "=== Device and root module ==="
for key in ro.product.device ro.build.version.incremental ro.build.version.sdk \
           ro.vendor.build.version.sdk ro.boot.product.vendor.sku; do
  echo "$key=$(getprop "$key")"
done
command -v magisk >/dev/null 2>&1 && magisk -v
mod=/data/adb/modules/clarifae
grep -E '^version(Code)?=' "$mod/module.prop" 2>/dev/null
for flag in disable remove skip_mount; do
  [ ! -e "$mod/$flag" ] || echo "Module flag: $flag"
done
target="$(cat /data/adb/clarifae/audio_effects.patched 2>/dev/null)"
case "$target" in
  /vendor/*|/odm/*|/system/*) echo "Staged config target: $target" ;;
  *) target=; echo "No staged config target recorded" ;;
esac

echo "=== Audio effects factories ==="
service check android.hardware.audio.effect.IFactory/default 2>/dev/null
if command -v lshal >/dev/null 2>&1; then
  lshal -i 2>/dev/null | grep -i 'android.hardware.audio.effect'
fi

echo "=== Audio service namespaces and mapped library ==="
# Find vendor services with names that may be truncated in ps NAME columns.
for pid in $(ps -A -o PID,ARGS | awk '$2 ~ /\/(audioserver|[^/]*audio[^/]*service[^/]*)$/ {print $1}'); do
  proc="/proc/$pid"
  printf 'PID %s ' "$pid"
  cat "$proc/comm" 2>/dev/null
  cat "$proc/attr/current" 2>/dev/null
  printf '\n'
  if [ -n "$target" ]; then
    if grep -q 'c1a71fae-0001-4a5e-9b10-43578768aaf3' "$proc/root$target" 2>/dev/null; then
      echo "Clarifae UUID visible in $target"
    else
      echo "Clarifae UUID absent or unreadable in $target"
    fi
  fi
  grep -oE '/[^[:space:]]*libclarifae\.so' "$proc/maps" 2>/dev/null | sort -u
done

echo "=== Audio effects config filenames ==="
for dir in /vendor/etc /odm/etc /system/etc /system_ext/etc /product/etc; do
  [ -d "$dir" ] || continue
  find "$dir" -maxdepth 4 \( -name 'audio_effects*.xml' -o -name 'audio_effects*.conf' \) 2>/dev/null
done
echo "=== Live effect references and record threads ==="
dumpsys -t 5 media.audio_flinger 2>/dev/null |
  grep -iE -C 4 'Clarifae|c1a71fae|record thread|effect chain' | head -n 180
echo "=== Recent Clarifae audio loader messages ==="
logcat -d -t 2000 2>/dev/null |
  grep -iE 'Clarifae|audio_effects(_config)?\.(xml|conf)' | tail -n 60
