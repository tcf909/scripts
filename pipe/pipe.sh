#!/usr/bin/env bash
[[ "${DEBUG-}" == "true" ]] && set -x
set -e -u -o pipefail

declare SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

declare QITEM=""
declare -a QITEMS=()
declare -A QUEUE=()
declare -A QUEUE_RUNNING=()
declare QUEUE_UPDATED=false
declare -A LOCK_READ_HANDLES=()
declare -A LOCK_READ_HANDLE_COUNTS=()
declare -A LOCK_WRITE_HANDLES=()
declare -A LOCK_WRITE_HANDLE_COUNTS=()
declare PIPE_TMP_DIR="${PIPE_TMP_DIR:-/var/spool/pipe}"
declare PIPE_OUTPUT_CMD_LOG="${PIPE_OUTPUT_CMD_LOG:-true}"
declare PIPE_OUTPUT_CMD_LOG_REALTIME="${PIPE_OUTPUT_CMD_LOG_REALTIME:-false}"
declare PIPE_QUEUE_IFS=${PIPE_QUEUE_IFS:-$'\n\t'}
declare -i PIPE_MAX_FAILED=0
declare -i PIPE_MAX_FAILED_PER_QITEM=0
declare -i PIPE_MAX_THREADS=${PIPE_MAX_THREADS:-1}
declare -i FAILED=0

trap "QUIT" INT

trap "QUIT_FORCE" TERM

source "${SCRIPT_DIR}/inc/functions.inc.sh"

OUTPUT_PREFIX_ADD "PIPE():"

function HELP_SHOW() {

	echo "USAGE: echo \"item\" | ${0} [-v] [-h] [-t MAX_THREADS] [CMD_TO_RUN]"

	echo "CMD_TO_RUN Example: ./script.sh static_arg1 {}"

	echo " Use \"{}\" as a placeholder for the item passed to pipe."

	return 0
}


function LOCK_READ(){

	{ [[ -z "${1-}" ]] || [[ ! -f "${1}" ]]; } && THROW "(${1}) MUST BE A FILE PATH"

	if [[ -n  "${LOCK_READ_HANDLES["${1}"]}" ]]; then

		((++LOCK_READ_HANDLE_COUNTS[${1}]))

		OUTPUT "READ LOCK INCREMENTED (${1})"

		return 0

	fi

	local HANDLE_INT=$(( 100 + (${RANDOM} % (1024 - 100 + 1))))

	while eval ">&${HANDLE_INT}" 2> /dev/null; do
		HANDLE_INT=$(( 100 + (${RANDOM} % (1024 - 100 + 1))))
	done

	eval "exec ${HANDLE_INT}> \"${1}\"" || return 1

	flock -sn ${HANDLE_INT} || { eval "exec ${HANDLE_INT}>&-"; return 1; }

	LOCK_READ_HANDLES["${1}"]=${HANDLE_INT}

	LOCK_READ_HANDLE_COUNTS["${1}"]=1

	OUTPUT "READ LOCK ESTABLISHED (${1-}) (${HANDLE_INT})"

	return 0
}

function LOCK_READ_REMOVE() {

	[[ -z "${1-}" ]] && THROW "(${1}) MUST BE A FILE PATH"

	[[ -z "${LOCK_READ_HANDLES["${1}"]}" ]] && return 0

	if [[ "${LOCK_READ_HANDLE_COUNTS["${1}"]}" == 1 ]]; then

		#check to see if fd is active
		#>&100 2> /dev/null || return 0

		flock -u "${LOCK_READ_HANDLES["${1}"]}"

		eval "exec ${LOCK_READ_HANDLES["${1}"]}>&-"

		unset 'LOCK_READ_HANDLES[${1}]'

		unset 'LOCK_READ_HANDLE_COUNTS[${1}]'

		OUTPUT "READ LOCK REMOVED (${1})"

	else

		((--LOCK_READ_HANDLE_COUNTS[${1}]))

		OUTPUT "READ LOCK DECREMENTED (${1})"

	fi

	return 0
}

function LOCK_WRITE(){

	{ [[ -z "${1-}" ]] || [[ ! -f "${1-}" ]]; } && THROW "(${1}) MUST BE A FILE PATH"

	if [[ -n "${LOCK_WRITE_HANDLES["${1}"]-}" ]]; then

		((++LOCK_WRITE_HANDLE_COUNTS[${1}]))

		OUTPUT "WRITE LOCK INCREMENTED (${1})"

		return 0

	fi

	local HANDLE_INT=$(( 100 + (${RANDOM} % (1024 - 100 + 1))))

	while eval ">&${HANDLE_INT}" 2> /dev/null; do
		HANDLE_INT=$(( 100 + (${RANDOM} % (1024 - 100 + 1))))
	done

	eval "exec ${HANDLE_INT}> \"${1}\"" || return 1

	flock -xn ${HANDLE_INT} || { eval "exec ${HANDLE_INT}>&-"; return 1; }

	LOCK_WRITE_HANDLES["${1}"]=${HANDLE_INT}

	LOCK_WRITE_HANDLE_COUNTS["${1}"]=1

	OUTPUT "WRITE LOCK ESTABLISHED (${1-})"

	return 0
}

function LOCK_WRITE_REMOVE() {

	[[ -z "${1-}" ]] && THROW "(${1}) MUST BE A FILE PATH";

	[[ -z "${LOCK_WRITE_HANDLES[${1}]-}" ]] && return 0

	if [[ ${LOCK_WRITE_HANDLE_COUNTS[${1}]-} == 1 ]]; then

		#check to see if fd is active
		#>&100 2> /dev/null || return 0

		flock -u "${LOCK_WRITE_HANDLES["${1}"]}"

		eval "exec ${LOCK_WRITE_HANDLES["${1}"]}>&-"

		unset 'LOCK_WRITE_HANDLES[${1}]'

		unset 'LOCK_WRITE_HANDLE_COUNTS[${1}]'

		OUTPUT "WRITE LOCK REMOVED (${1})"

	else

		((--LOCK_READ_HANDLE_COUNTS[${1}]))

		OUTPUT "WRITE LOCK DECREMENTED (${1})"

	fi

	return 0
}

function QUEUE_FAILED_PUSH() {

	[[ -z "${1-}" ]] && THROW "EXPECT \$1"

	echo "${1}" >> "${QUEUE_FAILED_FILE}"

	return 0
}

function QUEUE_PUSH() {

	[[ -z "${1-}" ]] && THROW "EXPECT \$1"

	if [[ -v 'QUEUE[${1}]' ]]; then

		OUTPUT "QUEUE_PUSH(): IGNORING DUPLICATE (${1})"

		return 1
	else

		OUTPUT "QUEUE_PUSH(): ADDING ITEM (${1})"

		QUEUE["${1}"]=

		QUEUE_UPDATED=true

		return 0
	fi
}

function QUEUE_READ() {

	declare -g -A QUEUE=()

	local QUEUE_APPEND

	local QITEM

	OUTPUT_PREFIX_ADD "QUEUE_READ():"

	if [[ -f "${QUEUE_FILE}" ]]; then

		OUTPUT "READING QUEUE FROM (${QUEUE_FILE})"

		DEBUG_TRACE_DISABLE

		# shellcheck disable=SC1090
		source -- "${QUEUE_FILE}"

		DEBUG_TRACE_ENABLE_IF
	fi

	if [[ -n "${QUEUE_APPEND_FILE}" ]] && [[ -f "${QUEUE_APPEND_FILE}" ]]; then

 		OUTPUT "READING APPEND QUEUE FROM (${QUEUE_APPEND_FILE})"

		LOCK_WRITE "${QUEUE_APPEND_FILE}" || { OUTPUT "UNABLE TO LOCK APPEND FILE FOR WRITING"; exit 1; }

		while IFS=$"${PIPE_QUEUE_IFS}" read -r -t 1 QITEM; do

			[[ -z "${QITEM}" ]] && continue

			QUEUE_PUSH "${QITEM}"
		done < "${QUEUE_APPEND_FILE}"

		rm "${QUEUE_APPEND_FILE}"

		LOCK_WRITE_REMOVE "${QUEUE_APPEND_FILE}"

		QUEUE_WRITE

	fi

	OUTPUT "READ (${#QUEUE[@]}) ITEMS FROM DISK"

	OUTPUT_PREFIX_REMOVE

	return 0
}

function QUEUE_UNSET() {

	[[ -z "${1-}" ]] && { OUTPUT "ERROR: \$1 CAN NOT BE NULL"; exit 1; }

	OUTPUT_PREFIX_ADD "QUEUE_UNSET():"

	if [[ -v 'QUEUE[${1}]' ]]; then

		OUTPUT "ITEM (${1}) FOUND - REMOVING"

		unset 'QUEUE[${1}]'

		QUEUE_UPDATED=true

		OUTPUT_PREFIX_REMOVE

		return 0
	else

		OUTPUT "ITEM (${1}) NOT FOUND"

		OUTPUT_PREFIX_REMOVE

		return 1
	fi
}

function QUEUE_SHIFT() {

	#SET QITEM TO BE CONSUMED BY CALLER
	for QITEM in "${!QUEUE[@]}"; do

		QUEUE_REMOVE "${QITEM}"

		return 0
	done

	return 1
}

function QUEUE_UNSHIFT() {

	[[ -z "${1-}" ]] && THROW "EXPECT \$1"

	[[ -v 'QUEUE[$1]' ]] && return 1

	"QUEUE[${1}]"="${1}"

	QUEUE_UPDATED=true

	return 0
}

function QUEUE_WRITE() {

	[[ "${QUEUE_UPDATED}" != "true" ]] && return 0

	OUTPUT_PREFIX_ADD "QUEUE_WRITE():"

	if [[ "${#QUEUE[@]}" -eq 0 ]]; then

		OUTPUT "REMOVING QUEUE FILE"

		[[ -f "${QUEUE_FILE}" ]] && rm "${QUEUE_FILE}"
	else

		OUTPUT "WRITING QUEUE FILE WITH (${#QUEUE[@]}) ITEMS"

		#Make sure we add the global flag to the declare command
		declare -p QUEUE | sed 's/declare/declare -g/' > "${QUEUE_FILE}"
	fi

	OUTPUT "SETTING QUEUE_UPDATED=false"

	QUEUE_UPDATED=false

	OUTPUT_PREFIX_REMOVE

	return 0
}

function QUIT() {

	# A second ctrl-c will force a quit
	trap "QUIT_FORCE" INT

	RUN_STOP_ALL

	LOCK_WRITE_REMOVE "${PIPE_FILE}"

	exit ${1-}
}

function QUIT_FORCE() {

	trap 'echo "Already quiting..."' INT TERM

	RUN_STOP_ALL "true"

	LOCK_WRITE_REMOVE "${PIPE_FILE}"

	exit ${1-}
}

function RUN() {

	[[ -z "${1-}" ]] && THROW "EXPECT \$1"

	local QITEM="${1}"

	local CMD_ACTUAL=${CMD/\{\}/${QITEM-}}

	local PID

	OUTPUT_PREFIX_ADD "RUN(${QITEM}):"

	(

		trap : INT TERM

		# GETS THE PID OF THE SUBSHELL (MAKE SURE TO INCLUDE "exec" OR BASH DOES SOME FUNKY THINGS THAT MESS THIS UP)
		# https://unix.stackexchange.com/questions/484442/how-can-i-get-the-pid-of-a-subshell#comment1041670_484464
		# shellcheck disable=SC2016
		PID=$(exec sh -c 'echo $PPID')

		STATUS_PATH="${PIPE_TMP_DIR}/${PID}${STATUS_SUFFIX}"

		LOG_PATH="${PIPE_TMP_DIR}/${PID}${LOG_SUFFIX}"

		OUTPUT_PREFIX_ADD "JOB (${PID}) "

		OUTPUT "STARTING"

		#We set the status at 129 initially so we are re-queued if for some reason we do not finish and update the status
		echo "" > "${STATUS_PATH}"

		touch "${LOG_PATH}"

		if [[ "${PIPE_OUTPUT_CMD_LOG_REALTIME-}" == "true" ]]; then
			( eval "trap 'echo INT or TERM received; exit 129' INT TERM; ${CMD_ACTUAL}" 2>&1 |
				tee "${LOG_PATH}" | while read -r LINE; do
					OUTPUT "CMD OUTPUT: ${LINE}"
					done )
		else
			( eval "trap 'echo INT or TERM received; exit 129' INT TERM; ${CMD_ACTUAL};" 1> "${LOG_PATH}" 2>&1 )
		fi

		STATUS="${PIPESTATUS[0]}"

		echo "${STATUS}" > "${STATUS_PATH}"

		#OUTPUT "COMPLETE. STATUS (${STATUS})."
	) &

	#save pid of background job
	PID="$!"

	#fail if for some reason the pid couldn't be realized
	[[ -z "${PID-}" ]] && THROW "COULD NOT DETERMINE PID"

	#add pid to associative array with QITEM as key
	QUEUE_RUNNING["${QITEM}"]="${PID}"

	OUTPUT_PREFIX_REMOVE

	return 0
}

function RUN_KILL() {

	local PID="${1}"

	# shellcheck disable=SC2155
	local CHILDREN="$(ps --ppid "${PID}" -o pid --noheaders)"

	[[ -n "${CHILDREN-}" ]] && for CHILD in ${CHILDREN}; do

		ps -p "${CHILD}" &> /dev/null && RUN_KILL "${CHILD}"

	done

	kill -9 "${PID}" &> /dev/null

	return 0
}

function RUN_WAITFORANY() {

	local PID=

	echo "WAITING FOR A JOB TO COMPLETE (${QUEUE_RUNNING[*]-})..."

	while [[ -n "${QUEUE_RUNNING[*]-}" ]]; do

		for PID in "${QUEUE_RUNNING[@]-}"; do

			ps -p ${PID} > /dev/null || break 2

		done

		sleep 1

	done

	return 0

}

function RUN_STOP_ALL() {

	local FORCE="${1:-false}"

	OUTPUT_PREFIX_ADD "RUN_STOP_ALL():"

	OUTPUT "STOPPING JOBS"

	while [[ -n "${QUEUE_RUNNING[*]-}" ]]; do

		RUN_CHECK

		for QITEM in "${!QUEUE_RUNNING[@]}"; do

			PID="${QUEUE_RUNNING["${QITEM}"]}"

			OUTPUT "(${QITEM}) JOB (${PID}) STOPPING..."

			if [[ "${FORCE-}" == "true" ]]; then
				RUN_KILL ${PID} || true
			else
				kill ${PID} || true
			fi
		done

		RUN_CHECK

		[[ -n "${QUEUE_RUNNING[*]-}" ]] && sleep 5

	done

	OUTPUT "STOPPING JOBS DONE"

	OUTPUT_PREFIX_REMOVE
}

function RUN_CHECK() {

	local FAILED_COUNT=

	local PID_COUNT=

	local PID=

	local JOB_STATUS=

	local QITEM=

	OUTPUT_PREFIX_ADD "RUN_CHECK():"

	#Go through all jobs and see if they completed
	for QITEM in "${!QUEUE_RUNNING[@]}"; do

		PID="${QUEUE_RUNNING["${QITEM}"]}"

		## IF the pid is still running, skip processing a running job
		ps -p ${PID} > /dev/null && continue

		STATUS_PATH="${PIPE_TMP_DIR}/${PID}${STATUS_SUFFIX}"

		LOG_PATH="${PIPE_TMP_DIR}/${PID}${LOG_SUFFIX}"

		OUTPUT_PREFIX_ADD "QITEM (${QITEM}):"

		OUTPUT "PROCESSING RESULTS..."

		read -r JOB_STATUS < "${STATUS_PATH}" || THROW "UNABLE TO READ STATUS_PATH (${STATUS_PATH})"

		[[ -z "${JOB_STATUS}" ]] && JOB_STATUS=128

		OUTPUT "STATUS (${JOB_STATUS})"

		if [[ "${JOB_STATUS}" != "0" ]]; then

			# shellcheck disable=SC2004
			if ((${JOB_STATUS} > 128)); then

				OUTPUT "JOB DID NOT EXIT ON ITS OWN. LEAVING IN QUEUE TO TRY AGAIN."

			else

				[[ "${PIPE_OUTPUT_CMD_LOG_REALTIME}" != "true" ]] && OUTPUT "JOB OUTPUT: $(cat "${LOG_PATH}" | sed 's/^/  /')"

				#Increment item failed count
				QUEUE_FAILED["${QITEM}"]=$((${QUEUE_FAILED["${QITEM}"]:-0} + 1))

				OUTPUT "INCREMENTED ITEM FAIL COUNT (${QUEUE_FAILED["${QITEM}"]})"

				if (( ${QUEUE_FAILED["${QITEM}"]} >= ${PIPE_MAX_FAILED_PER_QITEM})); then

					OUTPUT "ITEM EXCEEDED MAX FAILURES (${PIPE_MAX_FAILED_PER_QITEM}). NOT RETURNING TO QUEUE."

					QUEUE_UNSET "${QITEM}"

					QUEUE_FAILED_PUSH "${QITEM}"

					((++FAILED))

					if (( ${FAILED} > 0 )); then

						if (( ${FAILED} >= ${PIPE_MAX_FAILED} )); then

							OUTPUT "EXCEEDED MAX FAILED (${PIPE_MAX_FAILED}). EXITING."

							QUIT 1
						fi

						#echo "FAILED COUNT (${FAILED}), THROTTLING FOR $((2 ** ${FAILED})) SECONDS"; sleep "$((2 ** ${FAILED}))" &
						#wait $!
					fi

				else

					OUTPUT "WILL RETRY"
				fi
			fi
		else

			#We do not output the log at the end if the realtime log is enabled
			if [[ "${PIPE_OUTPUT_CMD_LOG_REALTIME}" != "true" ]] && [[ "${PIPE_OUTPUT_CMD_LOG-}" == "true" ]]; then
				OUTPUT "JOB OUTPUT: $(cat "${LOG_PATH}" | sed 's/^/  /')"
			fi

			QUEUE_UNSET "${QITEM}"

		fi

		OUTPUT "CLEANING TEMP FILES..."

		[[ -e ${STATUS_PATH} ]] && rm "${STATUS_PATH}"

		[[ -e ${LOG_PATH} ]] && rm "${LOG_PATH}"

		unset 'QUEUE_RUNNING[${QITEM}]' || exit 1

		OUTPUT "REMOVED FROM ACTIVE JOBS LIST"

		OUTPUT_PREFIX_REMOVE

	done

	QUEUE_WRITE

	OUTPUT_PREFIX_REMOVE
}

while getopts hvt: opt; do
	case $opt in
		h)
			HELP_SHOW
			exit 0
			;;
		d)
			DEBUG=TRUE
			;;
		t)
			echo "SETTING MAX THREADS (${OPTARG})"
			PIPE_MAX_THREADS="$OPTARG"
			;;
		*)
			HELP_SHOW >&2
			exit 1
			;;
	esac
done

shift "$((OPTIND - 1))" # Shift off the options and optional --.



# shellcheck disable=SC2124
CMD=${*}

CMD_MD5="$(printf '%s' "${CMD}" | md5sum | awk '{print $1}')"

QUEUE_FILE="${PIPE_TMP_DIR}/${CMD_MD5}.queue"
QUEUE_APPEND_FILE="${PIPE_TMP_DIR}/${CMD_MD5}.append"
QUEUE_FAILED_FILE="${PIPE_TMP_DIR}/${CMD_MD5}.failed"
PIPE_FILE="${PIPE_TMP_DIR}/${CMD_MD5}"
LOG_SUFFIX=".log"
STATUS_SUFFIX=".status"


[[ -z "${CMD-}" ]] && HELP_SHOW && exit 1

function DEINIT(){

	OUTPUT_PREFIX_ADD "DEINIT():"

	[[ "${QUEUE_UPDATED}" != false ]] && THROW "QUEUE_UPDATED MUST BE \"false\""

	QUEUE_READ

	[[ "${#QUEUE[@]}" -gt 0 ]] && THROW "QUEUE MUST BE EMPTY"

	OUTPUT "REMOVING PIPE FILE (${PIPE_FILE})"

	rm "${PIPE_FILE}"

	LOCK_WRITE_REMOVE "${PIPE_FILE}"

	OUTPUT_PREFIX_REMOVE

	exit 0
}

function INIT(){

	local QITEM

	OUTPUT_PREFIX_ADD "INIT():"

	mkdir -p "${PIPE_TMP_DIR}" || {
		echo "PROBLEM CREATING PIPE_TMP_DIR"
		exit 1
	}

	if [[ ! -f "${PIPE_FILE}" ]]; then
		#THIS IS THE FIRST TIME THIS PIPE HAS RAN
		touch "${PIPE_FILE}" || THROW "UNABLE TO WRITE PIPE FILE (${PIPE_FILE})"
	fi

	if ! LOCK_WRITE "${PIPE_FILE}"; then

		OUTPUT "PIPE ALREADY RUNNING"

		if [[ -p /dev/fd/0 ]]; then

			readarray -t QUEUE_APPEND -d "${PIPE_QUEUE_IFS}"

			if [[ "${#QUEUE_APPEND[@]}" -gt 0 ]]; then

				OUTPUT "ADDING ITEMS TO QUEUE"

				for i in "${!QUEUE_APPEND[@]}"; do

					if [[ -e "${QUEUE_APPEND[${i}]}" ]]; then

						OUTPUT "CONVERTING RELATIVE ITEM (${QUEUE_APPEND[${i}]}) TO ABSOLUTE ($(realpath "${QUEUE_APPEND[${i}]}"))"

						QUEUE_APPEND[${i}]="$(realpath "${QUEUE_APPEND[${i}]}")"
					fi
				done

				LOCK_READ "${QUEUE_APPEND_FILE}" || THROW "UNABLE TO LOCK APPEND FILE FOR READING"

				OUTPUT "WRITING TO APPEND FILE (${QUEUE_APPEND_FILE})"

				printf "%s\n" "${QUEUE_APPEND[@]}" >> "${QUEUE_APPEND_FILE}"

				LOCK_READ_REMOVE "${QUEUE_APPEND_FILE}"
			fi
		fi

		OUTPUT "PIPE ID (${CMD_MD5})"

		OUTPUT_PREFIX_REMOVE

		exit 0
	else

		#PROVIDES ${QUEUE}
		QUEUE_READ

		# APPEND STDIN TO QUEUE
		if [[ -p /dev/fd/0 ]]; then

			while IFS=$"${PIPE_QUEUE_IFS}" read -r -t 1 QITEM; do

				[[ -z "${QITEM}" ]] && continue

				QUEUE_PUSH "${QITEM}"
			done

			QUEUE_WRITE
		fi
	fi

	OUTPUT_PREFIX_REMOVE
}

function PROCESS(){

	local QITEM

	OUTPUT "QUEUED ITEMS WAITING FOR PROCESSING (${#QUEUE[@]})..."

	while true; do

		for QITEM in "${!QUEUE[@]}"; do

			[[ -n "${QUEUE_RUNNING[${QITEM}]-}" ]] && continue

			OUTPUT "PROCESSING (${QITEM})"

			RUN "${QITEM}"

			[[ "${#QUEUE_RUNNING[@]}" -ge "${PIPE_MAX_THREADS}" ]] && break

		done

		RUN_CHECK

		while [[ "${#QUEUE_RUNNING[@]}" -ge "${PIPE_MAX_THREADS}" || ( "${#QUEUE[@]}" -gt 0 && "${#QUEUE_RUNNING[@]}" -ge "${#QUEUE[@]}" ) ]]; do

			OUTPUT "JOBS ACTIVE ($(jobs -rp | wc -l | tr -d '[:space:]')), JOBS TRACKING (${#QUEUE_RUNNING[@]}), QUEUE COUNT (${#QUEUE[@]})"

			sleep 1

			RUN_CHECK

		done

		[[ "${#QUEUE[@]}" -gt 0 ]] && continue

		QUEUE_READ

		[[ "${#QUEUE[@]}" -gt 0 ]] && continue

		break

	done

}

INIT

PROCESS

DEINIT



