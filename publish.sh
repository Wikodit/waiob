#!/usr/bin/env bash

image="registry.cluster.wik.cloud/utils/wik-aio-backup"

majorVersion="0"
minorVersion="2"
patchVersion="0"

channel="latest"

tags=(
  "pg15"
  "mysql8"
  "mongo6"
)

tag () {
  docker image tag "${image}:${channel}" "${image}:${1}"
  docker push "${image}:${1}"

  echo "Pushed ${image}:${1}"
}

publish_all_tags () {
  tag "${majorVersion}"
  tag "${majorVersion}.${minorVersion}"
  tag "${majorVersion}.${minorVersion}.${patchVersion}"

  tagsSize=${#tags[@]}

  for (( i=0; i<${tagsSize}; i++ )); do
    tag "${majorVersion}-${tags[$i]}"
    tag "${majorVersion}.${minorVersion}-${tags[$i]}"
    tag "${channel}-${tags[$i]}"
    tag "${tags[$i]}"
  done
}

build_and_publish () {
  docker build "${image}:${channel}" .
  docker push "${image}:${channel}"
  echo "Pushed ${image}:${channel}"

  publish_all_tags
}

build_and_publish $@