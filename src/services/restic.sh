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