set -euo pipefail
# set -x # uncomment for xtrem debugging with high cafeine level requirement

source "${SRC_DIR}/includes.sh"

# Launcher
main () {
  fetch_args $@

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

  if [[ ! -z "${ADAPTER}" ]]; then
    [ -x "${SRC_DIR}/adapters/${ADAPTER}.sh" ] && source "${SRC_DIR}/adapters/${ADAPTER}.sh" || exception "no adapter found"
  fi

  [ -x "${SRC_DIR}/actions/${ACTION}.sh" ] && source "${SRC_DIR}/actions/${ACTION}.sh" || exception "no action found"
  
  call "${ACTION}"
}

# Launch the script
main $@