#!/usr/bin/env bash

# Author: Jeremy Trufier <jeremy@trufier.com>

set -euo pipefail
# set -x # uncomment for xtrem debugging with high cafeine level requirement

export IS_IN_TTY=$(tty -s && echo 1 || echo 0)

export FORCE="0"
export ACTION="help"
export SNAPSHOT_ID="${SNAPSHOT_ID:-""}"
export TAGS=(${TAGS:-""})
# export EXCLUDED_TAGS=()
export RESTIC_ARGS=()
export ADAPTER_ARGS=()

export AUTO_CLEAN=`[[ "${WAIOB_DISABLE_AUTO_CLEAN:-"0"}" == "1" ]] && echo "0" || echo "1"`

export SYSLOG_FACILITY="${WAIOB_SYSLOG_FACILITY:-"local0"}"
export SYSLOG_LEVEL="${WAIOB_SYSLOG_LEVEL:-"5"}"

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-""}"
export RESTIC_PASSWORD="${RESTIC_PASSWORD:-""}"
export RESTIC_REPOSITORY_VERSION="${WAIOB_RESTIC_REPOSITORY_VERSION:-"2"}"
export ADAPTER="${WAIOB_ADAPTER:-"fs"}"
export MODE="${WAIOB_MODE:-"utility"}"
export DB_LOCK="${WAIOB_DB_LOCK:-"1"}"

export PREPARED_RESTIC_ARGS=()

export RETURN_VALUE=""

############
# FS
####

# Validate env and variables
validate_config_fs() {
  [[ -z "${FS_ROOT:-}" ]] \
    && exception "missing FS_ROOT environment variable" 64
  return 0
}

backup_fs () {
  call restic ${PREPARED_RESTIC_ARGS[@]} backup "${FS_ROOT}"
  return $?
}

restore_fs () {
  call restic ${PREPARED_RESTIC_ARGS[@]} restore "${SNAPSHOT_ID}" --target "${FS_ROOT}"
  return $?
}

############
# MySQL
####

# Validate env and variables
validate_config_mysql() {
  validate_db_mode_dependencies "mysql" "mysqldump" "mysql"

  # var_names=("$@")
  # for var_name in "${var_names[@]}"; do
  #     [ -z "${!var_name}" ] && echo "$var_name is unset." && var_unset=true
  # done
  return 0
}

# To avoid password prompt or password diffusion in the process list, we create an option file
# return location of file
create_mysql_option_file() {
  if [ -z "${!DB_CONFIG_*}" ]; then
    notice "no DB_CONFIG_* environment variables, connexion may be unsuccessful"
    return 0 # nothing to do
  fi

  tmp=$(mktemp)
  sections=("mysql" "client")

  info "preparing mysql option file"
  for section in ${sections[@]}; do
    echo "[$section]" >> $tmp
    for env_var_name in ${!DB_CONFIG_*}; do
      local lower_name=$(echo "${env_var_name#DB_CONFIG_}" | awk '{print tolower($0)}')
      echo "${lower_name}"="${!env_var_name}" >> $tmp
    done
    echo -ne "\n" >> $tmp
  done

  info "created mysql option file at location $tmp"

  if is_debug; then
    debug "\t┌─────────────────────────────"
    cat $tmp | while read -r line; do debug "\t│ $line"; done
    debug "\t└─────────────────────────────"
  fi

  RETURN_VALUE="${tmp}"

  return 0
}

backup_mysql () {
  call create_mysql_option_file
  local option_file="${RETURN_VALUE}"

  if [[ "${MODE}" == "files" ]] then

    if [[ ${DB_LOCK} == "1" ]]; then
      notice "locking database"
      exec 3> >(mysql --defaults-extra-file=${option_file})
      # call mysql --defaults-extra-file=${option_file} -e "LOCK INSTANCE FOR BACKUP;" && info "success locking database" || exception "failed locking database"
      echo "LOCK INSTANCE FOR BACKUP;" >&3

      # todo check that, the idea was to ensure session is closed correctly, but maybe not needed
      # imo, but need to be tested, if program is quit, session is killed and database is unlocked
      # trap 'exec 3>&-' SIGINT SIGQUIT SIGTSTP
    fi

    backup_fs

    local ret=${?}

    if [[ ${DB_LOCK} == "1" ]]; then
      notice "unlocking database"
      # call mysql --defaults-extra-file=${option_file} -e "LOCK INSTANCE FOR BACKUP;" && info "success unlocking database" || exception "failed unlocking database" 1 2
      echo "UNLOCK INSTANCE;" >&3
      exec 3>&-

      # todo check that, the idea was to ensure session is closed correctly, but maybe not needed
      # imo, but need to be tested, if program is quit, session is killed and database is unlocked
      # trap - SIGINT SIGQUIT SIGTSTP
    fi

    return ${ret}
  fi

  local adapter_args=(\
    "--single-transaction"\
    "--skip-lock-tables"\
    "--defaults-extra-file=${option_file}"\
  )
  
  local db_filename="${DB_DATABASE:-"database"}.sql"
  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    "--stdin"\
    "--stdin-filename"\
    "${db_filename}"\
  )
  
  debug "restic_args=${restic_args[@]}"

  call_silent_err mysqldump ${adapter_args[@]} "${DB_DATABASE:-}" ${DB_TABLES:-} | restic ${restic_args[@]} backup
}

restore_mysql () {
  call create_mysql_option_file
  local option_file="${RETURN_VALUE}"

  if [[ "${MODE}" == "files" ]] then
    if [[ "${FORCE}" != "1" ]]; then
      call_silent mysql --defaults-extra-file=${option_file} -e "show database" && exception "on mode=files, database should not be running, pass --force to restore anyway or stop database before restoring"
    fi
    
    restore_fs
    local ret=${?}

    return ${ret}
  fi

  local adapter_args=(\
    "--defaults-extra-file=${option_file}"\
  )

  local db_filename="${DB_DATABASE:-"database"}.sql"
  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    "--path"\
    "/${db_filename}"\
  )

  call_silent_err mysqldump ${adapter_args[@]} "${DB_DATABASE:-}" ${DB_TABLES:-} | restic ${restic_args[@]} dump "${SNAPSHOT_ID}" "${db_filename}"
}

############
# PostgreSQL
####

# Validate env and variables
validate_config_pg() {
  validate_db_mode_dependencies "psql" "pg_dump" "pg_restore"
  return 0
}

backup_pg () {
  error "${ACTION}_${ADAPTER} not implemented yet"
}

restore_pg () {
  error "${ACTION}_${ADAPTER} not implemented yet"
}

############
# Mongo
####

# Validate env and variables
validate_config_mongo() {
  validate_db_mode_dependencies "mongo" "mongodump" "mongorestore"
  return 0
}

backup_mongo () {
  error "${ACTION}_${ADAPTER} not implemented yet"
}

restore_mongo () {
  error "${ACTION}_${ADAPTER} not implemented yet"
}

############
# Common
####

# arg1=client command, arg2=restore command, arg3=backup command
validate_db_mode_dependencies() {
  if [[ "${MODE}" == "utility" ]]; then
    if [ -x "$(command -v "${2}")" ] || [ -x "$(command -v "${3}")" ]; then
      warn "${2} or ${3} is not installed, fallback to mode='files'"
      MODE="files"
    fi
  fi

  if [[ "${MODE}" == "files" ]]; then
    if [[ "${DB_LOCK}" == "1" ]] && [ -x "$(command -v "${1}")" ]; then
      exception "${1} is not installed, but needed to acquire a lock, if you really want to backup/restore without lock pass the --no-db-lock option" 64
    fi
  fi
}

# Usage get_restic_args backup toto
prepare_restic_args() {
  PREPARED_RESTIC_ARGS+=(\
    "${RESTIC_ARGS[@]}"\
    "${TAGS[@]/#/--tag=}"\
    "${@}"\
  )
  
  debug "PREPARED_RESTIC_ARGS=${PREPARED_RESTIC_ARGS[@]}"
  return 0
}

# Validate env and variables
validate_config_common() {
  [[ -z "$RESTIC_REPOSITORY" ]] \
    && exception "missing RESTIC_REPOSITORY environment variable" 64
  [[ -z "$RESTIC_PASSWORD" ]] \
    && exception "missing RESTIC_PASSWORD environment variable" 64
  [[ -z "$ADAPTER" ]] \
    && exception "missing -a|--adapter option or WAIOB_ADAPTER environment variable" 64
  return 0
}

# Backup entrypoint
backup () {
  call validate_config_${ADAPTER}
  call prepare_restic_args
  call ensure_repository true
  call "backup_${ADAPTER}" && info "backup done" || exception "backup failed, enable verbose with -v or debug with -d" $? 2
}

# Restore entrypoint
restore () {
  [[ -z "$SNAPSHOT_ID" ]] \
    && exception "missing --snapshotId|-s option or SNAPSHOT_ID environment variable, 'latest' is a valid snaphotId value" 64

  call validate_config_${ADAPTER}
  call prepare_restic_args
  call ensure_repository
  call "restore_${ADAPTER}" && info "restore done" || exception "restore failed, enable verbose with -v or debug with -d" $? 2
}

# List snapshots
list () {
  call prepare_restic_args
  call restic "${PREPARED_RESTIC_ARGS[@]}" snapshots
}

# Forget password using retention policies
prune () {
  call prepare_restic_args
  call ensure_repository

  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    ${WAIOB_RETENTION_POLICY[@]/#/--keep}\
  )

  debug "restic_args=${restic_args[@]}"
  
  #call restic "${restic_args[@]}" forget
}

# Forget specific snapshots
forget () {
  call prepare_restic_args
  call ensure_repository
  error "${ACTION} not implemented yet"
}


# Check if the repository is created and available
# try to init if true is given as first argument
ensure_repository() {
  if is_repository_exists; then
    info "repository ${RESTIC_REPOSITORY} is ready"
    return 0
  fi

  if [ ${1:-false} != true ]; then
    exception "repository ${RESTIC_REPOSITORY} is not reachable or does not exists"
  fi

  warn "repository ${RESTIC_REPOSITORY} does not exists, attempt to initialized it..."

  if ! init_repository; then
    exception "${RESTIC_REPOSITORY} is not available or could not be initialized, check config, authorizations and network access" 2
  fi
}

is_repository_exists() {
  # If repository has been inialized, fetching snapshots will work, otherwise it will fail
  # with a dummy tag to avoid too much feedback
  call_silent restic snapshots --tag="wik-aio-backup--never"
  return $?
}

# Init restic repository
init_repository() {
  info "trying to initialize v${RESTIC_REPOSITORY_VERSION} repository at ${RESTIC_REPOSITORY}..."

  call_silent restic init --repository-version ${RESTIC_REPOSITORY_VERSION} --repo ${RESTIC_REPOSITORY}

  if (( $? == 0 )); then
    info "repository ${RESTIC_REPOSITORY} has been initialized"
    return 0
  fi

  error "repository ${RESTIC_REPOSITORY} could not be initialized"

  return 1
}

# Launcher
main () {
  [[ -z "$ACTION" ]] \
    && error "No action defined" 64

  if (( ${SYSLOG_LEVEL} >= 6 )) && [[ ! " ${RESTIC_ARGS[*]} " =~ " --verbose " ]]; then
    RESTIC_ARGS+=("--verbose")
  fi

  debug "\$ACTION=$ACTION"
  debug "\$ADAPTER=$ADAPTER"
  debug "\$SNAPSHOT_ID=$SNAPSHOT_ID"
  debug "\$TAGS=(${TAGS[@]})"
  # debug "\$EXCLUDED_TAGS=(${EXCLUDED_TAGS[@]})"
  debug "\$AUTO_CLEAN=$AUTO_CLEAN"
  debug "\$RESTIC_ARGS=${RESTIC_ARGS[@]}"
  debug "\$ADAPTER_ARGS=${ADAPTER_ARGS[@]}"
  debug "\$RESTIC_REPOSITORY=$RESTIC_REPOSITORY"
  debug "\$RESTIC_REPOSITORY_VERSION=$RESTIC_REPOSITORY_VERSION"

  validate_config_common
  call "${ACTION}"
}

# Fetch and treat cli args
fetch_args () {
  local args=${@}
  while test $# -gt 0; do
    case "$1" in
      -h|--help)
        call help
        shift
        ;;
      backup|restore|list|prune|forget)
        ACTION="$1"
        shift
        ;;
      mysql|pg|fs|mongo)
        ADAPTER="$1"
        shift
        ;;
      --adapter=*)
        ADAPTER=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      -a|--adapter)
        shift
        ADAPTER="$1"
        shift
        ;;
      --snapshotId=*|--snapshotid=*)
        SNAPSHOT_ID=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      -s|--snapshotId|--snapshotid)
        shift
        SNAPSHOT_ID="$1"
        shift
        ;;
      --tag=*)
        TAGS+=(`echo "$1" | sed -e 's/^[^=]*=//g'`)
        shift
        ;;
      --mode=*)
        DB_BACKUP_MODE=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      --no-db-lock)
        DB_LOCK="0"
        shift
        ;;
      -f|--force)
        FORCE="1"
        shift
        ;;
      --mode|-mode)
        shift
        MODE="$1"
        shift
        ;;
      -t|--tag)
        shift
        TAGS+=("$1")
        shift
        ;;
      # --exclude-tag=*)
      #   export EXCLUDED_TAGS+=(`echo "$1" | sed -e 's/^[^=]*=//g'`)
      #   shift
      #   ;;
      # --exclude-tag)
      #   shift
      #   export EXCLUDED_TAGS+=("$1")
      #   shift
      #   ;;
      --no-clean|--clean)
        AUTO_CLEAN=`[[ ${AUTO_CLEAN} != "1" && "$1" == "--clean" || "$1" != "--no-clean" ]] && echo "1" || echo "0"`
        shift
        ;;
      --verbose|-v)
        SYSLOG_LEVEL=6
        shift
        ;;
      --debug|-d)
        SYSLOG_LEVEL=7
        shift
        ;;
      --log-level=*)
        SYSLOG_LEVEL=(`echo "$1" | sed -e 's/^[^=]*=//g'`)
        shift
        ;;
     --log-level)
        shift
        SYSLOG_LEVEL+=("$1")
        shift
        ;;
      --json)
        warn 'compatibility with this kind of output is not guaranteed yet'
        # @todo This check should go somewhere else, disabling it because does not need it right now
        # if [ -x "$(command -v jq)" ]; then
        RESTIC_ARGS+=("--json")
        # else
        #   warn 'jq is not installed, json output will not be available'
        # fi
        shift
        ;;
      --)
        shift
        ADAPTER_ARGS=($@)
        break
        ;;
      *)
        RESTIC_ARGS+=("$1")
        shift
        ;;
    esac
  done

  debug "Command: ${args}"
}

help () {
  cat <<EOF
Wikodit AIO Backup, simplifies backup through restic.

It handles the restic repository initialization, as well as easy restore and easy backup of a variety of sources. It locks database and can be used to backup them using utility of fs

Supported backup adapters:

* MySQL database
* PostgreSQL database
* MongoDB database
* Filesystem

Usage:
  wik-aio-backup <action> [adapter] [options] [restic_additional_args] [ -- [adapter_additional_args]]

  ? [] denotes optional

  "<action>" can be :
    * backup - launch the backup, this command will also clean old backups if a retention policy has been set in the env.
    * restore - restore a specified snapshots
    * list - list all available snapshots (can use --tags to filter)
    * prune - forget all backups depending on the retention policy (do not clean anything if no retention policy)
    * forget - remove some snapshots

  "[adapter]" can be 'mysql', 'pg', 'mongo', 'fs'

Options:
  -h, --help                      show brief help
  -a adapter, --adapter=adapter   can be 'mysql', 'pg', 'mongo', 'fs'
  -f, --force                     less safe, but force some actions even if not entirely possible, and avoid some checks
  -m adapter, --mode=mode         can be 'files' or 'utility', default to 'utility' (no effect for 'fs' adapter). Utility uses mongodump, mysqldump, ... while 'files' backup database files. FS_ROOT is required with 'files' option
  -s id, --snapshotId=id          use a specific snapshot (restore action only), "latest" is a valid value
  -t tag, --tag=tag               filer using tag (or tags, option can be used multiple time)
  --no-clean                      prevent the cleaning after all actions (and act as a dry-run for prune action)
  --no-db-lock                    when using mode=files, disable the database lock (hot backup), may result in data lost if the database is in use. This can be useful to backup a database that is not running and thus not reachable
  --clean                         trigger the cleaning after all action (or act as a dry-run for prune action), for use with WAIOB_DISABLE_AUTO_CLEAN env variable
  -d, --debug                     set the logging level to debug (see WAIOB_SYSLOG_LEVEL)
  -v, --verbose                   set the logging level to info (see WAIOB_SYSLOG_LEVEL)
  --log-level=level               set the logging level (see WAIOB_SYSLOG_LEVEL)
  --json                          output json instead of human readable output
  -*, --*                         all other restic available options
  -- *                            all other adapter available options (ex: mysqldump additional options if adapter is mysql)

  Note: `=` is optional in options and can be replaced by the next argument

Environment:

  Note: those are considered permanent config options, and should not change through time

  - Required:
    * AWS_ACCESS_KEY_ID: The S3 storage key id
    * AWS_SECRET_ACCESS_KEY: The S3 storage secret id
    * RESTIC_PASSWORD: An encryption password to write and read from the restic repository
    * RESTIC_REPOSITORY: The repository to store the snapshosts, exemple: s3:s3.gra.perf.cloud.ovh.net/backups/my-namespace/mysql
    * RESTIC_COMPRESSION: set compression level (repository v2), "auto", "max", "off"
    * RESTIC_\*: all other Restic possible env variables
    * WAIOB_ADAPTER: can be
      - mysql - require mysqldump/mysql
      - pg - require pg_dump/pg_restore
      - mongo - require mongodump/mongorestore
      - fs

  - Recommended:
    * TAGS: list of tags to filter snapshots (ex: TAG="tag1 tag2")
  
  - FileSystem (FS):
    * FS_ROOT: the root directory to backup from / restore to

  - MySQL/Mongo/PG:
    * WAIOB_MODE: can be "files" or "utility", default to "utility", "utility" uses mongodump/mongorestore, and "files" backup database directory files. "files" is not compatible with DB_DATABASE, DB_TABLES, DB_COLLECTIONS...
    * WAIOB_DB_LOCK: enable by default '1', disable to '0', with mode="files" it is strongly advised lock files to prevent data loss during backup (no effect for mode="utility")
    * DB_CONFIG_HOST: the database host, default to database type default
    * DB_CONFIG_PORT: the database port, default to database type default
    * DB_CONFIG_USER: the database username, default to database type default
    * DB_CONFIG_PASSWORD: the database password, default to database type default
    * FS_ROOT: require only for mode=files, the root directory is necessary

  - MySQL/PG:
    * DB_DATABASE: the database to backup, if you want to backup all databases, pass '-- --all-databases' at the end of the command, or '-- --databases DB1 DB2 DB3'
    * DB_TABLES: list of tables to backup, by default all tables are backed up
    
  - Mongo:
    * DB_COLLECTIONS: which collections to backup (default to all collections)
    * DB_TABLES: backup specific tables (separated by spaces), DB_DATABASES should only contain one database

  - Other optional envs:
    * WAIOB_SYSLOG_FACILITY: define facility for syslog, default to local0
    * WAIOB_SYSLOG_LEVEL: define logging level, default to 5 "notice" (0=emergency, 1=alert, 2=crit, 3=error, 4=warning, 5=notice, 6=info, 7=debug), --verbose override the level to 7
    * WAIOB_RESTIC_REPOSITORY_VERSION: default to 2 (restic >=v0.14), repository version
    * WAIOB_DISABLE_AUTO_CLEAN: disabled by default, each action trigger an auto-clean of old snapshots if there is some retention policy, set to 1 to disable it by default, can still be enable afterwards with --clean
    * WAIOB_RETENTION_POLICY: define retention policy, default to none, if some tags have been defined, they will be used and only the snapshot with the same tags may be removed. An exemple: "hourly=24 daily=7 weekly=5 monthly=12 yearly=10 tag=manual last=5", this will keep the latest backup for each hour in the last 24h, the last backup of each day in the last 7 days, the last backup each week in the last 5 weeks, last backup per month for a year, and the last backup of each year for 10 years, it also keep all backups with the tag "manual" and ensure the last 5 backups are also kept.

Examples:
  wik-aio-backup backup -a fs
  wik-aio-backup backup -a fs --no-clean --tag=2022 --tag=app --tag=manual-backup
  wik-aio-backup backup -a fs -t 2022 -t manual-backup -t app --no-clean --dry-run --verbose
  wik-aio-backup backup -a fs -t 2022 -t manual-backup -t app --no-clean --exclude="node_modules"
  wik-aio-backup backup -a mysql -t 2022 -t manual-backup -t db --dry-run -- -C --add-drop-database
  wik-aio-backup list -a mysql -t=2022 --no-clean
  wik-aio-backup restore mysql -s 123456 --no-clean
  wik-aio-backup prune -a mysql --exclude-tag=periodic-backup
  wik-aio-backup forget -a mysql -t 2021
  wik-aio-backup forget -a mysql -s 123456

Author:
  Wikodit - Jeremy Trufier <jeremy@wikodit.fr>
EOF
}


# Usage: 
#   log <level> <message>
#
# exemple:
#   log 3 "this is an error"
#   log 7 "too much verbosity here"
log () {
  local levels=( "emerg"  "alert"  "crit"   "error"  "warn"   "notice" "info"   "debug"  )
  local colors=( "\e[35m" "\e[35m" "\e[35m" "\e[31m" "\e[33m" "\e[39m" "\e[32m" "\e[36m" )

  local level="${1}"
  shift 1;
  local msg="${@}";

  # Silence logging if level to high
  (( "${level}" > "${SYSLOG_LEVEL}" )) && return 0;

  # Redirect to stdout/stderr if in a tty
  if [[ "${IS_IN_TTY}" == "1" ]]; then
    local std="${colors[${level}]}$(date "+%F %T") [${levels[level]:-3}]\t${msg}\e[0m"
    (( "${level}" > "3" )) && echo -e "${std}" || >&2 echo -e "${std}" # stdout or stderr
  fi

  # In any case redirect to logger
  logger -t ${0##*/}[$$] -p "${SYSLOG_FACILITY}.${levels[level]:-3}" "${msg}";
}

# Some logging helpers
debug   () { log 7 $@; }
info    () { log 6 $@; }
notice  () { log 5 $@; }
warn    () { log 4 $@; }
error   () { log 3 $@; }
is_debug() { (( "${SYSLOG_LEVEL}" == "7" )) && return 0 || return 1; }

# Usage: exception <message> <code> <level=3>
exception () {
  log ${3:-3} $1

  # if in terminal, we can show the help
  if tty -s; then
    notice "check help with -h"
    #help
  fi

  exit ${2:-1}
}

call() {
  local callee="${1}"
  shift
  local callee_args="${@}"
  debug "${callee}: start, args: [${@}]"
  $callee $callee_args
  local result=$?
  debug "${callee}: end"
  return $result
}

call_silent() {
  if is_debug; then
    call ${@}
  else
    call ${@} &> /dev/null
  fi

  local result=$?
  return $result
}

call_silent_err() {
  if is_debug; then
    call ${@}
  else
    call ${@} 2> /dev/null
  fi

  return $?
}

# Launch the script
fetch_args $@
main