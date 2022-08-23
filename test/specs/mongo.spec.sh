#!/usr/bin/env bash

####################################################################################################
# Mongo Tests
#-----------------------------

test_mongo() {
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

    # Start mongo server
    mkdir -p "${mongo_dbpath}"
    mongod --dbpath="${mongo_dbpath}" &> /dev/null & export mongod_pid="$!"
    sleep 2
  }

  teardown() {
    [[ -d "${factory_workdir:-""}" ]] && rm -Rf "${factory_workdir}"

    # Kill mongo server
    kill -0 "$mongod_pid" && kill "$mongod_pid"
    sleep 2
    rm -Rf "${mongo_dbpath}"
  }

  backup() {
    mongoimport "${SCRIPT_DIR}/datas/mongo/sales.json"
    export factory_mongo_sales_count="$(query_sales_count)"
    
    ${cmd} backup mongo -d -t $factory_mongo_tag || throw "backup failed"
  }

  restore() {
    ${cmd} restore mongo -s latest -t $factory_mongo_tag || throw "restore failed"
    
    sales_count="$(query_sales_count)"
    
    expect_to_be "${sales_count}" "${factory_mongo_sales_count:-5000}"
  }

  # --- Helper methods

  query_sales_count() {
    echo "$(mongosh --quiet --eval "JSON.stringify(db.sales.countDocuments())" | jq .)"
  }

  # --- Test suite

  test_mongo_utility_mode() {
    export WAIOB_MODE="utility"
    it "should backup" backup
    it "should restore" restore
  }

  test_mongo_files_mode() {
    export WAIOB_MODE="files"
    it "should backup" backup
    it "should restore" restore
  }

  prepare
  describe "- with mode utility" test_mongo_utility_mode
  teardown

  prepare
  describe "- with mode files" test_mongo_files_mode
  teardown
}

describe "MongoDB" test_mongo