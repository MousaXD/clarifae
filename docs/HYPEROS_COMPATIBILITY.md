# POCO X7 Pro and HyperOS microphone verification

The POCO X7 Pro is also known as `rodin`. A [public Rodin custom-ROM tree](https://github.com/gimmebackmysandwich/device_xiaomi_rodin/tree/f4e4914) uses a HIDL 7.0 audio effects factory and an XML configuration with existing echo cancellation, noise suppression, and automatic gain control for `voice_communication`. The stock HyperOS firmware and its active capture routes must be checked on the phone.

## v1.2.0 capture options

**Clarifae Stock Mic** looks for a compatible noise suppressor already declared
by the phone's HIDL or AIDL effects configuration. It adds the effect to normal
mic, camcorder, and VoIP routes that have no recognized noise suppressor.
The installer checks for the firmware's effect library. Its only change to the
audio system is a systemless XML overlay.

Flash the stock ZIP in the root manager and reboot. Try a voice note and a camera
video in two different apps. Disable Clarifae Stock Mic in the root manager and
reboot to record matching OFF samples. The companion APK is optional.

Apps using a supported capture source get the same device policy. Raw capture,
voice recognition, cellular modem audio and other vendor DSP paths can follow
different rules. The stock package and regular Clarifae use the same module ID.

**Clarifae with RNNoise** defaults to mic, camcorder and VoIP with playback cleanup
off on fresh installations. Existing installations keep their saved settings.
For an existing RNNoise installation, select Camcorder under Capture sources
and reinstall the RNNoise ZIP to update the overlay.

## What v1.1.3 fixes

- The [Android 15 legacy effect ABI](https://android.googlesource.com/platform/hardware/libhardware/+/refs/heads/android15-release/include_all/hardware/audio_effect.h) expects the `AELI` symbol with the `AELT` tag, library API 3.0 and control API 2.0. Earlier Clarifae source used the wrong tag and control version.
- The module builds with the public Android NDK property API. Each effect session checks its own live settings and both framework and vendor effect hosts have a property prefix.
- The installer follows Android 15's legacy lookup order, with ODM and the vendor SKU-specific directory ahead of the generic vendor directory. It preserves existing XML effects and stages the library in the vendor sound effects directory when available.
- The module checks for an active AIDL effects factory at install time. AIDL factories require a different plugin ABI. On a detected AIDL device the installer stages diagnostic tools and skips legacy effect registration.
- The installer relies on the root manager's systemless mounts. Recent official KernelSU versions require a [mounting metamodule](https://kernelsu.org/guide/module.html) for modules that overlay system files. Visibility of a separate ODM partition also depends on the mount implementation.

## What v1.1.4 fixes

- RNNoise aligns the delayed processed signal with the original samples and uses a fixed queue so the result stays consistent across capture buffer sizes.
- The installer preserves legacy `.conf` routes and uses Android's `output_session_processing` section for playback.
- The module preserves empty routing selections, serializes settings writes, and reports when a saved setting could not be published to Android.
- The diagnostic reports settings in both property namespaces, the framework enable event, and actual PCM callbacks separately.

Android's recording thread [hands preprocessing to the audio HAL](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/android15-release/services/audioflinger/Threads.cpp). A mapped library and a `framework enabled: capture` log can appear on routes where the vendor HAL never sends PCM to Clarifae. Android may reject software preprocessing on fast and raw routes.

## Verify during an independent recording

1. Install the module ZIP through the root manager and reboot.
2. With the RNNoise package, turn off playback processing and set Info logging with `su -c 'sh /data/adb/clarifae/clarifae-ctl set loglevel 2'`.
3. Start a recording in Xiaomi Recorder or another unrelated app. Keep it recording while running:

   ```sh
   su -c 'sh /data/adb/modules/clarifae/scripts/diagnose-hyperos.sh'
   ```

4. With Stock Mic, check whether the staged XML is visible in the audio service's mount namespace and look for the stock effect in the live session. With RNNoise, a new `processed PCM: capture session=` entry confirms the session reached the Clarifae library.
5. Record matched clips with Clarifae OFF and ON, using the same app, input route, speech and background noise. Close and reopen the recorder between takes. Confirm the noise falls while speech remains clear. Repeat separately for VoIP, camera or Bluetooth if those routes matter.

Android associates default effects with recording sources. Apps that request unprocessed audio, and capture routes implemented below the Android effect chain, may behave differently. Leave noise suppression off by default for voice recognition as specified by [Android's preprocessing guidance](https://source.android.com/docs/core/audio/implement-pre-processing).

The diagnostic reads device state and logs. It neither records audio nor changes settings. If audio becomes unreliable, disable the module in the root manager and reboot.
