#!/bin/bash

set -e -u -o pipefail

declare SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

source "${SCRIPT_DIR}/inc/functions.inc.sh"

cd "$PLEX_HOME/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/"

declare DB_FILE="com.plexapp.plugins.library.db"

for DB_FILE in "com.plexapp.plugins.library.db" "com.plexapp.plugins.library.blobs.db"; do
	cp "${DB_FILE}" "${DB_FILE}.original"
	sqlite3 "${DB_FILE}" "DROP index 'index_title_sort_naturalsort'" || true
	sqlite3 "${DB_FILE}" "DELETE from schema_migrations where version='20180501000000'" || true
	sqlite3 "${DB_FILE}" .dump > dump.sql
	rm "${DB_FILE}"
	sqlite3 "${DB_FILE}" "PRAGMA page_size=4096"
	sqlite3 "${DB_FILE}" "PRAGMA default_cache_size=128000;"
	sqlite3 "${DB_FILE}" < dump.sql
	chown plex:plex "${DB_FILE}"
	rm dump.sql
done
