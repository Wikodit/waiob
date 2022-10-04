#!/usr/bin/env bash

####################################################################################################
# pg Tests
#-----------------------------

test_pg() {
  export postgres_pid_file="/postgres.pid"
  export postgres_user="postgres"

  # Path is missing pg binary
  export PATH="/usr/lib/postgresql/14/bin/:${PATH}"

  prepare() {
    export factory_workdir="${WORKDIR:-"$(mktemp -d)"}"
    # unzip -qq -d "${factory_workdir}" "${FACTORY_DIR}/pg/test_db.zip" &> /dev/null || throw "can't unzip test factory db"
    # export factory_sample="${factory_workdir}/test_db-master/employees.sql"
    export factory_sample="${FACTORY_DIR}/pg/employees.sql"
  }

  teardown() {
    after || debug "can\'t force after"
    if [ -d "${factory_workdir}" ]; then
      rm -Rf "${factory_workdir}"
    fi
  }

  before() {
    export pg_dbpath="$(mktemp -d)"

    # ENV
    export RESTIC_REPOSITORY="$(mktemp -d)"
    export RESTIC_PASSWORD="$(echo $RANDOM)"
    export WAIOB_MODE="utility"
    export FS_ROOT="${pg_dbpath}"
    export FS_RELATIVE="1"

    # Some factories
    export factory_pg_db="postgres"
    export factory_pg_employees_count="69"
    export factory_pg_tag="$(echo $RANDOM)"
    export factory_pg_new_doc_id="999999"
    export factory_pg_new_doc="(${factory_pg_new_doc_id},'1964-09-12','John','Wick','M','1999-09-09')"
  }

  after() {
    [[ -d "${RESTIC_REPOSITORY}" ]] && rm -Rf "${RESTIC_REPOSITORY}"
    remove_db
  }

  start_db() {
    debug "start_db"

    if [ -r "${postgres_pid_file}" ]; then
      local pid="$(cat "${postgres_pid_file}")"
      if kill -0 "${pid}" &> /dev/null; then
        debug "already running";
        return 0
      fi
    fi

    debug "starting postgres"
    su "${postgres_user}" -c "postgres -D \"${pg_dbpath}\"" &> /dev/null &
    echo -n "$!" > "${postgres_pid_file}"
    sleep 10
  }

  stop_db() {
    debug "stop_db"

    if [ -r "${postgres_pid_file}" ]; then
      local pid="$(cat "${postgres_pid_file}")"
      if kill -9 "$pid" &> /dev/null; then
        wait "${pid}" 2>/dev/null
        debug "postgres exited with status $?";
        rm -f "${postgres_pid_file}"
        return 0
      fi
    fi

    debug "postgres is not running"

    return 0
  }

  create_db() {
    debug "create_db"
    rm -Rf "${pg_dbpath}" # must not exists
    su "${postgres_user}" -c "initdb -D \"${pg_dbpath}\" --auth-local peer" &> /dev/null || throw "unable to initialize db"
    debug "pg data dir initialized"

    # attempt to avoid perm error
    chown -R "${postgres_user}" "${pg_dbpath}"

    start_db

    grant_root_user_to_db
  }

  remove_db() {
    debug "remove_db"
    # Kill pg server
    stop_db
    if [ -d "${pg_dbpath}" ]; then
      rm -Rf "${pg_dbpath}"
      debug "${pg_dbpath} removed"
    else
      debug "${pg_dbpath} already removed"
    fi
  }

  grant_root_user_to_db() {
    debug "grant_root_user_to_db"
    su "${postgres_user}" -c "createuser -s root"
    #&> /dev/null || throw "unable to give root access to the db"
  }

  import_seed() {
    debug "seeding..."
    psql "${factory_pg_db}" < "${factory_sample}" &> /dev/null || throw "unable to import seed"
    debug "seeding completed"
  }

  backup() {
    ${cmd} backup pg ${WAIOB_EXTRA_ARGS[@]} -t $factory_pg_tag -- --clean || throw "backup failed"
  }

  restore() {
    if [[ "${WAIOB_MODE}" == "files" ]]; then
      stop_db || throw "unable to stop db"
    fi

    ${cmd} restore pg ${WAIOB_EXTRA_ARGS[@]} -f -s latest -t $factory_pg_tag -- ${factory_pg_db} || throw "restore failed"
    
    if [[ "${WAIOB_MODE}" == "files" ]]; then
      start_db || throw "unable to start db"
    fi
  }

  # --- Helper methods

  pg_query() {
    # -q => quiet mode
    # -t => hide columns
    # --csv => better format for scripting
    # -c => command
    psql -tq --csv -c \"$1\" "${factory_pg_db}"
  }

  check_same_data() {
    sales_count="$(query_employees_count)"
    expect_to_be "${sales_count}" "${factory_pg_employees_count}"
  }

  query_employees_count() {
    pg_query "SELECT COUNT(*) FROM employees"
  }

  insert_new_document() {
    local id=$(pg_query "INSERT INTO employees VALUES ${factory_pg_new_doc} RETURNING emp_no")
    expect_to_be $id $factory_pg_new_doc_id
  }

  check_new_document() {
    local id=$(pg_query "SELECT id FROM employees WHERE id=${factory_pg_new_doc_id}")
    expect_to_be $id $factory_pg_new_doc_id
  }

  # --- Test suite

  test_pg_simple() {
    create_db
    import_seed
    it "should backup" backup
    remove_db

    create_db
    it "should restore" restore
    it "should have same data" check_same_data
    remove_db
  }

  test_pg_after_change() {
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

  test_pg_common() {
    before
    describe "simple backup/restore" test_pg_simple
    after

    # before
    # describe "another backup after data change" test_pg_after_change
    # after
  }

  prepare
  
  export WAIOB_MODE="utility"
  export DB_DATABASE="postgres"
  describe "with mode utility, dump postgres database" test_pg_common
  
  export WAIOB_MODE="utility"
  export DB_DATABASE=""
  describe "with mode utility, dump all databases" test_pg_common
  
  export WAIOB_MODE="files"
  describe "with mode files" test_pg_common

  teardown
}

[[ "${WAIOB_ADAPTER}" =~ ^(pg|all)$ ]] && describe "pg" test_pg || debug "skip pg"