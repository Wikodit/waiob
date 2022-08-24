#!/usr/bin/env bash

# Author: Jeremy Trufier <jeremy@trufier.com>

set -euo pipefail
# set -x # uncomment for xtrem debugging with high cafeine level requirement

export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export SRC_DIR="${SRC_DIR:-"${SCRIPT_DIR}/src"}"

############
# DEPENDENCIES
####

source "${SRC_DIR}/env.sh"
source "${SRC_DIR}/services/restic.sh"
source "${SRC_DIR}/services/validators.sh"
source "${SRC_DIR}/fetch_args.sh"
source "${SRC_DIR}/main.sh"

# Usage: 
#   log <level> <message>
#
# exemple:
#   log 3 "this is an error"
#   log 7 "too much verbosity here"
log () {
  local levels=( "emerg"  "alert"  "crit"   "error"  "warn"   "notice" "info"   "debug"  )
  local colors=( "\e[35m" "\e[35m" "\e[35m" "\e[31m" "\e[33m" "\e[39m" "\e[32m" "\e[36m" )

  local level="${1}"
  shift 1;
  local msg="${@}";

  # Silence logging if level to high
  (( "${level}" > "${SYSLOG_LEVEL}" )) && return 0;

  # Redirect to stdout/stderr if in a tty
  if [[ "${IS_IN_TTY}" == "1" ]]; then
    local std="${colors[${level}]}$(date "+%F %T") [${levels[level]:-3}]\t${msg}\e[0m"
    (( "${level}" > "3" )) && echo -e "${std}" || >&2 echo -e "${std}" # stdout or stderr
  fi

  # In any case redirect to logger
  logger -t ${0##*/}[$$] -p "${SYSLOG_FACILITY}.${levels[level]:-3}" "${msg}";
}

# Some logging helpers
debug   () { log 7 $@; }
info    () { log 6 $@; }
notice  () { log 5 $@; }
warn    () { log 4 $@; }
error   () { log 3 $@; }
is_debug() { (( "${SYSLOG_LEVEL}" == "7" )) && return 0 || return 1; }
is_force() { [[ "${FORCE}" != "1" ]] && return 0 || return 1; }
not_is_force() { [[ "${FORCE}" != "1" ]] && return 1 || return 0; }

# Usage: exception <message> <code> <level=3>
exception () {
  log ${3:-3} $1

  # if in terminal, we can show the help
  if tty -s; then
    notice "check help with -h"
    #help
  fi

  exit ${2:-1}
}

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

# Launch the script
fetch_args $@
main