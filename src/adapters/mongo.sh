############
# Mongo
####

source "${SRC_DIR}/adapters/fs.sh"

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
  call create_mongo_option_file
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