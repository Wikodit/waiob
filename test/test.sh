#!/usr/bin/env bash

set -euo pipefail

trap cleanup EXIT

####################################################################################################
# Env variables
#-----------------------------

export cmd="${WAIOB_CMD:-"waiob"}"

export SYSLOG_FACILITY="${SYSLOG_FACILITY:-"local0"}"
export SYSLOG_PREFIX="${SYSLOG_PREFIX:-0}"
export SYSLOG_LEVEL="${SYSLOG_LEVEL:-"5"}"

export SHOW_TEST_STDOUT="${SHOW_TEST_STDOUT:-"1"}"
export SHOW_TEST_STDERR="${SHOW_TEST_STDERR:-"1"}"

export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

####################################################################################################
# Dependencies
#-----------------------------

source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/exception.sh"
source "${SCRIPT_DIR}/lib/test.sh"
source "${SCRIPT_DIR}/lib/assert.sh"

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

main

####################################################################################################
