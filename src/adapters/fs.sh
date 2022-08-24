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