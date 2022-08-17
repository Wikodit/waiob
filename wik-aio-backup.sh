#!/bin/sh

# Author: Jeremy Trufier <jeremy@trufier.com>

set -e
set -uo pipefail

BIN_PATH=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
# PROJECT_NAME=${PWD##*/}

export AUTO_CLEAN=`[[ "${WAIOB_DISABLE_AUTO_CLEAN}" == "1" ]] && echo "0" || echo "1"`

export SYSLOG_FACILITY="${WAIOB_SYSLOG_FACILITY:-"local0"}"
export SYSLOG_LEVEL="${WAIOB_SYSLOG_LEVEL:-"5"}"


function main () {
  [[ -z "$ACTION" ]] \
    && error "No action defined" 64

  echo "ACTION: $ACTION"
  echo "SNAPSHOT_ID: $SNAPSHOT_ID"
  echo "TAGS: ${TAGS[@]}"
  echo "AUTO_CLEAN: $AUTO_CLEAN"

  exception "nothing to do yet"
}


function fetch_args () {
  export TAGS=()
  while test $# -gt 0; do
    case "$1" in
      -h|--help)
        show_help
        ;;
      backup|restore|list)
        export ACTION="$1"
        shift
        ;;
      -s)
        shift
        export SNAPSHOT_ID="$1"
        shift
        ;;
      --snapshotId=*|--snapshotid=*)
        export SNAPSHOT_ID=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      -t)
        shift
        export TAGS+=("$1")
        shift
        ;;
      --tag=*)
        export TAGS+=(`echo "$1" | sed -e 's/^[^=]*=//g'`)
        shift
        ;;
      --no-clean|--clean)
        export AUTO_CLEAN=`[[ ${AUTO_CLEAN} != "1" && "$1" == "--clean" || "$1" != "--no-clean" ]] && echo "1" || echo "0"`
        shift
        ;;
      --)
        shift
        export RESTIC_ARGS=$@
        break
        ;;
      *)
        REMAINING_ARG="$1"
        shift
        ;;
    esac
  done
}

function show_help () {
  cat <<EOF
Wikodit AIO Backup, simplifies backup through restic.

It handles the restic repository initialization, as well as easy restore and easy backup of a variety of sources.

Supported backup adapters:

* MySQL database
* PostgreSQL database
* MongoDB database
* Filesystem

Usage:
  wik-aio-backup {action} [options] [-- [restic_additional_args]]

  "{action}" can be :
    * backup - launch the backup, this command will also clean old backups if a retention policy has been set in the env.
    * prune - prune all backups depending on the retention policy (do not clean anything if no retention policy)
    * list - list all available snapshots (can use --tags to filter)
    * restore - restore a specified snapshots
    * delete - remove some snapshots

Options:
  -h, --help                      show brief help
  -s id, --snapshotId=id          use a specific snapshot (restore action only)
  -t tag, --tag=tag               filer using tag (or tags, option can be used multiple time)--exclude-tag=tag               filer excluding this tag (or tags, option can be used multiple time)
  --no-clean                      prevent the cleaning after all actions (and act as a dry-run for prune action)
  --clean                         trigger the cleaning after all action (or act as a dry-run for prune action), for use with `WAIOB_DISABLE_AUTO_CLEAN` env variable
  --verbose                       set the logging level to debug (see WAIOB_SYSLOG_LEVEL)

Environment:

  Note: those are considered permanent config options, and should not change through time

  - Required:
    * AWS_ACCESS_KEY_ID: The S3 storage key id
    * AWS_SECRET_ACCESS_KEY: The S3 storage secret id
    * RESTIC_PASSWORD: An encryption password to write and read from the restic repository
    * RESTIC_REPOSITORY: The repository to store the snapshosts, exemple: s3:s3.gra.perf.cloud.ovh.net/backups/my-namespace/mysql
    * RESTIC_COMPRESSION: set compression level (repository v2), "auto", "max", "off"
    * RESTIC_\*: all other Restic possible env variables
    * WAIOB_RESTIC_REPOSITORY_VERSION: default to 2 (restic >=v0.14), repository version
    * WAIOB_DISABLE_AUTO_CLEAN: disabled by default, each action trigger an auto-clean of old snapshots if there is some retention policy, set to 1 to disable it by default, can still be enable afterwards with --clean
    * WAIOB_ADAPTER: can be
      - mysql - require mysqldump/mysql
      - pg - require pg_dump/pg_restore
      - mongo - require mongodump/mongorestore
      - fs
  
  - MySQL/Mongo/PG:
    * DB_HOST: the database host, default to database type default
    * DB_PORT: the database port, default to database type default
    * DB_USERNAME: the database username, default to database type default
    * DB_PASSWORD: the database password, default to database type default

  - MySQL/PG:
    * DB_DATABASES: databases list to backup (separated by spaces), default to all-databases if not specified
    * DB_TABLES: backup specific tables (separated by spaces), DB_DATABASES should only contain one database
    
  - Mongo:
    * DB_COLLECTIONS: which collections to backup (default to all collections)
    * DB_TABLES: backup specific tables (separated by spaces), DB_DATABASES should only contain one database

  - Other optional envs:
    * WAIOB_SYSLOG_FACILITY: define facility for syslog, default to local0
    * WAIOB_SYSLOG_LEVEL: define logging level, default to 5 "notice" (0=emergency, 1=alert, 2=crit, 3=error, 4=warning, 5=notice, 6=info, 7=debug), --verbose override the level to 7

Examples:
  wik-aio-backup backup mysql
  wik-aio-backup backup mysql --no-clean -- --tag=2022 --tag=manual-backup
  wik-aio-backup backup mysql -t 2022 -t manual-backup --no-clean -- --dry-run --verbose
  wik-aio-backup backup mysql -t 2022 -t manual-backup --no-clean -- --exclude="node_modules"
  wik-aio-backup list mysql -t=2022 --no-clean
  wik-aio-backup restore mysql -s 123456 --no-clean
  wik-aio-backup prune mysql --exclude-tag=periodic-backup
  wik-aio-backup delete mysql -t 2021
  wik-aio-backup delete mysql -s 123456

Author:
  Wikodit - Jeremy Trufier <jeremy@wikodit.fr>
EOF
}


# Usage: 
#   log <level> <message>
#
# exemple:
#   log error "this is an error"
#   log debug "too much verbosity here"
function log () {
  local upper="$(echo "${1}" | awk '{print toupper($0)}')";
  shift 1;
  local msg="${@}";

  local -A levels;
  levels['DEBUG']=7;
  levels['INFO']=6;
  levels['NOTICE']=5;
  levels['WARN']=4;
  levels['ERROR']=3;
  levels['CRIT']=2;
  levels['ALERT']=1;
  levels['EMERG']=0; # Should never be used

  local -A colors;
  colors["DEBUG"]="\033[34m"  # Blue
  colors["INFO"]="\033[32m"   # Green
  colors["NOTICE"]=""         # White
  colors["WARN"]="\033[33m"   # Yellow
  colors["ERROR"]="\033[31m"  # Red
  colors["CRIT"]="\033[31m"   # Red
  colors["ALERT"]="\033[31m"  # Red
  colors["EMERG"]="\033[31m"  # Red
  colors["RESET"]="\033[0m" # Reset

  local level="${levels[${upper}]:-5}"
  
  # Silence logging if level to high
  (( "${level}" > "${SYSLOG_LEVEL}" )) && return 0;

  # Redirect to stdout/stderr if in a tty
  if tty -s; then
    local std="${colors[${upper}]}$(date "+%F %T") [${upper}] ${msg}${colors["RESET"]}"
    (( "${level}" > "3" )) && echo -e "${std}" || >&2 echo -e "${std}" # stdout or stderr
  fi

  # In any case redirect to logger
  logger -t ${0##*/}[$$] -p "${SYSLOG_FACILITY}.${SYSLOG_LEVEL}" "${msg}";
}

# Some helpers
function debug   () { log debug   $@ }
function info    () { log info    $@ }
function notice  () { log notice  $@ }
function warning () { log warning $@ }
function error   () { log error   $@ }
function exception () {
  log crit $1

  # if in terminal, we can show the help
  if tty -s; then
    echo -e "\nCheck help with -h"
    #show_help
  fi

  exit ${2:-1}
}

# Launch the script
fetch_args $@
main