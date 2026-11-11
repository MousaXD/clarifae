#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/android" "$tmp/sys"
cat > "$tmp/android/log.h" <<'HEADER'
enum {ANDROID_LOG_ERROR, ANDROID_LOG_WARN, ANDROID_LOG_INFO, ANDROID_LOG_DEBUG, ANDROID_LOG_VERBOSE};
static inline int __android_log_print(int priority, const char* tag, const char* format, ...) {
    (void)priority; (void)tag; (void)format;
    return 0;
}
HEADER
cat > "$tmp/sys/system_properties.h" <<'HEADER'
#define PROP_VALUE_MAX 92
int __system_property_get(const char* name, char* value);
HEADER
rnn=native/third_party/rnnoise
sources=("$rnn"/src/{denoise,rnn,pitch,kiss_fft,celt_lpc,nnet,nnet_default,parse_lpcnet_weights,rnnoise_data,rnnoise_tables}.c)
flags=(-std=gnu11 -O2 -DRNNOISE_BUILD -I"$tmp" -Inative -Inative/include -I"$rnn/include" -I"$rnn/src")
common=(native/{ringbuf,resampler,backend_rnnoise,backend_dtln,backend_deepfilternet}.c)
"${CC:-cc}" "${flags[@]}" tests/test_rnnoise.c "${common[@]}" native/config.c \
    "${sources[@]}" tests/test_properties.c -lm -o "$tmp/rnnoise"
"$tmp/rnnoise"
"${CC:-cc}" "${flags[@]}" tests/test_effect_lifecycle.c "${common[@]}" native/{config,effect}.c \
    "${sources[@]}" tests/test_properties.c -lm -o "$tmp/effect"
"$tmp/effect"
