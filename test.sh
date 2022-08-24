#!/usr/bin/env bash

set -euo pipefail

trap cleanup EXIT

####################################################################################################
# Env variables
#-----------------------------
export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export TEST_DIR="${SCRIPT_DIR}/test"
export FACTORY_DIR="${TEST_DIR}/factories"
export SPECS_DIR="${TEST_DIR}/specs"
export LIB_DIR="${SCRIPT_DIR}/lib"

export cmd="${WAIOB_CMD:-"waiob"}"

export SYSLOG_FACILITY="${SYSLOG_FACILITY:-"local0"}"
export SYSLOG_PREFIX="${SYSLOG_PREFIX:-0}"
export SYSLOG_LEVEL="${SYSLOG_LEVEL:-"5"}"
export WAIOB_ADAPTER="${WAIOB_ADAPTER:-"all"}"

export SHOW_TEST_STDOUT="${SHOW_TEST_STDOUT:-}"
export SHOW_TEST_STDERR="${SHOW_TEST_STDERR:-}"

####################################################################################################
# Dependencies
#-----------------------------

source "${LIB_DIR}/helpers.sh"
source "${LIB_DIR}/logger.sh"
source "${LIB_DIR}/exception.sh"
source "${LIB_DIR}/test.sh"
source "${LIB_DIR}/assert.sh"

####################################################################################################
# Main Block
#-----------------------------

main() {
  describe "\033[4mTESTS:" test_suite
  echo -e ""
  describe "\033[4mSUMMARY:" show_summary
}

cleanup() {
  teardown
}

####################################################################################################
# Launcher
#-----------------------------

# Fetch and treat cli args
fetch_args () {
  local args=${@}
  while test $# -gt 0; do
    case "$1" in
      mysql|pg|fs|mongo|all)
        WAIOB_ADAPTER="$1"
        shift
        ;;
      -h|--help)
        help
        shift
        ;;
      --adapter=*)
        WAIOB_ADAPTER=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      -a|--adapter)
        shift
        WAIOB_ADAPTER="$1"
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
      --show-test-stdout)
        SHOW_TEST_STDOUT="1"
        shift
        ;;
      --show-test-stderr)
        SHOW_TEST_STDERR="1"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  if (( ${SYSLOG_LEVEL} >= 6 )); then
    SHOW_TEST_STDOUT="${SHOW_TEST_STDOUT:-"1"}"
    SHOW_TEST_STDERR="${SHOW_TEST_STDERR:-"1"}"
  else
    SHOW_TEST_STDOUT="${SHOW_TEST_STDOUT:-"0"}"
    SHOW_TEST_STDERR="${SHOW_TEST_STDERR:-"0"}"
  fi

  debug "Command: ${args}"
}

help () {
  cat <<EOF
Wikodit AIO Backup, Test Tool

used to validate behavior of waiob.

Usage:
  ./test.sh [options]

  recommended to run on docker : 
    docker build -f test.dockerfile -t waiob:test . && docker run --rm -ti waiob:test --show-test-stderr

Options:
 (some have their ENV variable counterpart)

  -h, --help                      show brief help
  -a adapter, --adapter=adapter   test only a specific adapter (WAIOB_ADAPTER=*)
  -d, --debug                     set the logging level to debug (SYSLOG_LEVEL=7)
  -v, --verbose                   set the logging level to info (SYSLOG_LEVEL=6)
  --log-level=level               set the logging level (SYSLOG_LEVEL), default to 5 "notice" (0=emergency, 1=alert, 2=crit, 3=error, 4=warning, 5=notice, 6=info, 7=debug)
  --with-log-prefix               by default log prefix with date is hidden
  --log-facility                  by default local0, relevant only when not used with TTY
  --show-test-stdout              show the test logs, hidden by default
  --show-test-stderr              show the test logs, hidden by default

Author:
  Wikodit - Jeremy Trufier <jeremy@wikodit.fr>
EOF
}

fetch_args $@
main

####################################################################################################
