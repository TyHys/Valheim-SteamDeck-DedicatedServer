#!/bin/sh
# SERVER_NAME, WORLD_NAME, SERVER_PASS, and SERVER_PUBLIC must be provided via environment variables.
# SERVER_CROSSPLAY (optional, "1"/"0") enables the -crossplay flag, opening the server to
# PlayStation/Switch/Xbox players via PlayFab matchmaking in addition to Steam.

set -- -name "${SERVER_NAME}" -world "${WORLD_NAME}" -password "${SERVER_PASS}" -public "${SERVER_PUBLIC}" -savedir "${VALHEIM_SAVE_PATH}"

if [ "${SERVER_CROSSPLAY}" = "1" ]; then
    set -- "$@" -crossplay
fi

exec ./valheim_server.x86_64 "$@"
