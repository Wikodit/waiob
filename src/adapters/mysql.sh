############
# MySQL
####

source "${SRC_DIR}/adapters/fs.sh"

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
  
  return $?
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

  restic ${restic_args[@]} dump "${SNAPSHOT_ID}" "${db_filename}" | mysql ${adapter_args[@]}
}