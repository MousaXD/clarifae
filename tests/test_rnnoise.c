#include "backend.h"
#include "rnnoise.h"

#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum { FRAME = 480, SAMPLE_COUNT = 12000, PIPE_DELAY = 482 };

static int16_t samples[SAMPLE_COUNT];
static float regular[SAMPLE_COUNT], variable[SAMPLE_COUNT];

static void run(void* state, float* output, int step) {
    const clarifae_backend_t* backend = clarifae_backend_rnnoise();
    for (int i = 0; i < SAMPLE_COUNT; ++i) output[i] = samples[i];
    for (int i = 0; i < SAMPLE_COUNT;) {
        int n = step ? step : 1 + (i % 1301);
        if (n > SAMPLE_COUNT - i) n = SAMPLE_COUNT - i;
        assert(backend->process(state, output + i, n) == 0);
        i += n;
    }
}

int main(void) {
    uint32_t noise = 42;
    for (int i = 0; i < SAMPLE_COUNT; ++i) {
        noise = noise * 1664525u + 1013904223u;
        samples[i] = (int16_t)((int)(noise >> 21) - 1024);
    }
    const clarifae_backend_t* backend = clarifae_backend_rnnoise();
    int rates[] = {8000, 16000, 44100, 48000, 96000, 192000};
    for (size_t i = 0; i < sizeof(rates) / sizeof(rates[0]); ++i) {
        char error[160];
        void* state = backend->create(rates[i], 1, error, sizeof(error));
        assert(state);
        backend->set_params(state, 0.7f, 24.0f, 0.5f, 0, 0);
        run(state, regular, 16);
        backend->reset(state);
        run(state, variable, 0);
        for (int n = 0; n < SAMPLE_COUNT; ++n) {
            assert(fabsf(regular[n] - variable[n]) < 0.001f);
        }
        printf("%d Hz: consistent across recording callback sizes\n", rates[i]);

        if (rates[i] == 48000) {
            DenoiseState* reference = rnnoise_create(NULL);
            assert(reference);
            float input[FRAME], wet[FRAME];
            for (int offset = 0; offset + FRAME + PIPE_DELAY < SAMPLE_COUNT; offset += FRAME) {
                for (int n = 0; n < FRAME; ++n) input[n] = samples[offset + n];
                rnnoise_process_frame(reference, wet, input);
                for (int n = 0; n < FRAME; ++n) {
                    int dry_index = offset + n - 2 * FRAME;
                    float dry = dry_index >= 0 ? samples[dry_index] : 0;
                    float limit = (1.0f - powf(10.0f, -24.0f / 20.0f)) * fabsf(dry);
                    float removed = fmaxf(-limit, fminf(limit, (dry - wet[n]) * 0.7f));
                    assert(fabsf(variable[offset + n + PIPE_DELAY] - (dry - removed)) < 0.001f);
                }
            }
            rnnoise_destroy(reference);
            puts("48 kHz: wet and dry samples match the RNNoise reference delay");
        }
        backend->destroy(state);
    }
    return 0;
}
