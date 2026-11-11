#!/system/bin/sh
# Packaged as customize.sh in the stock noise suppression module.
. "$MODPATH/common/functions.sh" || abort "! Clarifae helpers missing"

ui_print "- Clarifae Stock Mic: applying the phone's built-in noise suppressor."
legacy_xml="$(find_audio_effects_xml audio_effects.xml)"
aidl_xml="$(find_audio_effects_xml audio_effects_config.xml)"
if aidl_effect_factory_running; then
  factory=aidl
  config="$aidl_xml"
elif [ -n "$legacy_xml" ] && [ -n "$aidl_xml" ]; then
  if command -v lshal >/dev/null 2>&1 &&
    timeout 5 lshal -i 2>/dev/null | grep -q 'android.hardware.audio.effect@.*::IEffectsFactory/'; then
    factory=hidl
    config="$legacy_xml"
  else
    abort "! Both effects configurations exist. Install from the root manager while Android is running so the effects factory can be identified."
  fi
elif [ -n "$aidl_xml" ]; then
  factory=aidl
  config="$aidl_xml"
else
  factory=hidl
  config="$legacy_xml"
fi
[ -n "$config" ] || abort "! No matching audio effects XML found for the $factory factory."

# Resolve a partition alias without writing to the source file.
resolved="$(readlink -f "$config")"
case "$resolved" in
  /vendor/*|/odm/*|/system/*) ;;
  *) abort "! Unsupported effects path: $resolved" ;;
esac
overlay="$(overlay_path_for "$MODPATH" "$resolved")"
info="$MODPATH/stock-routing"
mkdir -p "$(dirname "$overlay")" || abort "! Could not create module overlay."
awk -v engine=stock -v factory="$factory" -v 'in_streams=mic camcorder voice_communication' \
  -v report="$info" -f "$MODPATH/common/patch-effects.awk" "$resolved" > "$overlay" ||
  abort "! No usable stock noise suppressor entry found in $config."

library="$(sed -n 's/^Stock library: //p' "$info")"
case "$library" in
  ""|*[!a-zA-Z0-9_./+-]*|*/../*|../*) abort "! Unrecognized stock noise suppressor library path." ;;
esac
# AIDL effects may live in a vendor APEX. Search common soundfx locations.
library_found=
case "$library" in
  /odm/*|/vendor/*|/system/*|/apex/*) [ ! -r "$library" ] || library_found="$library" ;;
  /*) abort "! Stock effect library is outside the audio system partitions." ;;
  *)
    for lib_root in /odm/lib /odm/lib64 /vendor/lib /vendor/lib64 \
                    /system/lib /system/lib64 /apex/*/lib /apex/*/lib64; do
      if [ -r "$lib_root/soundfx/$library" ]; then
        library_found="$lib_root/soundfx/$library"
        break
      fi
    done
    ;;
esac
[ -n "$library_found" ] || abort "! Stock effect library $library is not readable on this firmware."

printf 'Config: %s\nLibrary file: %s\n' "$resolved" "$library_found" >> "$info" ||
  abort "! Could not save module routing details."
set_perm_recursive "$MODPATH" 0 0 0755 0644
ui_print "- Config: $resolved ($factory)"
ui_print "- $(sed -n '/^Stock effect: /p' "$info")"
ui_print "- Capture routes: microphone, camcorder, and VoIP."
ui_print "- Reboot to apply. Disable the module and reboot to restore stock routing."
