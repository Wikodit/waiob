# Fetch and treat cli args
fetch_args () {
  local args=${@}
  while test $# -gt 0; do
    case "$1" in
      -h|--help)
        ACTION="help"
        shift
        ;;
      help|backup|restore|list|prune|forget)
        ACTION="$1"
        shift
        ;;
      mysql|pg|fs|mongo)
        ADAPTER="$1"
        shift
        ;;
      --adapter=*)
        ADAPTER=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      -a|--adapter)
        shift
        ADAPTER="$1"
        shift
        ;;
      --snapshot-id=*|--snapshotid=*)
        SNAPSHOT_ID=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      -s|--snapshot-id|--snapshotid)
        shift
        SNAPSHOT_ID="$1"
        shift
        ;;
      --tag=*)
        TAGS+=(`echo "$1" | sed -e 's/^[^=]*=//g'`)
        shift
        ;;
      --mode=*)
        DB_BACKUP_MODE=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      --no-db-lock)
        DB_LOCK="0"
        shift
        ;;
      -f|--force)
        FORCE="1"
        shift
        ;;
      --mode|-mode)
        shift
        MODE="$1"
        shift
        ;;
      --fs-relative)
        shift
        FS_RELATIVE="1"
        ;;
      --fs-root=*|--fsroot=*)
        FS_ROOT=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      --fs-root|--fsroot)
        shift
        FS_ROOT="$1"
        shift
        ;;
      -t|--tag)
        shift
        TAGS+=("$1")
        shift
        ;;
      # --exclude-tag=*)
      #   export EXCLUDED_TAGS+=(`echo "$1" | sed -e 's/^[^=]*=//g'`)
      #   shift
      #   ;;
      # --exclude-tag)
      #   shift
      #   export EXCLUDED_TAGS+=("$1")
      #   shift
      #   ;;
      --no-clean|--clean)
        AUTO_CLEAN=`[[ ${AUTO_CLEAN} != "1" && "$1" == "--clean" || "$1" != "--no-clean" ]] && echo "1" || echo "0"`
        shift
        ;;
      --verbose|-v)
        SYSLOG_LEVEL=6
        shift
        ;;
      --debug|-d)
        SYSLOG_LEVEL=7
        shift
        ;;
      --log-level=*)
        SYSLOG_LEVEL=(`echo "$1" | sed -e 's/^[^=]*=//g'`)
        shift
        ;;
     --log-level)
        shift
        SYSLOG_LEVEL="$1"
        shift
        ;;
      --json)
        is_force || warn 'compatibility with this kind of output is not guaranteed yet'
        # @todo This check should go somewhere else, disabling it because does not need it right now
        # if [ -x "$(command -v jq)" ]; then
        RESTIC_ARGS+=("--json")
        # else
        #   warn 'jq is not installed, json output will not be available'
        # fi
        shift
        ;;
      --)
        shift
        ADAPTER_ARGS=($@)
        break
        ;;
      *)
        RESTIC_ARGS+=("$1")
        shift
        ;;
    esac
  done

  debug "Command: ${args}"
}