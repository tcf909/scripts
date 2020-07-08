#!/bin/bash

set -o nounset -o errexit -o pipefail

declare SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

source "${SCRIPT_DIR}/inc/functions.inc.sh"

[[ -z "${1-}" ]] && THROW "USAGE: ${0} private_key_path [private_key_password]"

ssh-keygen -q -N "${2-}" -C "" -f "${1}"
