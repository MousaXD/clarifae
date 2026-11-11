#!/system/bin/sh
# functions.sh — shared Clarifae helpers, sourced by customize.sh (install time)
# and by clarifae-ctl (runtime, from /data/adb/clarifae/functions.sh).
# POSIX sh / busybox ash only — no bashisms.

CLARIFAE_DIR=/data/adb/clarifae
CONFIG="$CLARIFAE_DIR/config.conf"
LOGFILE="$CLARIFAE_DIR/clarifae.log"
PATCH_MARK="$CLARIFAE_DIR/audio_effects.patched"   # holds the target config path
MODULE_DIR=/data/adb/modules/clarifae              # always present post-boot, mount-namespace independent

CLARIFAE_VERSION="v1.2.0"
EFFECT_UUID="c1a71fae-0001-4a5e-9b10-43578768aaf3"       # input  (capture pre-proc)
EFFECT_UUID_OUT="c1a71fae-0002-4a5e-9b10-43578768aaf3"   # output (playback post-proc)

CLARIFAE_KEYS="enabled in_enabled out_enabled mode strength out_strength atten_db vad targets out_targets highpass autogain loglevel"

clarifae_defaults() {
  cat <<'EOF'
enabled=1
in_enabled=1
out_enabled=0
mode=1
strength=70
out_strength=60
atten_db=24
vad=50
targets=mic,voice_comm,camcorder
out_targets=music,voice_call
highpass=1
autogain=0
loglevel=1
EOF
}

clarifae_log() {
  mkdir -p "$CLARIFAE_DIR" 2>/dev/null
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE" 2>/dev/null
}

conf_init() {
  mkdir -p "$CLARIFAE_DIR" || return 1
  [ -f "$CONFIG" ] || (umask 077; set -C; clarifae_defaults > "$CONFIG") 2>/dev/null || [ -f "$CONFIG" ]
}

valid_number() {
  case "$1" in
    0|[1-9]|[1-9][0-9]|100) [ "$1" -le "$2" ] ;;
    *) return 1 ;;
  esac
}

valid_targets() (
  case "$2" in "" ) return 0 ;; ,*|*,|*,,*) return 1 ;; esac
  set -f
  IFS=,
  for target in $2; do
    case "$1:$target" in
      targets:mic|targets:voice_comm|targets:camcorder|targets:voice_rec) ;;
      out_targets:music|out_targets:media|out_targets:voice_call|out_targets:calls|out_targets:ring|out_targets:alarm|out_targets:notification|out_targets:notif|out_targets:system) ;;
      *) return 1 ;;
    esac
  done
  [ "${#2}" -le 63 ]
)

validate_config_value() {
  case "$1" in
    enabled|in_enabled|out_enabled|highpass|autogain) [ "$2" = 0 ] || [ "$2" = 1 ] ;;
    mode) case "$2" in 1|2|3) return 0 ;; *) return 1 ;; esac ;;
    loglevel) valid_number "$2" 3 ;;
    strength|out_strength|vad) valid_number "$2" 100 ;;
    atten_db) valid_number "$2" 60 ;;
    targets|out_targets) valid_targets "$1" "$2" ;;
    *) return 1 ;;
  esac
}

# Preserve an explicitly empty route list and recover from invalid old values.
conf_get() (
  key="$1"
  if value=$(awk -v key="$key" '
    index($0, key "=") == 1 { value = substr($0, length(key) + 2); found = 1 }
    END { if (!found) exit 1; print value }
  ' "$CONFIG" 2>/dev/null) && validate_config_value "$key" "$value"; then
    printf '%s' "$value"
  else
    clarifae_defaults | awk -v key="$key" 'index($0, key "=") == 1 { printf "%s", substr($0, length(key) + 2) }'
  fi
)

# Serialize writers across the WebUI, command line and boot service.
with_config_lock() (
  mkdir -p "$CLARIFAE_DIR" || return 1
  umask 077
  exec 9>"$CLARIFAE_DIR/config.lock" || return 1
  if command -v flock >/dev/null 2>&1; then
    flock -x 9 || return 1
  else
    locked=0
    for busybox in /data/adb/magisk/busybox /data/adb/ksu/bin/busybox /data/adb/ap/bin/busybox; do
      if [ -x "$busybox" ] && "$busybox" flock -x 9; then
        locked=1
        break
      fi
    done
    [ "$locked" = 1 ] || { echo "Could not lock Clarifae configuration" >&2; return 1; }
  fi
  "$@"
)

conf_write() (
  conf_init || return 1
  tmp=$(mktemp "$CONFIG.XXXXXX") || return 1
  trap 'rm -f "$tmp"' EXIT
  awk -v changes="$(printf '%s\n' "$@")" '
    BEGIN {
      count = split(changes, lines, "\n")
      for (i = 1; i <= count; i++) {
        split(lines[i], pair, "=")
        order[i] = pair[1]
        replacement[pair[1]] = lines[i]
      }
    }
    {
      split($0, pair, "=")
      if (!(pair[1] in replacement)) print
    }
    END {
      for (i = 1; i <= count; i++)
        if (!written[order[i]]++) print replacement[order[i]]
    }
  ' "$CONFIG" > "$tmp" && mv -f "$tmp" "$CONFIG"
)

# write a single property (persisted)
_setp() {
  if command -v resetprop >/dev/null 2>&1; then
    resetprop -n -p "$1" "$2"
  else
    setprop "$1" "$2"
  fi
}

# Keep both the framework and vendor HAL property namespaces in sync.
publish_config_key() (
  result=0
  _setp "persist.clarifae.$1" "$2" || result=1
  _setp "persist.vendor.clarifae.$1" "$2" || result=1
  return "$result"
)

# Publish the saved settings at boot and when explicitly reapplied.
prop_sync() {
  sync_failed=0
  for _prop_key in $CLARIFAE_KEYS; do
    publish_config_key "$_prop_key" "$(conf_get "$_prop_key")" || sync_failed=1
  done
  [ "$sync_failed" = 0 ] || { clarifae_log "property sync incomplete"; return 1; }
  clarifae_log "props synced from config"
}

mode_name() {
  case "$1" in
    1) echo "RNNoise (Low latency)";;
    2) echo "DTLN (Balanced)";;
    3) echo "DeepFilterNet (Maximum clarity)";;
    *) echo "Unknown";;
  esac
}

# ---- audio_effects.xml / .conf integration ----

find_audio_effects_xml() (
  filename="$1"
  _sku="$(getprop ro.boot.product.vendor.sku)"
  case "$_sku" in
    ''|*[!a-zA-Z0-9_.-]*) _sku_dir= ;;
    *) _sku_dir="/vendor/etc/audio/sku_$_sku" ;;
  esac
  for _dir in /odm/etc $_sku_dir /vendor/etc /system/etc; do
    _f="$_dir/$filename"
    [ -r "$_f" ] && { echo "$_f"; return 0; }
  done
  return 1
)

find_audio_effects_file() {
  find_audio_effects_xml audio_effects.xml && return 0
  for _f in /vendor/etc/audio_effects.conf /system/etc/audio_effects.conf; do
    [ -r "$_f" ] && { echo "$_f"; return 0; }
  done
  return 1
}

aidl_effect_factory_running() {
  service check android.hardware.audio.effect.IFactory/default 2>/dev/null | grep -q ': found$'
}

# map a real partition path to the module overlay path (Magisk magic-mount)
overlay_path_for() {
  _mp="$1"; _real="$2"
  case "$_real" in
    /vendor/*) echo "$_mp/system$_real" ;;          # system/vendor -> /vendor
    /odm/*)    echo "$_mp/system/odm${_real#/odm}" ;;
    /system/*) echo "$_mp$_real" ;;
    *)         echo "$_mp/system$_real" ;;
  esac
}

# our csv target names -> AOSP audio_source stream types (capture / <preprocess>)
map_targets() {
  _out=""
  _oifs="$IFS"; IFS=,
  for _t in $1; do
    case "$_t" in
      mic)        _s=mic ;;
      voice_comm) _s=voice_communication ;;
      camcorder)  _s=camcorder ;;
      voice_rec)  _s=voice_recognition ;;
      *)          _s="" ;;
    esac
    [ -n "$_s" ] && _out="$_out $_s"
  done
  IFS="$_oifs"
  echo "$_out"
}

# our csv out target names -> AOSP audio_stream_type names (playback / <postprocess>)
map_out_targets() {
  _out=""
  _oifs="$IFS"; IFS=,
  for _t in $1; do
    case "$_t" in
      media|music)       _s=music ;;
      calls|voice_call)  _s=voice_call ;;
      ring)              _s=ring ;;
      alarm)             _s=alarm ;;
      notif|notification) _s=notification ;;
      system)            _s=system ;;
      *)                 _s="" ;;
    esac
    [ -n "$_s" ] && _out="$_out $_s"
  done
  IFS="$_oifs"
  echo "$_out"
}

_patch_xml_file() {
  awk -v uuid_in="$EFFECT_UUID" -v uuid_out="$EFFECT_UUID_OUT" \
      -v in_streams="$3" -v out_streams="$4" -f "$5" "$1" > "$2"
}

_patch_conf_file() {
  awk -v uuid_in="$EFFECT_UUID" -v uuid_out="$EFFECT_UUID_OUT" \
      -v in_streams="$3" -v out_streams="$4" -v lib_path="$6" -f "$5" "$1" > "$2"
}

# patch_audio_effects MODPATH: stage a complete overlay atomically.
patch_audio_effects() (
  mp="$1"
  lib_path="$2"
  real="$(find_audio_effects_file)" || { clarifae_log "audio_effects file not found"; return 1; }
  streams="$(map_targets "$(conf_get targets)")"
  out_streams="$(map_out_targets "$(conf_get out_targets)")"
  # Resolve vendor/ODM aliases so the file is staged on the owning partition.
  resolved="$(readlink -f "$real")" && [ -n "$resolved" ] && real="$resolved"
  case "$real" in /vendor/*|/odm/*|/system/*) ;; *) return 1 ;; esac
  overlay="$(overlay_path_for "$mp" "$real")"

  mkdir -p "$(dirname "$overlay")" || return 1
  tmp="$overlay.tmp"
  case "$real" in
    *.xml)  _patch_xml_file "$real" "$tmp" "$streams" "$out_streams" "$mp/common/patch-effects.awk" ;;
    *.conf) _patch_conf_file "$real" "$tmp" "$streams" "$out_streams" "$mp/common/patch-effects-conf.awk" "$lib_path" ;;
    *) return 1 ;;
  esac

  if [ $? -eq 0 ] && chmod 0644 "$tmp" && mv -f "$tmp" "$overlay"; then
    printf '%s\n' "$real" > "$PATCH_MARK" || return 1
    clarifae_log "staged audio effects: $real -> $overlay (in:$streams | out:$out_streams)"
    return 0
  fi
  rm -f "$tmp"
  clarifae_log "FAILED to patch $real"
  return 1
)

is_audio_effects_patched() {
  _f="$(cat "$PATCH_MARK" 2>/dev/null)" || return 1
  _ov="$(overlay_path_for "$MODULE_DIR" "$_f")"
  [ -f "$_ov" ] && grep -q "$EFFECT_UUID" "$_ov" 2>/dev/null
}
