#!/usr/bin/env bash

function IS_AVAILABLE(){

	[[ -z "${1-}" ]] && {
		echo "EXPECT \$1. EXITING (1)."
		exit 1
	}

	if hash "${1}" &> /dev/null; then
		return 0
	else
		return 1
	fi
}

declare -a CATEGORIES=()

while getopts vhc: OPT; do
	case ${OPT} in
		v)
			echo "${0} version 1.0.0"
			exit 0
			;;
		h)
			HELP_SHOW
			exit 0
			;;
		c)
			! [[ "${OPT}" =~ ^(k8|pipe|plex|ssh|sync|zfs)$ ]] && {
				echo "Invalid category (${OPT}). Exiting (1)."
				exit 1
			}
			CATEGORIES+=("${OPT}")
			;;
		*)
			HELP_SHOW >&2
			exit 1
			;;
	esac
done

[[ "${#CATEGORIES[@]}" == "0" ]] && {
	CATEGORIES=("k8" "pipe" "plex" "ssh" "sync" "zfs")
}

shift "$((OPTIND - 1))" # Shift off the options and optional --.

mkdir -p /usr/local/scripts

declare -a INCLUDES=('scripts-master/inc/general.inc')

for CATEGORY in "${CATEGORIES[@]}"; do
	INCLUDES+=("scripts-master/${CATEGORY}/*")
	INCLUDES+=("scripts-master/inc/${CATEGORY}.inc'")
done

# shellcheck disable=SC2016
curl -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' https://codeload.github.com/tcf909/scripts/tar.gz/master | \
	tar -zxv --strip-component=1 -C /usr/local/scripts --wildcards "${INCLUDES[*]}"





