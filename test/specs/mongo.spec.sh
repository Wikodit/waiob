#!/usr/bin/env bash

####################################################################################################
# Mongo Tests
#-----------------------------

test_mongo() {
  export mongod_pid=""

  prepare() {
    export mongo_dbpath="/datas/mongo"

    # ENV
    export RESTIC_REPOSITORY="$(mktemp -d)"
    export RESTIC_PASSWORD="$(echo $RANDOM)"
    export WAIOB_MODE="utility"
    export FS_ROOT="${mongo_dbpath}"
    export FS_RELATIVE="1"
    export DB_MONGO_URI="mongodb://127.0.0.1:27017"

    # Some factories
    export factory_mongo_tag="$(echo $RANDOM)"

    create_db
  }

  teardown() {
    [[ -d "${RESTIC_REPOSITORY}" ]] && rm -Rf "${RESTIC_REPOSITORY}"
    remove_db
  }

  start_db() {
    [[ ! -z "${mongod_pid}" ]] && return 0
    mongod --dbpath="${mongo_dbpath}" &> /dev/null & mongod_pid="$!"
    sleep 1
  }

  stop_db() {
    [ -z "${mongod_pid:-}" ] && return 0
    kill "${mongod_pid:-}" || echo 'unable to kill mongo, already killed'
    sleep 1
    mongod_pid=""
  }

  create_db() {
    # Start mongo server
    mkdir -p "${mongo_dbpath}"
    start_db
  }

  remove_db() {
    # Kill mongo server
    stop_db
    rm -Rf "${mongo_dbpath}"
  }

  backup() {
    mongoimport "${SCRIPT_DIR}/datas/mongo/sales.json"
    export factory_mongo_sales_count="$(query_sales_count)"
    
    ${cmd} backup mongo -d -t $factory_mongo_tag || throw "backup failed"
  }

  restore() {
    remove_db || throw "unable to remove db"
    create_db || throw "unable to create virgin db"
    
    if [[ WAIOB_MODE == "files" ]]; then
      stop_db || throw "unable to stop db"
    fi

    ${cmd} restore mongo -f -s latest -t $factory_mongo_tag || throw "restore failed"
    
    if [[ WAIOB_MODE == "files" ]]; then
      start_db || throw "unable to start db"
    fi

    sales_count="$(query_sales_count)"
    expect_to_be "${sales_count}" "${factory_mongo_sales_count:-5000}"
  }

  # --- Helper methods

  query_sales_count() {
    echo "$(mongosh --quiet --eval "JSON.stringify(db.sales.countDocuments())" | jq .)"
  }

  # --- Test suite

  test_mongo_common() {
    it "should backup" backup
    it "should restore" restore
  }

  test_mongo_utility_mode() {
    export WAIOB_MODE="utility"
    test_mongo_common
  }

  test_mongo_files_mode() {
    export WAIOB_MODE="files"
    test_mongo_common
  }

  prepare
  describe "- with mode utility" test_mongo_utility_mode
  teardown

  prepare
  describe "- with mode files" test_mongo_files_mode
  teardown
}

describe "MongoDB" test_mongo