# Clarifae Mic Test (independent APK)

This is a **separate Android application and process**, not a Clarifae WebUI preview or an internal DSP loopback. It records through Android AudioRecord and never calls Clarifae's denoiser itself.

## Verification protocol

1. Install the root module, reboot, and install this APK.
2. Disable Clarifae microphone processing in the module UI. Force-stop and reopen this test app. Record the same spoken phrase with the same background noise and selected Android capture source.
3. Enable Clarifae microphone processing. Force-stop and reopen this test app, then repeat under matched conditions.
4. Compare exported WAV files on another device or in an independent editor, blinded if possible.
5. Repeat in **another unrelated application** (e.g. the phone's stock recorder, Discord, or a VoIP app). An improvement only in this APK is **not** proof of system-wide coverage.
6. Repeat for MIC, VOICE_COMMUNICATION, CAMCORDER, and VOICE_RECOGNITION. Results can differ by source and OEM routing.

The APK has no INTERNET permission, no analytics SDK, and does not request root. It cannot assert that the module was attached; only real cross-app recordings and device-level audio-effect inspection can establish that.

## Build

Open `android-companion` in Android Studio, or with Android SDK and JDK 17 run `gradle :app:assembleDebug`. CI builds the debug APK and uploads it as a workflow artifact. This project intentionally does not contain a Gradle wrapper JAR; CI uses a pinned Gradle distribution.
