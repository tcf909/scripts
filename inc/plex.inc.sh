#!/bin/bash

#TODO: NOT DONE YET

PLEX_HOME_DIR="${PLEX_HOME_DIR:-$(echo ~plex)}"

PLEX_APP_SUPPORT_DIR="${PLEX_APP_SUPPORT_DIR:-${PLEX_HOME_DIR}/Library/Application Support}"

PLEX_PREF_FILE="${PLEX_APP_SUPPORT_DIR}/Plex Media Server/Preferences.xml"

function PLEX_CURRENT_VERSION_GET(){

	declare -n installedVersion=${1-}

	if (dpkg --get-selections 'plexmediaserver' 2> /dev/null | grep -wq "install"); then
 		installedVersion=$(dpkg-query -W -f='${Version}' plexmediaserver 2> /dev/null)
	else
  		installedVersion=""
	fi
}

function PLEX_LATEST_VERSION_GET(){
	declare -n installedVersion=${1-}
	declare -n remoteFile=${2-}
	local version="${3-plexpass}"
	local token="${4-}"

	local versionInfo

	case "${version}" in
	'plexpass')
		versionInfo="$(curl -s "https://plex.tv/downloads/details/1?build=linux-ubuntu-x86_64&channel=8&distro=ubuntu&X-Plex-Token=${token}")"
	;;
	'public')
		versionInfo="$(curl -s "https://plex.tv/downloads/details/1?build=linux-ubuntu-x86_64&channel=16&distro=ubuntu")"
	;;
	*)
		versionInfo="$(curl -s "https://plex.tv/downloads/details/1?build=linux-ubuntu-x86_64&channel=8&distro=ubuntu&X-Plex-Token=${token}&version=${version}")"
		;;
	esac

	# Get update info from the XML.  Note: This could countain multiple updates when user specifies an exact version with the lowest first, so we'll use first always.
	installedVersion=$(echo "${versionInfo}" | sed -n 's/.*Release.*version="\([^"]*\)".*/\1/p')
	remoteFile=$(echo "${versionInfo}" | sed -n 's/.*file="\([^"]*\)".*/\1/p')
}

function PLEX_LATEST_INSTALL_FROM_URL {
  PLEX_LATEST_INSTALL_FROM_RAW_URL "https://plex.tv/${1}"
}

function PLEX_LATEST_INSTALL_FROM_RAW_URL {
  local remoteFile="$1"
  curl -J -L -o /tmp/plexmediaserver.deb "${remoteFile}"
  local last=$?

  # test if deb file size is ok, or if download failed
  if [[ "$last" -gt "0" ]] || [[ $(stat -c %s /tmp/plexmediaserver.deb) -lt 10000 ]]; then
    echo "Failed to fetch update"
    exit 1
  fi

  dpkg -i --force-confold /tmp/plexmediaserver.deb
  rm -f /tmp/plexmediaserver.deb
}

function PLEX_IS_RUNNING {

    local PS_OUTPUT="$(ps -p $(cat "${PLEX_APP_SUPPORT_DIR}/Plex Media Server/plexmediaserver.pid") -o cmd h)"

    [[ "${PS_OUTPUT}" == "/usr/lib/plexmediaserver/Plex Media Server" ]] && return 0 || return 1;
}

function PLEX_DB_GET {
  local key="$1"
  xmlstarlet sel -T -t -m "/Preferences" -v "@${key}" -n "${PLEX_PREF_FILE}"
}

function PLEX_DB_SET {
  local key="${1}"
  local value="${2}"
  count="$(xmlstarlet sel -t -v "count(/Preferences/@${key})" "${PLEX_PREF_FILE}")"
  count=$(($count + 0))
  if [[ $count > 0 ]]; then
    xmlstarlet ed --inplace --update "/Preferences/@${key}" -v "${value}" "${PLEX_PREF_FILE}"
  else
    xmlstarlet ed --inplace --insert "/Preferences"  --type attr -n "${key}" -v "${value}" "${PLEX_PREF_FILE}"
  fi
}

function PLEX_DB_UPDATE {

    local key="${1}"
    local value="${2}"

    { [[ -z "${PLEX_PREF_FILE}" ]] || [[ -z "${key}" ]] || [[ -z "${value}" ]]; } && return 1

    local token="$(PLEX_DB_GET "PlexOnlineToken")"

    [[ ! -z "${token}" ]] && PLEX_TOKEN="&X-Plex-Token=${token}"

    EXEC="$(curl -X PUT "http://localhost:32400/:/prefs?${key}=${value}${PLEX_TOKEN}")"

    return $?

}
