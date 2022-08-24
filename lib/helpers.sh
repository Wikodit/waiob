repl() { local ts=$(printf "%${2}s"); printf %s "${ts// /$1}"; }
is_debug() { (( "${SYSLOG_LEVEL}" == "7" )) && return 0 || return 1; }