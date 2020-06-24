#!/bin/bash

set -o nounset -o errexit -o pipefail

declare SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

source "${SCRIPT_DIR}/inc/functions.inc.sh"

function OP_ATTRIB() {

	[[ -z "${1-}" ]] && THROW "ERROR: MUST PROVIDE SOURCE AS FIRST ARGUMENT"

	local SOURCE="${1}"

	[[ ! -e "${SOURCE}" ]] && return 0 #THROW "ERROR: SOURCE MUST EXIST"

	local TARGET="${SOURCE/"${DIR_SRC}"/"${DIR_DST}"}"

	[[ ! -e "${TARGET}" ]] && return 0 #THROW "ERROR: TARGET MUST EXIST"

	OUTPUT "ATTRIB (${SOURCE} -> ${TARGET})"

	touch --reference="${SOURCE}" "${TARGET}"

	chmod --reference="${SOURCE}" "${TARGET}"

	chown --reference="${SOURCE}" "${TARGET}"

	return 0
}

function OP_COPY() {

	[[ -z "${1-}" ]] && THROW "ERROR: MUST PROVIDE SOURCE AS FIRST ARGUMENT"

	local SOURCE="${1}"

	[[ ! -e "${SOURCE}" ]] && return 0 #THROW "ERROR: SOURCE MUST EXIST"

	local TARGET="${SOURCE/"${DIR_SRC}"/"${DIR_DST}"}"

	OUTPUT "COPY (${SOURCE} -> ${TARGET})"

	mkdir -p "$(dirname "${TARGET}")"

	cp -f -a "${SOURCE}" "${TARGET}"

	return 0
}

function OP_CREATE() {

	[[ -z "${1-}" ]] && THROW "MUST PROVIDE SOURCE AS FIRST ARGUMENT"

	local SOURCE="${1}"

	[[ ! -f "${SOURCE}" ]] && return 0 #THROW "SOURCE MUST BE A FILE"

	local TARGET="${SOURCE/"${DIR_SRC}"/"${DIR_DST}"}"

	OUTPUT "CREATE (${TARGET})"

	mkdir -p "$(dirname "${TARGET}")"

	echo "" > "${TARGET}"

	touch --reference="${SOURCE}" "${TARGET}"

	chmod --reference="${SOURCE}" "${TARGET}"

	chown --reference="${SOURCE}" "${TARGET}"

	return 0
}

function OP_MKDIR() {

	[[ -z "${1-}" ]] && THROW "MUST PROVIDE SOURCE AS FIRST ARGUMENT"

	local SOURCE="${1}"

	[[ ! -d "${SOURCE}" ]] && return 0 #THROW "SOURCE MUST BE A DIRECTORY"

	local TARGET="${SOURCE/"${DIR_SRC}"/"${DIR_DST}"}"

	OUTPUT "CREATE DIRECTORY (${TARGET})"

	mkdir -p "${TARGET}"

	touch --reference="${SOURCE}" "${TARGET}"

	chmod --reference="${SOURCE}" "${TARGET}"

	chown --reference="${SOURCE}" "${TARGET}"

	return 0
}

function OP_MOVE() {

	[[ -z "${1-}" ]] && THROW "ERROR: MUST PROVIDE ORIGINAL SOURCE AS FIRST ARGUMENT"

	local ORIG_SOURCE="${1}"

	[[ -z "${2-}" ]] && THROW "ERROR: MUST PROVIDE NEW SOURCE AS SECOND ARGUMENT"

	local NEW_SOURCE="${2}"

	[[ ! -e "${NEW_SOURCE}" ]] && return 0 #THROW "ERROR: NEW SOURCE MUST EXIST"

	# If the we detect a move_from -> move_to of the same source we recopy the file to the target
	[[ "${ORIG_SOURCE}" == "${NEW_SOURCE}" ]] && return 0

	local ORIG_TARGET="${ORIG_SOURCE/"${DIR_SRC}"/"${DIR_DST}"}"

	[[ ! -e "${ORIG_TARGET}" ]] && return 0 #THROW "ERROR: ORIGINAL TARGET MUST EXIST"

	local NEW_TARGET="${NEW_SOURCE/"${DIR_SRC}"/"${DIR_DST}"}"

	OUTPUT "MOVE (${ORIG_TARGET} -> ${NEW_TARGET})"

	mkdir -p "$(dirname "${NEW_TARGET}")"

	mv "${ORIG_TARGET}" "${NEW_TARGET}"

	return 0
}

function OP_RM() {

	[[ -z "${1-}" ]] && THROW "ERROR: MUST PROVIDE SOURCE AS FIRST ARGUMENT"

	local SOURCE="${1}"

	local TARGET="${SOURCE/"${DIR_SRC}"/"${DIR_DST}"}"

	[[ ! -e "${TARGET}" ]] && return 0

	[[ -d "${TARGET}" ]] && THROW "TARGET (${TARGET}) MUST NOT BE A DIRECTORY"

	OUTPUT "REMOVE (${TARGET})"

	rm "${TARGET}"

	return 0
}

function OP_RMDIR() {

	[[ -z "${1-}" ]] && THROW "ERROR: MUST PROVIDE SOURCE AS FIRST ARGUMENT"

	local SOURCE="${1}"

	local TARGET="${SOURCE/"${DIR_SRC}"/"${DIR_DST}"}"

	[[ ! -e "${TARGET}" ]] && return 0

	[[ ! -d "${TARGET}" ]] && THROW "TARGET (${TARGET}) MUST BE A DIRECTORY"

	OUTPUT "REMOVE DIRECTORY (${TARGET})"

	rmdir "${TARGET}"

	return 0
}

[[ -z "${1-}" ]] && THROW "MUST PROVIDE \$SOURCE AS ARGUMENT 1"

[[ -z "${2-}" ]] && THROW "MUST PROVIDE \$DESTINATION AS ARGUMENT 2"

# Check if inotofywait is installed.
hash inotifywait 2> /dev/null || THROW "inotify-tools MUST BE INSTALLED"

declare CWD="$(pwd)"

if [[ "${1}" = /* ]]; then
	declare DIR_SRC="$(realpath "${1}")/"
else
	declare DIR_SRC="$(realpath "${CWD}/${1}")/"
fi

if [[ "${2}" = /* ]]; then
	declare DIR_DST="$(realpath "${2}")/"
else
	declare DIR_DST="$(realpath "${CWD}/${2}")/"
fi

[[ ! -d "${DIR_SRC}" ]] && { echo "ERROR: (${DIR_SRC}) is not a directory"; exit 1; }

[[ ! -d "${DIR_DST}" ]] && { echo "ERROR: (${DIR_DST}) is not a directory"; exit 1; }

trap "echo EXITING; exit 0" 10

trap "echo EXITING; exit 1" 11

declare READ_TIMEOUT="" SUBJECT EVENT EVENT_PENDING EVENT_NEXT

echo "SYNCING DIRECTORIES (${DIR_SRC} >>> ${DIR_DST})"

rsync -ahDHAXW --no-links --bwlimit=0 --no-compress --info=name1,progress2 --stats --update --exclude '/node_modules*' --exclude '/.sync*' "${DIR_SRC}" "${DIR_DST}"

echo "SYNCING DIRECTORIES (${DIR_SRC} <<< ${DIR_DST})"

# BI-DIRECTIONAL SYNC
rsync -ahDHAXW --no-links --bwlimit=0 --no-compress --info=name1,progress2 --stats --update --exclude '/node_modules*' --exclude '/.sync*' "${DIR_DST}" "${DIR_SRC}"

echo -n "FINAL SYNC (${DIR_SRC} >>> <<< ${DIR_DST})..."

rsync -ahDHAXW --no-links --bwlimit=0 --no-compress --update --exclude '/node_modules*' --exclude '/.sync*' "${DIR_SRC}" "${DIR_DST}" &

# BI-DIRECTIONAL SYNC
rsync -ahDHAXW --no-links --bwlimit=0 --no-compress --update --exclude '/node_modules*' --exclude '/.sync*' "${DIR_DST}" "${DIR_SRC}" &

wait

echo "COMPLETE"

while { IFS='|' read -r ${READ_TIMEOUT} -- EVENT SUBJECT; } || { DEBUG "READ TIMED OUT"; EVENT="TIMEOUT"; true; }; do

	while true; do

		DEBUG "EVENT LOOP (${EVENT}: ${SUBJECT})"

		# check for a pending event (MOVING_FROM)
		if [[ -n "${EVENT_PENDING[*]}" ]]; then

			DEBUG "EVENT_PENDING (${EVENT_PENDING[*]})"

			# if we have a matching event pair for MOVED_(TO|FROM) compress the event to "RENAMED"
			if [[ "${SUBJECT}" != "${EVENT_PENDING[1]}"
					&& ( ( "${EVENT}" == "MOVED_TO" && "${EVENT_PENDING[0]}" == "MOVED_FROM" )
						|| ( "${EVENT}" == "MOVED_TO,ISDIR" && "${EVENT_PENDING[0]}" == "MOVED_FROM,ISDIR" ) ) ]]; then

				#HANDLE A RENAME
				EVENT="${EVENT/"MOVED_TO"/"RENAMED"}"

				SUBJECT=("${EVENT_PENDING[1]}" "${SUBJECT}")

				DEBUG "UPDATING CURRENT EVENT_LOOP (${EVENT}: ${SUBJECT[*]})"

			else

				# USE EVENT_NEXT AS A MEANS TO DETERMINE IF THIS IS THE SECOND LOOP FOR AN ATTEMPTING PAIR
				# ALSO HANDLE EVENT_NEXT IN THE SECOND LOOP AS A NORMAL EVENT
				EVENT_NEXT=("${EVENT}" "${SUBJECT}")

				DEBUG "DEFERRING CURRENT EVENT_LOOP UNTIL NEXT"

				EVENT="${EVENT_PENDING[0]}"

				SUBJECT="${EVENT_PENDING[1]}"

				DEBUG "UPDATING CURRENT EVENT_LOOP (${EVENT}: ${SUBJECT})"
			fi

			EVENT_PENDING=()

			READ_TIMEOUT=""
		fi

		case "${EVENT}" in
			"TIMEOUT")
				;;
			"ATTRIB")
				OP_ATTRIB "${SUBJECT}"
				;;
			"ATTRIB,ISDIR")
				OP_ATTRIB "${SUBJECT}"
				;;
			"CLOSE_WRITE,CLOSE")
				OP_COPY "${SUBJECT}"
				;;
			"CREATE")
				OP_CREATE "${SUBJECT}"
				;; #IGNORE
			"CREATE,ISDIR")
				OP_MKDIR "${SUBJECT}"
				;;
			"DELETE")
				OP_RM "${SUBJECT}"
				;;
			"DELETE,ISDIR")
				OP_RMDIR "${SUBJECT}"
				;;
			"MOVED_FROM")
				if [[ -z "${EVENT_NEXT[*]}" ]]; then
					EVENT_PENDING=("${EVENT}" "${SUBJECT}")
					READ_TIMEOUT="-t .25"
					break; #WAIT FOR THE NEXT EVENT OR THE TIMEOUT
				else
					OP_RM "${SUBJECT}"
				fi
				;;
			"MOVED_FROM,ISDIR")
				if [[ -z "${EVENT_NEXT[*]}" ]]; then
					EVENT_PENDING=("${EVENT}" "${SUBJECT}")
					READ_TIMEOUT="-t .25"
					break; #WAIT FOR THE NEXT EVENT OR THE TIMEOUT
				else
					OP_RMDIR "${SUBJECT}"
				fi
				;;
			"MOVED_TO")
				OP_COPY "${SUBJECT}"
				;;
			"MOVED_TO,ISDIR")
				OP_COPY "${SUBJECT}"
				;;
			"RENAMED")
				#WE USE ${SUBJECT} AS AN ARRAY
				OP_MOVE "${SUBJECT[@]}"
				;;
			"RENAMED,ISDIR")
				#WE USE ${SUBJECT} AS AN ARRAY
				OP_MOVE "${SUBJECT[@]}"
				;;
			"DELETE_SELF")
				if [[ "${DIR_SRC}" == "${SUBJECT}" ]]; then
					echo "ERROR: DIR_SRC (${DIR_SRC}) WAS DELETED"
					kill -n 11 $$
				fi
				;; #TODO: NEED TO DO SAME FOR TARGET
			"MOVE_SELF")
				if [[ "${DIR_SRC}" == "${SUBJECT}" ]]; then
					echo "ERROR: DIR_SRC (${DIR_SRC}) WAS MOVED"
					kill -n 11 $$
				fi
				;; #TODO: NEED TO DO SAME FOR TARGET
			*)
				echo "UNKNOWN EVENT (${EVENT})"
				kill -n 11 $$
				;;
		esac

		if [[ -n "${EVENT_NEXT[*]}" ]]; then

			EVENT="${EVENT_NEXT[0]}"

			SUBJECT="${EVENT_NEXT[1]}"

			EVENT_NEXT=()
		else

			unset SUBJECT EVENT

			break
		fi

	done
done < <( inotifywait -mr \
	--exclude '(\/\.sync(\/.*)?|\/node_modules(\/.*)?)' \
	--format '%,e|%w%f' \
	-e attrib \
	-e close_write \
	-e create \
	-e delete \
	-e moved_from \
	-e moved_to \
	-e delete_self \
	-e move_self \
	"${DIR_SRC}" )

