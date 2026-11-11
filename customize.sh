#!/system/bin/sh
# customize.sh — Clarifae installer (sourced by Magisk / KernelSU / APatch).
SKIPUNZIP=0

ui_print " "
ui_print "  ============================================"
ui_print "   Clarifae — Real-Time AI Audio Clarity"
ui_print "   RNNoise / DTLN / DeepFilterNet  +  WebUI"
ui_print "  ============================================"
ui_print " "

. "$MODPATH/common/functions.sh"

# --- architecture -> ABI / lib dir ---
ui_print "- Architecture: $ARCH (API $API)"
case "$ARCH" in
  arm64) ABI=arm64-v8a;   LIBD=lib64 ;;
  arm)   ABI=armeabi-v7a; LIBD=lib   ;;
  x64)   ABI=x86_64;      LIBD=lib64 ;;
  x86)   ABI=x86;         LIBD=lib   ;;
  *) abort "! Unsupported architecture: $ARCH" ;;
esac

# --- stage the native effect for the vendor audio service's linker namespace ---
[ -f "$MODPATH/lib/$ABI/libclarifae.so" ] || \
  abort "! libclarifae.so for $ABI not bundled. Build it: ABIS=\"$ABI\" ./build.sh"

# --- runtime data dir + config + helpers ---
mkdir -p "$CLARIFAE_DIR/models/dtln" "$CLARIFAE_DIR/models/df"
conf_init
cp -f "$MODPATH/common/functions.sh" "$CLARIFAE_DIR/functions.sh"
ui_print "- Config: $CONFIG"

# --- CLI: on PATH (system/bin, post-reboot) + always-present data-dir copy ---
# The WebUI calls the data-dir copy by absolute path, so toggles work even
# before a reboot and regardless of whether the system overlay is on PATH.
mkdir -p "$MODPATH/system/bin"
cp -f "$MODPATH/common/clarifae-ctl" "$MODPATH/system/bin/clarifae-ctl"
cp -f "$MODPATH/common/clarifae-ctl" "$CLARIFAE_DIR/clarifae-ctl"
chmod 0755 "$CLARIFAE_DIR/clarifae-ctl"

# --- copy any bundled optional models to /data ---
[ -d "$MODPATH/models" ] && cp -rf "$MODPATH/models/." "$CLARIFAE_DIR/models/" 2>/dev/null

# --- stage registration without modifying the live partitions ---
if [ -d "/vendor/$LIBD/soundfx" ]; then
  effect_path="/vendor/$LIBD/soundfx/libclarifae.so"
  lib_label=u:object_r:vendor_file:s0
else
  effect_path="/system/$LIBD/soundfx/libclarifae.so"
  lib_label=u:object_r:system_file:s0
fi
lib_dest=
rm -f "$PATCH_MARK"
if aidl_effect_factory_running; then
  ui_print "! AIDL audio effects factory detected. This build supports legacy/HIDL effects."
  ui_print "  Diagnostic tools installed. Audio configuration was left alone."
  clarifae_log "AIDL effects factory detected; legacy registration skipped"
elif patch_audio_effects "$MODPATH" "$effect_path"; then
  lib_dest="$(overlay_path_for "$MODPATH" "$effect_path")"
  mkdir -p "$(dirname "$lib_dest")" && cp -f "$MODPATH/lib/$ABI/libclarifae.so" "$lib_dest" ||
    abort "! Unable to stage libclarifae.so"
  ui_print "- Staged libclarifae.so ($ABI) -> ${lib_dest#"$MODPATH/"}"
  ui_print "- Staged audio configuration for $(cat "$PATCH_MARK")"
  ui_print "  Reboot and verify during recording. Some KernelSU versions require a mounting metamodule."
else
  ui_print "! Could not stage audio effects on this device. Use the installed diagnostic script."
fi
rm -rf "$MODPATH/lib"

# --- seed props (service.sh re-applies on every boot) ---
with_config_lock prop_sync 2>/dev/null || ui_print "! Live settings will be retried at boot."

# --- permissions ---
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/system/bin/clarifae-ctl" 0 0 0755
[ -n "$lib_dest" ] && set_perm "$lib_dest" 0 0 0644 "$lib_label"

ui_print " "
ui_print "  Installed. Reboot, then open the WebUI:"
ui_print "   - KernelSU/APatch: Modules > Clarifae > Open"
ui_print "   - Magisk: use the MMRL app to open Clarifae's WebUI"
ui_print "  Default engine: RNNoise."
ui_print " "
