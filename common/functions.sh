#!/system/bin/sh
# functions.sh — shared Clarifae helpers, sourced by customize.sh (install time)
# and by clarifae-ctl (runtime, from /data/adb/clarifae/functions.sh).
# POSIX sh / busybox ash only — no bashisms.

CLARIFAE_DIR=/data/adb/clarifae
CONFIG="$CLARIFAE_DIR/config.conf"
LOGFILE="$CLARIFAE_DIR/clarifae.log"
PATCH_MARK="$CLARIFAE_DIR/audio_effects.patched"   # holds the target config path
MODULE_DIR=/data/adb/modules/clarifae              # always present post-boot, mount-namespace independent

CLARIFAE_VERSION="v1.1.3"
EFFECT_UUID="c1a71fae-0001-4a5e-9b10-43578768aaf3"       # input  (capture pre-proc)
EFFECT_UUID_OUT="c1a71fae-0002-4a5e-9b10-43578768aaf3"   # output (playback post-proc)
LIB_NAME="clarifae"
EFFECT_NAME="clarifae_ns"
OUT_EFFECT_NAME="clarifae_out"

CLARIFAE_KEYS="enabled in_enabled out_enabled mode strength out_strength atten_db vad targets out_targets highpass autogain loglevel"

clarifae_defaults() {
  cat <<'EOF'
enabled=1
in_enabled=1
out_enabled=1
mode=1
strength=70
out_strength=60
atten_db=24
vad=50
targets=mic,voice_comm
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
  mkdir -p "$CLARIFAE_DIR" 2>/dev/null
  [ -f "$CONFIG" ] || clarifae_defaults > "$CONFIG"
}

# conf_get KEY -> value (falls back to default)
conf_get() {
  _k="$1"; _v=""
  [ -f "$CONFIG" ] && _v=$(grep "^$_k=" "$CONFIG" 2>/dev/null | tail -n1 | cut -d= -f2-)
  [ -z "$_v" ] && _v=$(clarifae_defaults | grep "^$_k=" | cut -d= -f2-)
  printf '%s' "$_v"
}

# conf_set KEY VALUE
conf_set() {
  _k="$1"; _v="$2"
  conf_init
  if grep -q "^$_k=" "$CONFIG" 2>/dev/null; then
    _tmp="$CONFIG.tmp.$$"
    sed "s|^$_k=.*|$_k=$_v|" "$CONFIG" > "$_tmp" && mv "$_tmp" "$CONFIG"
  else
    echo "$_k=$_v" >> "$CONFIG"
  fi
}

# write a single property (persisted)
_setp() {
  if command -v resetprop >/dev/null 2>&1; then
    resetprop -n -p "$1" "$2"
  else
    setprop "$1" "$2"
  fi
}

# Keep both the framework and vendor HAL property namespaces in sync.
publish_config_key() {
  _setp "persist.clarifae.$1" "$2" || return 1
  _setp "persist.vendor.clarifae.$1" "$2"
}

# Publish the saved settings at boot and when explicitly reapplied.
prop_sync() {
  for _prop_key in $CLARIFAE_KEYS; do
    publish_config_key "$_prop_key" "$(conf_get "$_prop_key")" || return 1
  done
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

find_audio_effects_file() {
  _sku="$(getprop ro.boot.product.vendor.sku)"
  case "$_sku" in
    ''|*[!a-zA-Z0-9_.-]*) _sku_dir= ;;
    *) _sku_dir="/vendor/etc/audio/sku_$_sku" ;;
  esac
  for _dir in /odm/etc $_sku_dir /vendor/etc /system/etc; do
    _f="$_dir/audio_effects.xml"
    [ -r "$_f" ] && { echo "$_f"; return 0; }
  done
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
  _src="$1"; _dst="$2"; _in_streams="$3"; _out_streams="$4"
  awk -v uuid_in="$EFFECT_UUID" -v uuid_out="$EFFECT_UUID_OUT" -v lib="$LIB_NAME" \
      -v eff_in="$EFFECT_NAME" -v eff_out="$OUT_EFFECT_NAME" \
      -v in_streams="$_in_streams" -v out_streams="$_out_streams" '
    BEGIN { lib_done=0; eff_done=0 }
    { print }
    /libraries[ \t]*\{/ && !lib_done { print "  " lib " { path libclarifae.so }"; lib_done=1 }
    /effects[ \t]*\{/   && !eff_done {
      print "  " eff_in  " { library " lib " uuid " uuid_in  " }";
      print "  " eff_out " { library " lib " uuid " uuid_out " }";
      eff_done=1
    }
    /pre_processing[ \t]*\{/ {
      n=split(in_streams, ai, " ");
      for (i=1;i<=n;i++) if (ai[i]!="") print "  " ai[i] " { " eff_in " {} }";
    }
    /post_processing[ \t]*\{/ {
      n=split(out_streams, ao, " ");
      for (i=1;i<=n;i++) if (ao[i]!="") print "  " ao[i] " { " eff_out " {} }";
    }
  ' "$_src" > "$_dst" 2>/dev/null
  [ -s "$_dst" ] && grep -q "clarifae" "$_dst"
}

# patch_audio_effects MODPATH: stage a complete overlay atomically.
patch_audio_effects() (
  mp="$1"
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
    *.conf) _patch_conf_file "$real" "$tmp" "$streams" "$out_streams" ;;
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
