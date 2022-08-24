# Restore entrypoint
restore () {
  [[ -z "$SNAPSHOT_ID" ]] \
    && exception "missing --snapshot-id|-s option or SNAPSHOT_ID environment variable, 'latest' is a valid snaphotId value" 64

  call validate_config_${ADAPTER}
  call prepare_restic_args
  call ensure_repository
  call "restore_${ADAPTER}" && info "restore done" || exception "restore failed, enable verbose with -v or debug with -d" $? 2
}