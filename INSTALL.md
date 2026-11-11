# Installing & building Clarifae

## 1. Prerequisites

| For | You need |
|---|---|
| Flashing only | Magisk ≥ 24.0, KernelSU with working systemless mounts, or APatch on a rooted device |
| WebUI on Magisk | the [MMRL](https://github.com/MMRLApp/MMRL) app (KernelSU/APatch have it built in) |
| Building | Android NDK r27+, CMake ≥ 3.18, `git`, `zip`, network access |

Set the NDK location if it isn't auto-detected:

```bash
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/28.2.13676358
```

## 2. Build the native effect (RNNoise — the default engine)

```bash
# run from the project folder
./scripts/fetch_deps.sh        # prepares native/third_party/rnnoise (source + weights)
./build.sh                     # builds libclarifae.so for arm64-v8a, armeabi-v7a, x86_64
```

> **Recommended (reliable): use a RNNoise release tarball.** `media.xiph.org`'s
> model download can be very slow/flaky. To skip it entirely, download a release
> tarball from <https://github.com/xiph/rnnoise/releases> (e.g. `rnnoise-0.2.tar.gz`)
> and drop it in the project folder. `fetch_deps.sh` detects `rnnoise-*.tar.gz`,
> uses it as the source (the weights are bundled), and adds the small `os_support.h`
> shim the release omits — no network needed. Otherwise it falls back to
> `git clone` + a **resumable, checksum-verified** weights download.

`build.sh` stages `lib/<abi>/libclarifae.so` for each ABI. The installer
stages the library into the device's sound effects directory at flash time.

Build a subset of ABIs:

```bash
ABIS="arm64-v8a" ./build.sh
```

> The trained weights (`rnnoise_data.c`) are downloaded by `fetch_deps.sh`, **not**
> committed. If your network blocks `media.xiph.org`, run RNNoise's `download_model.sh`
> manually inside `native/third_party/rnnoise`, or build RNNoise's autotools target once
> to generate the weights, then re-run `./build.sh`.

## 3. (Optional) Build the experimental backends

### DTLN (mode 2, TensorFlow Lite)

```bash
./scripts/fetch_models.sh                       # stages model_1/2.tflite into models/dtln/
CLARIFAE_WITH_DTLN=ON TFLITE_DIR=/path/to/tflite-c ./build.sh
```

`TFLITE_DIR` must contain `tensorflow/lite/c/c_api.h` and `libtensorflowlite_c.so`
(Android build of the TFLite C API). Models are loaded at runtime from
`/data/adb/clarifae/models/dtln/` (copied there from `models/` on flash).

### DeepFilterNet (mode 3, libdf)

1. Cross-compile **libdf** (DeepFilterNet's C-FFI) for your Android ABIs (e.g. with
   `cargo-ndk` from the DeepFilterNet `ladspa`/capi crate).
2. Put the exported model at `models/df/DeepFilterNet3_onnx.tar.gz`.
3. Build:

```bash
CLARIFAE_WITH_DF=ON DF_DIR=/path/to/libdf ./build.sh
```

If the symbol names from your `libdf` build differ, adjust the `extern` block in
`native/backend_deepfilternet.c`.

## 4. Package the flashable zip

```bash
./scripts/package.sh           # -> dist/clarifae-<version>.zip
```

The ZIP contains the module scripts, the prebuilt `lib/<abi>/libclarifae.so`
files, WebUI, on-device diagnostic, and any staged models.

## 5. Flash & enable

1. Flash `dist/clarifae-<version>.zip` in Magisk / KernelSU / APatch.
2. **Reboot.**
3. Open the WebUI:
   - **KernelSU / APatch:** Modules → *Clarifae* → **Open**.
   - **Magisk:** open **MMRL** → Clarifae → WebUI.
4. Toggle Clarifae **on** and pick a clarity mode (default = RNNoise).

## 6. Verify capture processing

Start a recording in an unrelated recorder app and follow the
[HyperOS verification steps](docs/HYPEROS_COMPATIBILITY.md).
