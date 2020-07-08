#!/usr/bin/env bash

#TODO: NOT DONE YET

declare SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"
source "${SCRIPT_DIR}/../include/functions.inc.sh"
source "${SCRIPT_DIR}/inc/plex.inc.sh"

declare PLEX_CURRENT_VERSION PLEX_LATEST_VERSION PLEX_LATEST_FILE

PLEX_CURRENT_VERSION PLE

PLEX_LATEST_GET PLEX_LATEST_VERSION PLEX_LATEST_FILE

[[ -z "${PLEX_LATEST_VERSION}" || -z "${PLEX_LATEST_FILE}" ]] && {
    echo "Could not get install version"
    exit 1
}

echo "Attempting to install: ${PLEX_LATEST_VERSION}"

PLEX_LATEST_INSTALL_FROM_URL "${PLEX_LATEST_FILE}"
