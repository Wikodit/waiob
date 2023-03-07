# logc <color> <level> <message>
#   log "\033[35m" 3 "this is an error"
logc () {
  local levels=( "emerg"  "alert"  "crit"   "error"  "warn"   "notice" "info"   "debug"  )

  local color="${1}"; shift;
  local level="${1}"; shift;
  local msg="${@}";

  # Silence logging if level to high
  (( "${level}" > "${SYSLOG_LEVEL}" )) && return 0;

  # Redirect to stdout/stderr if in a tty
  if [[ $IS_IN_TTY == "1" || ${WAIOB_SYSLOG_FORCE_COLOR:-"0"} == "1" ]]; then
    [[ "${SYSLOG_PREFIX:-"0"}" == "1" ]] && local prefix="$(date "+%F %T") [${levels[level]:-3}]\t"
    local std="${color}${prefix:-""}${msg}\033[0m"
    (( "${level}" > "3" )) && echo -e "${std}" || >&2 echo -e "${std}" # stdout or stderr
  fi

  # In any case redirect to logger
  logger -t ${0##*/}[$$] -p "${SYSLOG_FACILITY}.${levels[level]:-3}" "${msg}";
}

# log <level> <message>
#   log 3 "this is an error"
#   log 7 "too much verbosity here"
log () {
  local colors=( "\033[35m" "\033[35m" "\033[35m" "\033[31m" "\033[33m" "\033[39m" "\033[32m" "\033[36m" )
  logc "${colors[${1}]}" $@
}

# Some logging helpers
debug   () { log 7 $@; }
info    () { log 6 $@; }
notice  () { log 5 $@; }
warn    () { log 4 $@; }
error   () { log 3 $@; }