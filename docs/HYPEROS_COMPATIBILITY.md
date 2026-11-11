# HyperOS 2 / POCO X7 Pro compatibility investigation

## Current status: NOT FIXED OR DEVICE-VERIFIED

Clarifae's installer patches the **first** existing audio-effects configuration it finds. This is not proof that Android 15's running audio service consumes that file. The installer also reports success when an overlay was merely staged. On devices with vendor AIDL effects or a separate audio-effects service, a legacy `AELI` effect may not load.

AOSP defines microphone preprocessing per capture source in audio policy. Android 15's audio effect framework may be implemented through vendor-specific HAL/service paths. Do not disable Xiaomi's stock noise suppression or replace stock vendor libraries to force attachment.

## Read-only diagnostic

From a root shell in the checked-out repository run:

```sh
su -c 'sh /path/to/clarifae/scripts/diagnose-hyperos.sh'
```

Start a real recording in a separate app **before** running the diagnostic, and keep it active while collecting AudioFlinger information. The script does not record or upload audio. Inspect output for personal information before sharing.

### Interpreting results

- Overlay staged but no Clarifae entry in the live effect chain: installation success is misleading; verify the config selected by the actual audio service.
- Effect registered but no instance on a live MIC/VOICE_COMMUNICATION capture: capture-source routing/attachment issue.
- Effect instance present, but no backend activation log: check native library ABI, SELinux denials, effect lifecycle and backend initialization.
- Instance and backend active, but unchanged WAV in independent test: verify processing counters and A/B signal metrics; a WebUI toggle alone is insufficient.

Do not flash an experimental vendor overlay until exact firmware paths and loader architecture are confirmed. Never replace Xiaomi audio HAL binaries or disable SELinux as a workaround.

## Acceptance criteria

1. Correct loader/config identified on exact POCO X7 Pro HyperOS 2 firmware.
2. Root module installation and removal preserve stock configuration.
3. Actual recording session reports Clarifae effect instance.
4. Native effect processing is measurable without relying on the WebUI.
5. Independent APK and unrelated recorder demonstrate matched-condition OFF/ON difference.
6. Calls, Bluetooth routing, playback, battery and reboot regression checks pass.
