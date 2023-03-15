# Backup entrypoint
backup() {
  call validate_config_${ADAPTER}
  call prepare_restic_args
  call ensure_repository true
  call "backup_${ADAPTER}" && info "backup done" || exception "backup failed, enable verbose with -v or debug with -d" $? 2
  if [[! "$WAIOB_DISABLE_AUTO_CLEAN" -eq 1 ]]; then
    call prune --last=1
  fi
}
