export STATS_COMPLETED=0
export STATS_FAILED=0

test_suite() {
  local specs="$(find "${SPECS_DIR:-"./test/specs"}" -maxdepth 1 -type f -name '*.spec.sh' -print)"
  for file in ${specs}; do
    debug "spec found: $file"
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

# deprecated but some pretty good tricks there to keep
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
  
  if [[ "${SHOW_TEST_STDOUT}" == "1" ]]; then
    if [[ ! -z "$out" ]]; then
      while IFS=  read -r line; do logc "\033[2m" 5 "$(repl "  " ${describe_level})\t${line}"
      done < <(printf '%s\n' "$out")
    fi
  fi

  if [[ "${SHOW_TEST_STDERR}" == "1" ]]; then
    if [[ ! -z "$err" ]]; then
      while IFS=  read -r line; do logc "\033[2m\033[31m" 5 "$(repl "  " ${describe_level})\t${line}"
      done < <(printf '%s\n' "$err")
    fi
  fi
}

show_summary() {
  success "${STATS_COMPLETED} tests completed"
  failure "${STATS_FAILED} tests failed"
}

# Todo: find why it freezes the process
# it() {
#   local ret;
#   local out;
  
#   # Fails should be capture but not critical
#   set +e; 

#   run()(set -o pipefail;"$@" 2>&1>&3|sed $'s,.*,\e[31m&\e[m,'>&2)3>&1
  
#   # Execute command, and colorise stdout line and stderr lines using logc
#   # just save everything into a variable to show it after success
#   if [[ "${SHOW_TEST_STDERR}" == "1" ]] && [[ "${SHOW_TEST_STDOUT}" == "1" ]]; then
#     out="$(run "${@:2}" 2>&1)"
#   elif [[ "${SHOW_TEST_STDERR}" == "1" ]]; then
#     out="$(run "${@:2}" > /dev/null 2>&1)"
#   elif [[ "${SHOW_TEST_STDOUT}" == "1" ]]; then
#     out="$(run "${@:2}" 2>&1)"
#   else
#     out="$(run "${@:2}" &> /dev/null)"
#   fi
#   # local out="$(${@:2} 2> >(while read line; do
#   #   [[ "${SHOW_TEST_STDERR}" == "1" ]] && echo -e "\033[31m${line}"
#   # done))"

#   ret=$?

#   # Fails should now be critical
#   set -e

#   # Show the success / failure message
#   [[ $ret == "0" ]] && {
#     STATS_COMPLETED=$((STATS_COMPLETED+1))
#     success ${1}
#   } || {
#     STATS_FAILED=$((STATS_FAILED+1))
#     failure ${1}
#   }

#   # Show logs
#   if [[ ! -z "$out" ]]; then
#     while IFS=  read -r line; do
#       logc "\033[2m" 5 "$(repl "  " ${describe_level})\t${line}"
#     done < <(printf '%s\n' "$out")
#   fi
# }
