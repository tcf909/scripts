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

shift "$((OPTIND - 1))" # Shift off the options and optional --.

curl -L https://github.com/tcf909/scripts/archive/master.tar.gz | tar -zxv --strip-component=1 -C /tmp -



