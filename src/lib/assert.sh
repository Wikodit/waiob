expect_file_to_have_content(){
  local content="$(cat ${1})"
  [[ "${content}" == "${2}" ]] || throw "file content differs, expected \"${2}\", got \"${content}\""
}

expect_to_be() {
  [[ "${1}" == "${2}" ]] || throw "expected \"${2}\", got \"${1}\""
}