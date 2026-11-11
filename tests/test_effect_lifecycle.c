#include <assert.h>
#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "audio_effect.h"
#include "clarifae_uuid.h"

extern audio_effect_library_t AELI;
extern int input_enabled;

static void command(effect_handle_t handle, uint32_t cmd, effect_config_t *config) {
    uint32_t length = sizeof(int);
    int status = -1;
    assert((*handle)->command(handle, cmd, config ? sizeof(*config) : 0,
                              config, &length, &status) == 0 && status == 0);
}

int main(void) {
    assert(AELI.tag == 0x41454c54 && AELI.version == 0x30000);
    effect_uuid_t uuid = CLARIFAE_IMPL_UUID;
    effect_descriptor_t desc;
    assert(AELI.get_descriptor(&uuid, &desc) == 0 && desc.apiVersion == 0x20000);
    assert((desc.flags & 7) == 3);

    effect_handle_t handles[2];
    effect_config_t config = {0};
    config.inputCfg.samplingRate = config.outputCfg.samplingRate = 16000;
    config.inputCfg.channels = config.outputCfg.channels = AUDIO_CHANNEL_IN_MONO;
    config.inputCfg.format = config.outputCfg.format = AUDIO_FORMAT_PCM_16_BIT;
    config.inputCfg.accessMode = EFFECT_BUFFER_ACCESS_READ;
    config.outputCfg.accessMode = EFFECT_BUFFER_ACCESS_WRITE;
    int16_t input[160], output[160];
    audio_buffer_t in = {.frameCount=160, .s16=input};
    audio_buffer_t out = {.frameCount=160, .s16=output};
    config.inputCfg.mask = config.outputCfg.mask = EFFECT_CONFIG_ALL;
    config.inputCfg.buffer = in;
    config.outputCfg.buffer = out;

    for (int i=0; i<2; i++) {
        assert(AELI.create_effect(&uuid, 20+i, 1, &handles[i]) == 0);
        command(handles[i], EFFECT_CMD_SET_CONFIG, &config);
    }

    uint32_t seed = 42;
    for (int i=0; i<160; i++) input[i] = i + 500;
    assert((*handles[0])->process(handles[0], NULL, NULL) == -ENODATA);
    assert(memcmp(input, output, sizeof(input)) == 0);
    for (int i=0; i<2; i++) command(handles[i], EFFECT_CMD_ENABLE, NULL);

    double energy_in=0, energy_out=0;
    for (int j=0; j<300; j++) {
        for (int i=0; i<160; i++) {
            seed = seed * 1664525u + 1013904223u;
            input[i] = (int16_t)((seed >> 21) - 1024);
        }
        for (int k=0; k<2; k++) {
            assert((*handles[k])->process(handles[k], &in, &out) == 0);
            if (j >= 100) for (int i=0; i<160; i++) {
                energy_in += input[i]*(double)input[i];
                energy_out += output[i]*(double)output[i];
            }
        }
    }
    assert(energy_out < energy_in);
    printf("Two 16 kHz capture sessions reduced synthetic noise by %.1f dB\n", 10*log10(energy_in/energy_out));
    input_enabled = 0;
    for (int j=0; j<26; j++) for (int i=0; i<2; i++) {
        assert((*handles[i])->process(handles[i], &in, &out) == 0);
        if (j==25) assert(memcmp(input, output, sizeof(input)) == 0);
    }
    for (int i=0; i<2; i++) {
        command(handles[i], EFFECT_CMD_DISABLE, NULL);
        assert((*handles[i])->process(handles[i], &in, &out) == -ENODATA);
        assert(AELI.release_effect(handles[i]) == 0);
    }
    puts("Verified independent toggles and framework disable");
}
