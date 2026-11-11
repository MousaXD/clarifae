#!/system/bin/sh
# Publish saved settings as soon as the root manager starts its late service.
MODDIR=${0%/*}
. "$MODDIR/common/functions.sh" || exit 1

with_config_lock prop_sync
