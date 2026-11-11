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
stock_info="$mod/stock-routing"
stock_uuid=
if [ -f "$stock_info" ]; then
  cat "$stock_info"
  target="$(sed -n 's/^Config: //p' "$stock_info")"
  stock_uuid="$(sed -n 's/^Stock UUID: //p' "$stock_info")"
  library_file="$(sed -n 's/^Library file: //p' "$stock_info")"
  library_name="${library_file##*/}"
else
  for key in enabled in_enabled loglevel; do
    printf '%s: framework=%s vendor=%s\n' "$key" \
      "$(getprop "persist.clarifae.$key")" "$(getprop "persist.vendor.clarifae.$key")"
  done
  target="$(cat /data/adb/clarifae/audio_effects.patched 2>/dev/null)"
  library_name=libclarifae.so
fi
for flag in disable remove skip_mount; do
  [ ! -e "$mod/$flag" ] || echo "Module flag: $flag"
done
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
    if [ -n "$stock_uuid" ]; then
      case "$target" in
        /system/*) staged="$mod$target" ;;
        *) staged="$mod/system$target" ;;
      esac
      if cmp -s "$staged" "$proc/root$target"; then
        echo "Staged stock capture routing visible at $target"
      else
        echo "Stock capture routing differs or is unreadable at $target"
      fi
    elif grep -q 'c1a71fae-0001-4a5e-9b10-43578768aaf3' "$proc/root$target" 2>/dev/null; then
      echo "Clarifae UUID visible in $target"
    else
      echo "Clarifae UUID absent or unreadable in $target"
    fi
  fi
  if [ -r "$proc/maps" ]; then
    mapped=$(awk -v lib="$library_name" '
      $6 ~ /^\// { n = split($6, path, "/"); if (path[n] == lib) print $6 }
    ' "$proc/maps" 2>/dev/null | sort -u)
    printf '%s\n' "${mapped:-Effect library mapping not found}"
  else
    echo "Audio process maps unavailable"
  fi
done

echo "=== Audio effects config filenames ==="
for dir in /vendor/etc /odm/etc /system/etc /system_ext/etc /product/etc; do
  [ -d "$dir" ] || continue
  find "$dir" -maxdepth 4 \( -name 'audio_effects*.xml' -o -name 'audio_effects*.conf' \) 2>/dev/null
done
echo "=== Live effect references and record threads ==="
flinger=$(dumpsys -t 5 media.audio_flinger 2>/dev/null)
if [ -n "$stock_uuid" ]; then
  printf '%s\n' "$flinger" | grep -iF -C 4 -e "$stock_uuid" -e 'Noise Suppression' -e 'NoiseSuppressor' | head -n 80
else
  printf '%s\n' "$flinger" | grep -iE -C 4 'Clarifae|c1a71fae' | head -n 80
fi
printf '%s\n' "$flinger" | grep -iE 'record thread|input device|audio source|input flags|FastCapture' | head -n 50
echo "=== Capture policy ==="
dumpsys -t 5 media.audio_policy 2>/dev/null |
  grep -iE 'input descriptor|input flag|input device|AUDIO_SOURCE|AUDIO_INPUT_FLAG|AUDIO_DEVICE_IN_' | head -n 60
if [ -z "$stock_uuid" ]; then
  echo "=== Clarifae effect lifecycle ==="
  logcat -d -s Clarifae:V 2>/dev/null | tail -n 70
fi
echo "=== Recent Clarifae audio loader messages ==="
logcat -d -t 2000 2>/dev/null |
  grep -iE 'checkEffectCompatibility_l.*Clarifae|audio_effects(_config)?\.(xml|conf)|avc:.*libclarifae|dlopen.*libclarifae' | tail -n 35
