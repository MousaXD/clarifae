/*
 * config.c — read persist.clarifae.* system properties into clarifae_config_t,
 * for both framework and vendor effect hosts.
 */
#include "config.h"
#include "log.h"

#include <sys/system_properties.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

atomic_int clarifae_log_level = 1;

/* Legacy audio effects can run in a vendor HAL process. Publish the same
 * settings under a vendor property prefix for that process. */
static int get_property(const char* key, char* value) {
    char name[64];
    snprintf(name, sizeof(name), "persist.vendor.clarifae.%s", key);
    int n = __system_property_get(name, value);
    if (n > 0) return n;
    snprintf(name, sizeof(name), "persist.clarifae.%s", key);
    return __system_property_get(name, value);
}

static int get_str(const char* name, char* out, int outlen, const char* def) {
    char buf[PROP_VALUE_MAX];
    int n = get_property(name, buf);
    const char* src = (n > 0) ? buf : def;
    strncpy(out, src, (size_t)outlen - 1);
    out[outlen - 1] = '\0';
    return n > 0;
}

static int get_int(const char* name, int def, int lo, int hi) {
    char buf[PROP_VALUE_MAX];
    if (get_property(name, buf) <= 0) return def;
    char* end = NULL;
    long v = strtol(buf, &end, 10);
    if (end == buf) return def;       /* not a number -> default */
    if (v < lo) v = lo;
    if (v > hi) v = hi;
    return (int)v;
}

void clarifae_config_load(clarifae_config_t* cfg) {
    memset(cfg, 0, sizeof(*cfg));
    cfg->enabled      = get_int("enabled",      1, 0, 1);
    cfg->in_enabled   = get_int("in_enabled",   1, 0, 1);
    cfg->out_enabled  = get_int("out_enabled",  1, 0, 1);
    cfg->mode         = get_int("mode",         1, 1, 3);
    cfg->strength     = get_int("strength",     70, 0, 100);
    cfg->out_strength = get_int("out_strength", 60, 0, 100);
    cfg->atten_db     = get_int("atten_db",     24, 0, 60);
    cfg->vad          = get_int("vad",          50, 0, 100);
    cfg->highpass     = get_int("highpass",     1, 0, 1);
    cfg->autogain     = get_int("autogain",     0, 0, 1);
    cfg->loglevel     = get_int("loglevel",     1, 0, 3);
    get_str("targets", cfg->targets, (int)sizeof(cfg->targets),
            "mic,voice_comm");
    get_str("out_targets", cfg->out_targets, (int)sizeof(cfg->out_targets),
            "music,voice_call");
    atomic_store_explicit(&clarifae_log_level, cfg->loglevel, memory_order_relaxed);
}
