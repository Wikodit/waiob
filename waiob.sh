#!/usr/bin/env bash

set -euo pipefail
# set -x # uncomment for xtrem debugging with high cafeine level requirement

export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export SRC_DIR="${SRC_DIR:-"${SCRIPT_DIR}/src"}"
export LIB_DIR="${LIB_DIR:-"${SCRIPT_DIR}/lib"}"

source "${SRC_DIR}/main.sh"