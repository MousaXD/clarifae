#include <string.h>

int input_enabled = 1;

int __system_property_get(const char* name, char* value) {
    if (strcmp(name, "persist.vendor.clarifae.enabled") == 0) value[0] = '1';
    else if (strcmp(name, "persist.vendor.clarifae.in_enabled") == 0) value[0] = '0' + input_enabled;
    else return 0;
    value[1] = '\0';
    return 1;
}
