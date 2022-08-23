try() {
  [[ $- = *e* ]]
  SAVED_OPT_E=$?
  set +e
}

throw() {
  echo -e "\033[31m${@:-""}\033[0m"
  exit 99
}

catch() {
  export exception_code=$?
  (( $SAVED_OPT_E )) && set +e
  return $exception_code
}

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