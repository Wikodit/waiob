############
# Common
####

# arg1=client command, arg2=restore command, arg3=backup command
validate_db_mode_dependencies() {
  if [[ "${MODE}" == "utility" ]]; then
    debug $(command -v "${2}")
    debug $(command -v "${3}")
    if [ ! -x "$(command -v "${2}")" ] || [ ! -x "$(command -v "${3}")" ]; then
      warn "${2} or ${3} is not installed, fallback to mode='files'"
      MODE="files"
    fi
  fi

  if [[ "${MODE}" == "files" ]]; then
    debug $(command -v "${1}")
    if [[ "${DB_LOCK}" == "1" ]] && [ ! -x "$(command -v "${1}")" ]; then
      exception "${1} is not installed, but needed to acquire a lock, if you really want to backup/restore without lock pass the --no-db-lock option" 64
    fi
  fi
}

# Validate env and variables
validate_config_common() {
  [[ -z "$RESTIC_REPOSITORY" ]] \
    && exception "missing RESTIC_REPOSITORY environment variable" 64
  [[ -z "$RESTIC_PASSWORD" ]] \
    && exception "missing RESTIC_PASSWORD environment variable" 64
  [[ -z "$ADAPTER" ]] \
    && exception "missing -a|--adapter option or WAIOB_ADAPTER environment variable" 64
  return 0
}