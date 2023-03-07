# Forget password using retention policies
prune () {
  call prepare_restic_args
  call ensure_repository

  local restic_args=(\
    ${PREPARED_RESTIC_ARGS[@]}\
    ${WAIOB_RETENTION_POLICY[@]/#/--keep-}\
  )

  debug "restic_args=${restic_args[@]}"

  call restic "${restic_args[@]}" forget
}