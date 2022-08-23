export STATS_COMPLETED=0
export STATS_FAILED=0

test_suite() {
  local specs="$(find "${SCRIPT_DIR:-"."}/specs" -maxdepth 1 -type f -name '*.spec.sh' -print)"
  for file in ${specs}; do
    source $file
  done
}

success () { logc "\033[1m\033[32m" 5 "$(repl "  " $((describe_level)))✔︎ " $@; }
failure () { logc "\033[1m\033[31m" 5 "$(repl "  " $((describe_level)))✘ " $@; }

describe() {
  export describe_level=${describe_level:-0}
  local msg="${1}"
  (( describe_level > 0 )) && msg="$(repl "  " ${describe_level})${msg}"
  logc "\033[1m" 5 "${msg}"
  describe_level=$((describe_level+1))
  ${@:2}
  local result=$?
  describe_level=$((describe_level-1))
  return $result
}

it() {
  local out; local err; local ret;
  set +e; 
  eval "$({ err=$({ out=$(${@:2}); ret=$?; } 2>&1; declare -p out ret >&2); declare -p err; } 2>&1)"
  set -e
  [[ $ret == "0" ]] && {
    STATS_COMPLETED=$((STATS_COMPLETED+1))
    success ${1}
  } || {
    STATS_FAILED=$((STATS_FAILED+1))
    failure ${1}
  }
  
  if [[ ! -z "$out" ]]; then
    [[ "${SHOW_TEST_STDOUT}" == "1" ]] && while IFS=  read -r line; do logc "\033[2m" 5 "$(repl "  " ${describe_level})\t${line}"
    done < <(printf '%s\n' "$out")
  fi

  if [[ ! -z "$err" ]]; then
    [[ "${SHOW_TEST_STDERR}" == "1" ]] && while IFS=  read -r line; do logc "\033[2m\033[33m" 5 "$(repl "  " ${describe_level})\t${line}"
    done < <(printf '%s\n' "$err")
  fi
}

show_summary() {
  success "${STATS_COMPLETED} tests completed"
  failure "${STATS_FAILED} tests failed"
}