repl() { local ts=$(printf "%${2}s"); printf %s "${ts// /$1}"; }
is_debug() { (( "${SYSLOG_LEVEL}" == "7" )) && return 0 || return 1; }
is_force() { [[ "${FORCE}" != "1" ]] && return 0 || return 1; }
not_is_force() { [[ "${FORCE}" == "1" ]] && return 0 || return 1; }

call() {
  local callee="${1}"
  shift
  local callee_args="${@}"
  debug "${callee}: start, args: [${@}]"
  $callee $callee_args
  local result=$?
  debug "${callee}: end"
  return $result
}

call_silent() {
  if is_debug; then
    call ${@}
  else
    call ${@} &> /dev/null
  fi

  local result=$?
  return $result
}

call_silent_err() {
  if is_debug; then
    call ${@}
  else
    call ${@} 2> /dev/null
  fi

  return $?
}