export IS_IN_TTY=$(tty -s && echo 1 || echo 0)

export FORCE="0"
export ACTION="help"
export SNAPSHOT_ID="${SNAPSHOT_ID:-""}"
export TAGS=(${TAGS:-})
# export EXCLUDED_TAGS=()
export RESTIC_ARGS=()
export ADAPTER_ARGS=()

export AUTO_CLEAN=`[[ "${WAIOB_DISABLE_AUTO_CLEAN:-"0"}" == "1" ]] && echo "0" || echo "1"`

export SYSLOG_FACILITY="${WAIOB_SYSLOG_FACILITY:-"local0"}"
export SYSLOG_LEVEL="${WAIOB_SYSLOG_LEVEL:-"5"}"

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-""}"
export RESTIC_PASSWORD="${RESTIC_PASSWORD:-""}"
export RESTIC_REPOSITORY_VERSION="${WAIOB_RESTIC_REPOSITORY_VERSION:-"2"}"
export ADAPTER="${WAIOB_ADAPTER:-"fs"}"
export MODE="${WAIOB_MODE:-"utility"}"
export DB_LOCK="${WAIOB_DB_LOCK:-"1"}"

export FS_RELATIVE="${FS_RELATIVE:-0}"
export FS_ROOT="${FS_ROOT:-""}"

export PREPARED_RESTIC_ARGS=()

export RETURN_VALUE=""