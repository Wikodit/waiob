#!/usr/bin/env bash

####################################################################################################
# MySQL Tests
#-----------------------------

test_mysql() {
  export mysqld_pid_file="/mysqld.pid"

  prepare() {
    export factory_workdir="${WORKDIR:-"$(mktemp -d)"}"
    # unzip -qq -d "${factory_workdir}" "${FACTORY_DIR}/mysql/test_db.zip" &> /dev/null || throw "can't unzip test factory db"
    # export factory_sample="${factory_workdir}/test_db-master/employees.sql"
    export factory_sample="${FACTORY_DIR}/mysql/employees.sql"
  }

  teardown() {
    after || debug "can\'t force after"
    if [ -d "${factory_workdir}" ]; then
      rm -Rf "${factory_workdir}"
    fi
  }

  before() {
    export mysql_dbpath="$(mktemp -d)"

    # ENV
    export RESTIC_REPOSITORY="$(mktemp -d)"
    export RESTIC_PASSWORD="$(echo $RANDOM)"
    export WAIOB_MODE="utility"
    export FS_ROOT="${mysql_dbpath}"
    export FS_RELATIVE="1"

    # Some factories
    export factory_mysql_employees_count="69"
    export factory_mysql_tag="$(echo $RANDOM)"
    export factory_mysql_new_doc_id="999999"
    export factory_mysql_new_doc="{
        emp_no: \"${factory_mysql_new_doc_id}\",
        birth_data: '1964-09-12', first_name: 'John', last_name: 'Wick', gender: 'M', hire_date: '1999-09-09' }
    }"
  }

  after() {
    [[ -d "${RESTIC_REPOSITORY}" ]] && rm -Rf "${RESTIC_REPOSITORY}"
    remove_db
  }

  start_db() {
    debug "start_db"

    if [ -r "${mysqld_pid_file}" ]; then
      local pid="$(cat "${mysqld_pid_file}")"
      if kill -0 "${pid}" &> /dev/null; then
        debug "already running";
        return 0
      fi
    fi

    debug "starting mysqld"
    mysqld --user=root --datadir="${mysql_dbpath}" &> /dev/null &
    echo -n "$!" > "${mysqld_pid_file}"
    sleep 5
  }

  stop_db() {
    debug "stop_db"

    if [ -r "${mysqld_pid_file}" ]; then
      local pid="$(cat "${mysqld_pid_file}")"
      if kill -9 "$pid" &> /dev/null; then
        wait "${pid}" 2>/dev/null
        debug "mysqld exited with status $?";
        rm -f "${mysqld_pid_file}"
        return 0
      fi
    fi

    debug "mysqld is not running"

    return 0
  }

  create_db() {
    debug "create_db"
    rm -Rf "${mysql_dbpath}" # must not exists
    mysqld --initialize-insecure --datadir="${mysql_dbpath}" &> /dev/null || throw "unable to initialize db"
    debug "sql data dir initialized"
    start_db
  }

  remove_db() {
    debug "remove_db"
    # Kill mysql server
    stop_db
    if [ -d "${mysql_dbpath}" ]; then
      rm -Rf "${mysql_dbpath}"
      debug "${mysql_dbpath} removed"
    else
      debug "${mysql_dbpath} already removed"
    fi
  }

  import_seed() {
    debug "seeding..."
    mysql -t < "${factory_sample}" &> /dev/null || throw "unable to import seed"
    debug "seeding completed"
  }

  backup() {
    ${cmd} backup mysql ${WAIOB_EXTRA_ARGS[@]} -t $factory_mysql_tag -- --all-databases || throw "backup failed"
  }

  restore() {
    if [[ "${WAIOB_MODE}" == "files" ]]; then
      stop_db || throw "unable to stop db"
    fi

    ${cmd} restore mysql ${WAIOB_EXTRA_ARGS[@]} -f -s latest -t $factory_mysql_tag || throw "restore failed"
    
    if [[ "${WAIOB_MODE}" == "files" ]]; then
      start_db || throw "unable to start db"
    fi
  }

  # --- Helper methods

  mysql_query() {
    mysqlsh --quiet-start --json -e "print(mysqlx.getSession('localhost/employees').$1)"
  }

  check_same_data() {
    sales_count="$(query_employees_count)"
    expect_to_be "${sales_count}" "${factory_mysql_employees_count}"
  }

  query_employees_count() {
    mysql_query "currentSchema.getTable('employees').count()" | jq -r '.info'
  }

  insert_new_document() {
    local id=$(mysql_query "currentSchema.getTable('employees').count(" | jq -r '.insertedId')
    expect_to_be $id $factory_mysql_new_doc_id
  }

  check_new_document() {
    local id=$(mysql_query "
      db.inventory.findOne({ _id: \"${factory_mysql_new_doc_id}\" })
    " | jq -r '._id')
    expect_to_be $id $factory_mysql_new_doc_id
  }

  # --- Test suite

  test_mysql_simple() {
    create_db
    import_seed
    it "should backup" backup
    remove_db

    create_db
    it "should restore" restore
    it "should have same data" check_same_data
    remove_db
  }

  test_mysql_after_change() {
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

  test_mysql_common() {
    before
    describe "simple backup/restore" test_mysql_simple
    after
    
    # before
    # describe "another backup after data change" test_mysql_after_change
    # after
  }

  prepare
  
  export WAIOB_MODE="utility"
  describe "with mode utility" test_mysql_common
  
  export WAIOB_MODE="files"
  describe "with mode files" test_mysql_common

  teardown
}

[[ "${WAIOB_ADAPTER}" =~ ^(mysql|all)$ ]] && describe "MySQL" test_mysql || debug "skip mysql"