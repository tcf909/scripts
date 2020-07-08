#!/usr/bin/env bash
[[ "${DEBUG-}" == "true" ]] && set -x
set -u -o pipefail

NEW_FILE_SUFFIX=".new.${RANDOM}"

function HELP_SHOW() {
	echo "USAGE: ${0} [FILE]"
}

[[ -n "${2-}" ]] && { echo "ERROR: ONLY ONE ARGUMENT ALLOWED"; HELP_SHOW; exit 1; }

{ [[ -z "${1-}" ]] || [[ ! -f "${1-}" ]]; } && { echo "ERROR: (${1}) NOT A FILE"; exit 1; }

rsync -ahSDHAXW --no-compress --bwlimit=0 --stats "${1}" "${1}${NEW_FILE_SUFFIX}" && mv "${1}${NEW_FILE_SUFFIX}" "${1}"
