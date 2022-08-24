#!/usr/bin/env bash

####################################################################################################
# Mongo Tests
#-----------------------------

test_mongo() {
  export mongod_pid_file="/datas/mongo.pid"

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
    export factory_mongo_new_doc_id="e586882d-c827-4693-9ec9-ba3d80e4c4b4"
    export factory_mongo_new_doc="{
        _id: \"${factory_mongo_new_doc_id}\",
        item: \"canvas\", qty: 100, tags: [\"cotton\"], size: { h: 28, w: 35.5, uom: \"cm\" }
    }"
  }

  teardown() {
    [[ -d "${RESTIC_REPOSITORY}" ]] && rm -Rf "${RESTIC_REPOSITORY}"
    remove_db
  }

  start_db() {
    debug "start_db"

    if [ -r "${mongod_pid_file}" ]; then
      local pid="$(cat "${mongod_pid_file}")"
      if kill -0 "${pid}" &> /dev/null; then
        debug "already running";
        return 0
      fi
    fi

    debug "starting mongod"
    mongod --dbpath="${mongo_dbpath}" &> /dev/null &
    echo -n "$!" > "${mongod_pid_file}"
    sleep 1
  }

  stop_db() {
    debug "stop_db"

    if [ -r "${mongod_pid_file}" ]; then
      local pid="$(cat "${mongod_pid_file}")"
      if kill -9 "$pid" &> /dev/null; then
        wait "${pid}" 2>/dev/null
        debug "mongod exited with status $?";
        rm -f "${mongod_pid_file}"
        return 0
      fi
    fi

    debug "mongod is not running"

    return 0
  }

  create_db() {
    debug "create_db"
    # Start mongo server
    mkdir -p "${mongo_dbpath}"
    start_db
  }

  remove_db() {
    debug "remove_db"
    # Kill mongo server
    stop_db
    if [ -d "${mongo_dbpath}" ]; then
      rm -Rf "${mongo_dbpath}"
      debug "${mongo_dbpath} removed"
    else
      debug "${mongo_dbpath} already removed"
    fi
  }

  import_seed() {
    mongoimport "${FACTORY_DIR}/mongo/sales.json" &> /dev/null || throw "unable to import seed"
  }

  backup() {
    export factory_mongo_sales_count="$(query_sales_count)"
    
    ${cmd} backup mongo ${WAIOB_EXTRA_ARGS[@]} -t $factory_mongo_tag || throw "backup failed"
  }

  restore() {
    if [[ "${WAIOB_MODE}" == "files" ]]; then
      stop_db || throw "unable to stop db"
    fi

    ${cmd} restore mongo ${WAIOB_EXTRA_ARGS[@]} -f -s latest -t $factory_mongo_tag || throw "restore failed"
    
    if [[ "${WAIOB_MODE}" == "files" ]]; then
      start_db || throw "unable to start db"
    fi
  }

  # --- Helper methods

  mongo_query() {
    mongosh --quiet --eval "JSON.stringify($1)"
  }

  check_same_data() {
    sales_count="$(query_sales_count)"
    expect_to_be "${sales_count}" "${factory_mongo_sales_count:-5000}"
  }

  query_sales_count() {
    mongo_query "db.sales.countDocuments()" | jq .
  }

  insert_new_document() {
    local id=$(mongo_query "db.inventory.insertOne(${factory_mongo_new_doc})" | jq -r '.insertedId')
    expect_to_be $id $factory_mongo_new_doc_id
  }

  check_new_document() {
    local id=$(mongo_query "
      db.inventory.findOne({ _id: \"${factory_mongo_new_doc_id}\" })
    " | jq -r '._id')
    expect_to_be $id $factory_mongo_new_doc_id
  }

  # --- Test suite

  test_mongo_simple() {
    create_db
    import_seed
    it "should backup" backup
    remove_db

    create_db
    it "should restore" restore
    it "should have same data" check_same_data
    remove_db
  }

  test_mongo_after_change() {
    create_db
    import_seed
    it "should backup" backup
    it "should be able to write additional data" insert_new_document
    it "should backup again" backup

    remove_db

    create_db
    it "should restore" restore
    it "should have same data" check_same_data
    it "should have additionnal data" check_new_document
    remove_db
  }

  test_mongo_common() {
    prepare
    describe "simple backup/restore" test_mongo_simple
    teardown

    prepare
    describe "another backup after data change" test_mongo_after_change
    teardown
  }

  export WAIOB_MODE="utility"
  describe "- with mode utility" test_mongo_common
  
  export WAIOB_MODE="files"
  describe "- with mode files" test_mongo_common
}

[[ "${WAIOB_ADAPTER}" =~ ^(mongo|all)$ ]] && describe "MongoDB" test_mongo || debug "skip mongo"