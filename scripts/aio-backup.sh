#!/bin/sh

# Author: Jeremy Trufier <jeremy@trufier.com>

set -e

BIN_PATH=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
# PROJECT_NAME=${PWD##*/}

main () {
  [[ -z "$ACTION" ]] \
    && error "No action defined - choose either apply or delete" 64

  if [[ -d "./config/$RELEASE_CONFIG" ]]; then
    for file in ./config/$RELEASE_CONFIG/*; do
      if [[ ${file: -5} == ".yaml" ]]; then
        helm $file
      fi
      if [[ ${file: -3} == ".sh" ]]; then
        ./$file
      fi
    done
  else
    helm "./config/$RELEASE_CONFIG.yaml"
  fi
}

helm () {
  local config_file=$1
  local config_filename=$(basename -- "$config_file")
  local config_dirname=$(dirname -- "$config_file")
  local release_config="${config_file#*/*/}"
  local release_config="${release_config%.*}"

  [[ -f "$config_file" ]] || error "Can't find config: $config_file"

  if [[ -z "${release_config##*/*}" ]]; then
    if [[ -z "$NAMESPACE" ]]; then
      export NAMESPACE=${release_config%%/*}
      export NAMESPACE=${NAMESPACE##*_}
    fi
    export local_config=${release_config#*/}
  else
    export local_config=$release_config
  fi

  # Remove ordering number in front of config file (10_chart-name--name => chart-name--name )
  local local_config="${local_config##*_}"

  if [[ -z "${local_config##*--*}" ]]; then
    export RELEASE_NAME="${local_config#*--}"
  else
    export RELEASE_NAME=$local_config
  fi

  local local_chart_name="${local_config%%--*}"
  local local_chart=""

  for file in ./charts/*
  do
    local base_file=$(basename -- "$file")
    if [[ $base_file == "$local_chart_name"* ]]; then
      local_chart=$file
      break
    fi
  done

  # local local_chart="./charts/${local_config%%--*}"
  [[ -n "$local_chart" ]] || error "Can't find valid chart in: $local_chart"

  # if [[ -f "$local_chart/.unnamespaced" ]]; then
    # local no_namespace=yes
  if [[ -f "$config_dirname/.unnamespaced" ]]; then
    local no_namespace=yes
  elif [[ -z "$NAMESPACE" ]]; then
    local no_namespace=yes
  fi

  # using add_ns, because --namespace does not work correctly on helm
  # See: https://github.com/helm/helm/issues/3553
  if [[ "$no_namespace" ]]; then
    cmd="helm template -f $config_file $HELM_ARGS $RELEASE_NAME $local_chart"
  else
    cmd="helm template --namespace $NAMESPACE -f $config_file $HELM_ARGS $RELEASE_NAME $local_chart"

    if [[ -z "$no_namespace" ]]; then
      cmd="$cmd | $BIN_PATH/add-ns.py $NAMESPACE"
    fi
  fi

  kube_config=$(sh -c "$cmd")
  
  if [ -n "$DRY_RUN" ]; then
    echo "$kube_config"
  else
    if [[ -n "$CONTEXT" ]]; then
      local context_arg="--context=$CONTEXT"
    fi

    if [[ -z "$no_namespace" ]]; then
      local namespace_arg="-n $NAMESPACE"
    fi
  
    if [ "$ACTION" == "apply" ] && [ -z "$no_namespace" ]; then
      local remote_namespace=$(kubectl $context_arg get namespace | tail -n +2 | awk '{ print $1 }' | grep $NAMESPACE)
      if [ -z $remote_namespace ]; then
        kubectl $context_arg create namespace $NAMESPACE
      fi
    fi

    echo "$kube_config" | kubectl $context_arg $ACTION -f -

    if [ -n "$PURGE" ] && [ "$ACTION" == "delete" ]; then
      # error "only available for helm v3 (@todo), everything should have a label with RELEASE_NAME for it to work"
      kubectl $context_arg delete all $namespace_arg -l release=$RELEASE_NAME
    fi
  fi
}

fetch_args () {
  export TAGS=()
  while test $# -gt 0; do
    case "$1" in
      -h|--help)
        show_help
        ;;
      backup|restore|list)
        export ACTION="$1"
        shift
        ;;
      -s)
        shift
        export SNAPSHOT_ID="$1"
        shift
        ;;
      --snapshotId=*)
        export SNAPSHOT_ID=`echo "$1" | sed -e 's/^[^=]*=//g'`
        shift
        ;;
      -t)
        shift
        export TAGS+=("$1")
        shift
        ;;
      --tag=*)
        export TAGS+=(`echo "$1" | sed -e 's/^[^=]*=//g'`)
        shift
        ;;
      --no-clean)
        export NO_CLEAN=1
        shift
        ;;
      --)
        shift
        export ADDITIONAL_ARGS=$@
        break
        ;;
      *)
        FREMAINING_ARG="$1"
        shift
        ;;
    esac
  done
}

show_help () {
  cat <<EOF
Wikodit AIO Backup, simplifies backup through restic.

It handles the restic repository initialization, as well as easy restore and easy backup of a variety of sources.

Supported backup adapters:

* MySQL database
* PostgreSQL database
* MongoDB database
* Filesystem

Usage:
  wik-aio-backup {action} [options]

  "{action}" can be :
    * backup - launch the backup, this command will also clean old backups if a retention policy has been set in the env.
    * prune - prune all backups depending on the retention policy (do not clean anything if no retention policy)
    * list - list all available snapshots (can use --tags to filter)
    * restore - restore a specified snapshots
    * delete - remove some snapshots

Options:
  -h, --help                      show brief help
  -s id, --snapshotId=id          use a specific snapshot (restore action only)
  -t tag, --tag=tag               filer using tag (or tags, option can be used multiple time)--exclude-tag=tag               filer excluding this tag (or tags, option can be used multiple time)
  --no-clean                      prevent the cleaning after all actions (and act as a dry-run for `prune` action)
  --clean                         trigger the cleaning after all action (or act as a dry-run for `prune` action), for use with `NO_DEFAULT_CLEANING` env variable

Environment:

  Note: those are considered permanent config options, and should not change through time

  - Required:
    * `AWS_ACCESS_KEY_ID`: The S3 storage key id
    * `AWS_SECRET_ACCESS_KEY`: The S3 storage secret id
    * `RESTIC_PASSWORD`: An encryption password to write and read from the restic repository
    * `RESTIC_REPOSITORY`: The repository to store the snapshosts, exemple: `s3:s3.gra.perf.cloud.ovh.net/backups/my-namespace/mysql`
    * `RESTIC_\*`: all other Restic possible env variables
    * `WAIOB_ADAPTER`: can be
      - mysql - require mysqldump/mysql
      - pg - require pg_dump/pg_restore
      - mongo - require mongodump/mongorestore
      - fs
  
  - MySQL/Mongo/PG:
    * `DB_HOST`: the database host, default to database type default
    * `DB_PORT`: the database port, default to database type default
    * `DB_USERNAME`: the database username, default to database type default
    * `DB_PASSWORD`: the database password, default to database type default

  - MySQL/PG:
    * `DB_DATABASES`: databases list to backup (separated by spaces), default to all-databases if not specified
    * `DB_TABLES`: backup specific tables (separated by spaces), `DB_DATABASES` should only contain one database
    
  - Mongo:
    * `DB_COLLECTIONS`: which collections to backup (default to all collections)
    * `DB_TABLES`: backup specific tables (separated by spaces), `DB_DATABASES` should only contain one database

Examples:
  wik-aio-backup backup mysql -t 2022 -t manual-backup --no-clean
  wik-aio-backup list mysql -t=2022 --no-clean
  wik-aio-backup restore mysql -s 123456 --no-clean
  wik-aio-backup prune mysql --exclude-tag=periodic-backup
  wik-aio-backup delete mysql -t 2021
  wik-aio-backup delete mysql -s 123456

Author:
  Wikodit - Jeremy Trufier <jeremy@wikodit.fr>
EOF
}

error () {
  echo >&2 $1
  echo "---"
  echo " "
  show_help
  exit ${2:-1}
}


fetch_args $@
main