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