#!/usr/bin/env bash

set -o errtrace -o functrace

declare -a DEBUG_PREFIX=()

declare -a OUTPUT_PREFIX=()

function DEBUG_STACK () {

    local deptn=${#FUNCNAME[@]}

	echo "  STACK:"

    for ((i=1; i<$deptn; i++)); do

        local func="${FUNCNAME[$i]}"

        local src="${BASH_SOURCE[$i]}"

        local line="${BASH_LINENO[$((i - 1))]}"

        #printf '%*s' $i '' # indent

        echo "  -: $func(), $src, line $line"
    done
}

function DEBUG_DISABLE() {

	DEBUG=false

	return 0
}

function DEBUG_ENABLE() {

	DEBUG=true

	return 0
}

function DEBUG() {

	[[ "${DEBUG-}" != "true" ]] && return 0

	echo "${DEBUG_PREFIX[*]} ${*}"

	return 0
}

function DEBUG_PREFIX_ADD() {

    [[ -z "${1-}" ]] && THROW "MUST PROVIDE ONE ARGUMENT"

	# ADD THE PARAMS TO THE OUTPUT PREFIX
    DEBUG_PREFIX+=("$@")

    return 0
}

function DEBUG_PREFIX_REMOVE() {

	#REMOVE THE LAST OUTPUT PREFIX
	local LAST_INDEX=$(( ${#DEBUG_PREFIX[@]} - 1 ))

	DEBUG_PREFIX=("${DEBUG_PREFIX[@]:0:LAST_INDEX}")

	return 0
}

function DEBUG_PAUSE() {

	#Pauses if arg 1 is "true" OR DEBUG is "true" OR if set -x is being used
	[[ "${1-}" == "true" || "${DEBUG-}" == "true" || "${-/x/}" != "${-}" ]] && read -r -p "Press any key to resume ..."

	return 0
}

function DEBUG_TRACE_DISABLE() {

	set +x

	return 0
}

function DEBUG_TRACE_ENABLE() {

	#Only enables set -x if it is not enable and if we enable it, we do so twice so it will display in output
	[[ "${-/x/}" == "${-}" ]] && set -x && set -x

	return 0
}

function DEBUG_TRACE_ENABLE_IF() {

	[[ "${DEBUG-}" == "true" ]] && DEBUG_ENABLE

	return 0
}


function OUTPUT() {

	# shellcheck disable=SC2145
	echo "${OUTPUT_PREFIX[@]} ${@}"

	return 0
}


function OUTPUT_PREFIX_ADD() {

    [[ -z "${1-}" ]] && THROW "EXPECT \$1"

	# ADD THE PARAMS TO THE OUTPUT PREFIX
    OUTPUT_PREFIX+=("$@")

    return 0
}

function OUTPUT_PREFIX_REMOVE() {

	#REMOVE THE LAST OUTPUT PREFIX
	local LAST_INDEX=$(( ${#OUTPUT_PREFIX[@]} - 1 ))

	[[ "${LAST_INDEX}" == 0 ]] && OUTPUT "OUTPUT_PREFIX_REMOVE(): UNABLE TO REMOVE BASE PREFIX (${LAST_INDEX}). EXITING." && exit 1

	OUTPUT_PREFIX=("${OUTPUT_PREFIX[@]:0:LAST_INDEX}")

	return 0
}

function THROW() {

	echo "EXCEPTION: ${1-}"

	DEBUG_STACK

	exit 1
}

trap 'THROW' ERR
