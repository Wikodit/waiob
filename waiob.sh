#!/usr/bin/env bash

# Author: Jeremy Trufier <jeremy@trufier.com>

set -euo pipefail
# set -x # uncomment for xtrem debugging with high cafeine level requirement

export IS_IN_TTY=$(tty -s && echo 1 || echo 0)

export FORCE="0"
export ACTION="help"
export SNAPSHOT_ID="${SNAPSHOT_ID:-""}"
export TAGS=(${TAGS:-})
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

export FS_RELATIVE="${FS_RELATIVE:-0}"
export FS_ROOT="${FS_ROOT:-""}"

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
  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
  )

  local path=$(pwd)
  if [[ "${FS_RELATIVE}" == "1" ]]; then
    debug "fs relative enabled, cwd set to ${FS_ROOT}"
    cd "${FS_ROOT}"
    call restic ${restic_args[@]} backup "."
    debug "fs relative enabled, cwd set to ${path}"
    cd "${path}"
  else
    debug "fs relative disabled, storing absolute path in backup"
    call restic ${restic_args[@]} backup "${FS_ROOT}"
  fi

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
  chmod +600 "${tmp}"
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

  info "created mysql option file"

  if is_debug; then
    debug "mysql option file location: ${tmp}"
    debug "\t┌─────────────────────────────"
    cat $tmp | while read -r line; do
      debug "\t│ $(echo ${line} | sed -e 's/^password=.*$/password=******/g')"
    done
    debug "\t└─────────────────────────────"
  fi

  RETURN_VALUE="${tmp}"

  return 0
}

backup_mysql () {
  call create_mysql_option_file
  local option_file="${RETURN_VALUE}"

  if [[ "${MODE}" == "files" ]]; then

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
    "--defaults-extra-file=${option_file}"\
    ${ADAPTER_ARGS[@]} \
    "--single-transaction"\
    "--skip-lock-tables"\
    "${DB_DATABASE:-}"\
    ${DB_TABLES:-} \
  )
  
  local db_filename="${DB_DATABASE:-"database"}.sql"
  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    "--stdin"\
    "--stdin-filename=${db_filename}"\
  )
  
  debug "adapter_args=${adapter_args[@]}"
  debug "restic_args=${restic_args[@]}"

  mysqldump ${adapter_args[@]} | restic ${restic_args[@]} backup
}

restore_mysql () {
  call create_mysql_option_file
  local option_file="${RETURN_VALUE}"

  if [[ "${MODE}" == "files" ]]; then
    if not_is_force; then
      call_silent mysql --defaults-extra-file=${option_file} -e "show database" && exception "on mode=files, database should not be running, pass --force to restore anyway or stop database before restoring" 50 4
    fi
    
    restore_fs
    local ret=${?}

    return ${ret}
  fi

  local adapter_args=(\
    ${ADAPTER_ARGS[@]} \
    "--defaults-extra-file=${option_file}"\
  )

  local db_filename="${DB_DATABASE:-"database"}.sql"
  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    "--path=/${db_filename}"\
  )

  restic ${restic_args[@]} dump "${SNAPSHOT_ID}" "${db_filename}" | mysqldump ${adapter_args[@]} "${DB_DATABASE:-}" ${DB_TABLES:-}
}

############
# PostgreSQL
####

# Validate env and variables
validate_config_pg() {
  validate_db_mode_dependencies "psql" "pg_dump" "pg_restore"

  return 0
}

# To avoid password prompt or password diffusion in the process list, we create an option file
# return location of file
create_pg_option_file() {
  if [ -z "${!DB_CONFIG_*}" ]; then
    notice "no DB_CONFIG_* environment variables, connexion may be unsuccessful"
    return 0 # nothing to do
  fi

  tmp=$(mktemp)
  chmod +600 "${tmp}"
  echo "${DB_CONFIG_HOST:-"*"}:${DB_CONFIG_PORT:-"*"}:${DB_DATABASE:-"*"}:${DB_CONFIG_USER:-"*"}:${DB_CONFIG_PASSWORD:-""}" > "${tmp}"

  info "created pgpass file"

  if is_debug; then
    debug "pg option file location: ${tmp}"
    debug "\t┌─────────────────────────────"
    cat $tmp | while read -r line; do
      debug "\t│ $(echo ${line} | sed -e 's/:[^:]*$/:******/g')" # sed to mask password
    done
    debug "\t└─────────────────────────────"
  fi

  RETURN_VALUE="${tmp}"

  return 0
}

backup_pg () {
  call create_pg_option_file
  local option_file="${RETURN_VALUE}"

  if [[ "${MODE}" == "files" ]]; then
    not_is_force &&\
      call_silent pg_isready --passfile=${option_file} &&\
      exception "on mode=files, it is definitely not recommended to do a backup while the database is running, either shutdown the database first, or try with --force to ignore this warning" 50 4
    backup_fs
    return ${?}
  fi

  local adapter_args=(\
    ${ADAPTER_ARGS[@]} \
    "--passfile=${option_file}"\
  )
  
  local db_filename="${DB_DATABASE:-"database"}.sql"
  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    "--stdin"\
    "--stdin-filename=${db_filename}"\
  )
  
  debug "adapter_args=${adapter_args[@]}"
  debug "restic_args=${restic_args[@]}"

  local cmd
  if [[ -z ${DB_DATABASE:-""} ]]; then
    info "no database specified, backing up all databases"
    cmd="pg_dumpall"
  else
    info "will backup database ${DB_DATABASE}"
    adapter_args+=(${DB_DATABASE})
    cmd="pg_dump"
  fi

  $cmd ${adapter_args[@]} | restic ${restic_args[@]} backup
}

restore_pg () {
  call create_pg_option_file
  local option_file="${RETURN_VALUE}"

  if [[ "${MODE}" == "files" ]]; then
    not_is_force &&\
      call_silent pg_isready --passfile=${option_file} &&\
      exception "on mode=files, it is definitely not recommended to do a restore while the database is running, either shutdown the database first, or try with --force to ignore this warning" 50 4
    restore_fs
    return ${?}
  fi

  local adapter_args=(\
    ${ADAPTER_ARGS[@]} \
    "--passfile=${option_file}"\
  )

  local db_filename="${DB_DATABASE:-"database"}.sql"
  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    "--path=/${db_filename}"\
  )
  
  debug "adapter_args=${adapter_args[@]}"
  debug "restic_args=${restic_args[@]}"

  restic ${restic_args[@]} dump "${SNAPSHOT_ID}" "${db_filename}" | pg_restore ${adapter_args[@]}
}

############
# Mongo
####

# Validate env and variables
validate_config_mongo() {
  validate_db_mode_dependencies "mongosh" "mongodump" "mongorestore"
  
  [[ "${FORCE}" == "1" ]] && return 0

  # [[ -z "${DB_MONGO_PASSWORD:-}" ]] \
    # && exception "missing DB_MONGO_PASSWORD environment variable, or force with -f" 64
  [[ -z "${DB_MONGO_URI:-}" ]] \
    && exception "missing DB_MONGO_URI environment variable, or force with -f" 64

  return 0
}

# To avoid password prompt or password diffusion in the process list, we create an option file
# return location of file
create_mongo_option_file() {
  tmp=$(mktemp)
  chmod +600 "${tmp}"
  # echo -ne "password: "${DB_MONGO_PASSWORD}"\nuri: "${DB_MONGO_URI}"" > "${tmp}"
  echo -ne "uri: "${DB_MONGO_URI}"" > "${tmp}"


  info "created mongo option file"

  if is_debug; then
    debug "mongo option file location: ${tmp}"
    debug "\t┌─────────────────────────────"
    cat $tmp | while read -r line; do
      debug "\t│ $(echo ${line})" # | sed -e 's/^password:.*$/password: ******/g')" # sed to mask password
    done
    debug "\t└─────────────────────────────"
  fi

  RETURN_VALUE="${tmp}"

  return 0
}

check_mongo_connexion () {
  call_silent mongosh --quiet --eval "JSON.stringify(db.serverStatus())" "${DB_MONGO_URI}"
  return ${?}
}

lock_mongo () {
  data=$(mongosh --quiet --eval "db.fsyncLock()" "${DB_MONGO_URI}" 2> /dev/null)
  debug "lock_mongo result: ${data}"
  echo "$data" | grep -q "\"ok\" : 1"
  return ${?}
}

unlock_mongo () {
  data=$(mongosh --quiet --eval "db.fsyncUnlock()" "${DB_MONGO_URI}" 2> /dev/null)
  debug "unlock_mongo result: ${data}"
  echo "$data" | grep -q "\"ok\" : 1"
  return ${?}
}

backup_mongo () {
  call create_mongo_option_file
  local option_file="${RETURN_VALUE}"

  if [[ "${MODE}" == "files" ]]; then
    local connected="0"
    check_mongo_connexion && connected="1" || connected="0"
    not_is_force &&\
      [[ "${connected}" == "1" ]] &&\
      exception "on mode=files, it is definitely not recommended to do a restore while the database is running, either shutdown the database first, or try with --force to ignore this warning" 50 4

    if [[ "${connected}" == "1" ]]; then 
      [[ ${DB_LOCK} == "1" ]] && lock_mongo
    fi

    backup_fs
    ret=${?}
    
    if [[ "${connected}" == "1" ]]; then 
      [[ ${DB_LOCK} == "1" ]] && unlock_mongo
    fi

    return ${ret}
  fi

  local adapter_args=(\
    ${ADAPTER_ARGS[@]} \
    "--archive"
    "--config=${option_file}"\
  )

  if (( ${SYSLOG_LEVEL} >= 6 )) && [[ ! " ${adapter_args[*]} " =~ " --verbose " ]]; then
    adapter_args+=("--verbose")
  fi

  if (( ${SYSLOG_LEVEL} <= 4 )) && [[ ! " ${adapter_args[*]} " =~ " --quiet " ]]; then
    adapter_args+=("--quiet")
  fi
  
  local db_filename="${DB_DATABASE:-"database"}.tar"
  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    "--stdin"\
    "--stdin-filename=${db_filename}"\
  )
  
  debug "adapter_args=${adapter_args[@]}"
  debug "restic_args=${restic_args[@]}"

  mongodump ${adapter_args[@]} | restic ${restic_args[@]} backup
}

restore_mongo () {
  call create_pg_option_file
  local option_file="${RETURN_VALUE}"

  if [[ "${MODE}" == "files" ]]; then
    local connected="0"
    check_mongo_connexion && connected="1" || connected="0"
    not_is_force &&\
      [[ "${connected}" == "1" ]] &&\
      exception "on mode=files, it is definitely not recommended to do a restore while the database is running, either shutdown the database first, or try with --force to ignore this warning" 50 4
    restore_fs
    return ${?}
  fi

  local adapter_args=(\
    ${ADAPTER_ARGS[@]} \
    "--archive"
    "--config=${option_file}"\
  )

  if (( ${SYSLOG_LEVEL} >= 6 )) && [[ ! " ${adapter_args[*]} " =~ " --verbose " ]]; then
    adapter_args+=("--verbose")
  fi

  if (( ${SYSLOG_LEVEL} <= 4 )) && [[ ! " ${adapter_args[*]} " =~ " --quiet " ]]; then
    adapter_args+=("--quiet")
  fi

  local db_filename="${DB_DATABASE:-"database"}.tar"
  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    "--path=/${db_filename}"\
  )

  restic ${restic_args[@]} dump "${SNAPSHOT_ID}" "${db_filename}" | mongorestore ${adapter_args[@]}
}

############
# Common
####

# arg1=client command, arg2=restore command, arg3=backup command
validate_db_mode_dependencies() {
  if [[ "${MODE}" == "utility" ]]; then
    debug $(command -v "${2}")
    debug $(command -v "${3}")
    if [ ! -x "$(command -v "${2}")" ] || [ ! -x "$(command -v "${3}")" ]; then
      warn "${2} or ${3} is not installed, fallback to mode='files'"
      MODE="files"
    fi
  fi

  if [[ "${MODE}" == "files" ]]; then
    debug $(command -v "${1}")
    if [[ "${DB_LOCK}" == "1" ]] && [ ! -x "$(command -v "${1}")" ]; then
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
    && exception "missing --snapshot-id|-s option or SNAPSHOT_ID environment variable, 'latest' is a valid snaphotId value" 64

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
      --snapshot-id=*|--snapshotid=*)
        SNAPSHOT_ID=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      -s|--snapshot-id|--snapshotid)
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
      --fs-relative)
        shift
        FS_RELATIVE="1"
        ;;
      --fs-root=*|--fsroot=*)
        FS_ROOT=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      --fs-root|--fsroot)
        shift
        FS_ROOT="$1"
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
        is_force || warn 'compatibility with this kind of output is not guaranteed yet'
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
  -s id, --snapshot-id=id          use a specific snapshot (restore action only), "latest" is a valid value
  -t tag, --tag=tag               filer using tag (or tags, option can be used multiple time)
  --no-clean                      prevent the cleaning after all actions (and act as a dry-run for prune action)
  --fs-root                       check FS_ROOT
  --fs-relative                   check FS_RELATIVE
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
    * FS_ROOT: the root directory to backup from or restore to
    * FS_RELATIVE: backup option, default to 0, if enabled, will not store the whole path in the archive. If this option is not enable, on restore FS_ROOT needs to be set to /, otherwise a backup of "/dir1/dir2/" will be restored like "/dir1/dir2/dir1/dir2/

  - MySQL/Mongo/PG:
    * WAIOB_MODE: can be "files" or "utility", default to "utility", "utility" uses mongodump/mongorestore, and "files" backup database directory files. "files" is not compatible with DB_DATABASE, DB_TABLES, DB_COLLECTIONS...
    * WAIOB_DB_LOCK: enable by default '1', disable to '0', with mode="files" it is strongly advised lock files to prevent data loss during backup (no effect for mode="utility")
    * FS_ROOT: required only for mode=files, the root directory is necessary

  - MySQL/PG:
    * DB_CONFIG_HOST: the database host, default to database type default
    * DB_CONFIG_PORT: the database port, default to database type default
    * DB_CONFIG_USER: the database username, default to database type default
    * DB_CONFIG_PASSWORD: the database password, default to database type default
    * DB_DATABASE: the database to backup, if you want to backup all databases, pass '-- --all-databases' at the end of the command, or '-- --databases DB1 DB2 DB3'
    * DB_TABLES: list of tables to backup, by default all tables are backed up
    
  - Mongo:
    * DB_MONGO_URI: uri, like mongodb://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]
    * DB_MONGO_PASSWORD: the database password (@todo, for now put it in DB_MONGO_URI)

  - Other optional envs:
    * WAIOB_SYSLOG_FACILITY: define facility for syslog, default to local0
    * WAIOB_SYSLOG_LEVEL: define logging level, default to 5 "notice" (0=emergency, 1=alert, 2=crit, 3=error, 4=warning, 5=notice, 6=info, 7=debug), --verbose override the level to 7
    * WAIOB_RESTIC_REPOSITORY_VERSION: default to 2 (restic >=v0.14), repository version
    * WAIOB_DISABLE_AUTO_CLEAN: disabled by default, each action trigger an auto-clean of old snapshots if there is some retention policy, set to 1 to disable it by default, can still be enable afterwards with --clean
    * WAIOB_RETENTION_POLICY: define retention policy, default to none, if some tags have been defined, they will be used and only the snapshot with the same tags may be removed. An exemple: "hourly=24 daily=7 weekly=5 monthly=12 yearly=10 tag=manual last=5", this will keep the latest backup for each hour in the last 24h, the last backup of each day in the last 7 days, the last backup each week in the last 5 weeks, last backup per month for a year, and the last backup of each year for 10 years, it also keep all backups with the tag "manual" and ensure the last 5 backups are also kept.

Examples:
  wik-aio-backup backup fs
  wik-aio-backup backup fs --no-clean --tag=2022 --tag=app --tag=manual-backup
  wik-aio-backup backup fs -t 2022 -t manual-backup -t app --no-clean --dry-run --verbose
  wik-aio-backup backup fs -t 2022 -t manual-backup -t app --no-clean --exclude="node_modules"
  wik-aio-backup backup mysql -t 2022 -t manual-backup -t db --dry-run -- -C --add-drop-database
  wik-aio-backup backup pg -t db:pg -- --clean
  wik-aio-backup list mysql -t=2022 --no-clean
  wik-aio-backup restore mysql -s 123456 --no-clean
  wik-aio-backup prune mysql --exclude-tag=periodic-backup
  wik-aio-backup forget mysql -t 2021
  wik-aio-backup forget mysql -s 123456

Recommendation:
  MongoDB
    When backuping large collections
      wik-aio-backup backup mongo --mode=files

    When backuping all databases (recommended)
      wik-aio-backup backup mongo -- --oplog
      wik-aio-backup restore mongo -- --oplogReplay

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
is_force() { [[ "${FORCE}" != "1" ]] && return 0 || return 1; }
not_is_force() { [[ "${FORCE}" != "1" ]] && return 1 || return 0; }

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