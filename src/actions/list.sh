# List snapshots
list () {
  call prepare_restic_args
  call restic "${PREPARED_RESTIC_ARGS[@]}" snapshots
}