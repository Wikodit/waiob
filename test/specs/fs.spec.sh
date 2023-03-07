#!/usr/bin/env bash

####################################################################################################
# FS Tests
#-----------------------------

test_fs() {

  prepare() {
    # Factory
    export factory_workdir="${WORKDIR:-"$(mktemp -d)"}"
    export factory_fs_tag="$(echo $RANDOM)"
    export factory_fs_file1="$(echo $RANDOM)"
    export factory_fs_file1_content="$(echo $RANDOM)"
    export factory_fs_dir1="$(echo $RANDOM)"
    export factory_fs_dir1_file1="${factory_fs_dir1}/$(echo $RANDOM)"
    export factory_fs_dir1_file1_content="$(echo $RANDOM)"

    # ENV
    export RESTIC_REPOSITORY="$(mktemp -d)"
    export RESTIC_PASSWORD="$(echo $RANDOM)"
    export WAIOB_MODE="utility"
  }

  teardown() {
    [[ -d "${factory_workdir:-""}" ]] && rm -Rf "${factory_workdir}"
  }

  backup() {
    export FS_ROOT="${factory_workdir}/original"
    mkdir -p "${FS_ROOT}/${factory_fs_dir1}"

    echo -n "$factory_fs_file1_content" > "${FS_ROOT}/$factory_fs_file1"
    echo -n "$factory_fs_dir1_file1_content" > "${FS_ROOT}/$factory_fs_dir1_file1"

    ${cmd} backup fs ${WAIOB_EXTRA_ARGS[@]} --fs-relative -t $factory_fs_tag || throw "backup failed"
  }

  restore() {
    export FS_ROOT="${factory_workdir}/restored"
    mkdir -p "${FS_ROOT}"

    ${cmd} restore fs ${WAIOB_EXTRA_ARGS[@]} -s latest -t $factory_fs_tag || throw "restore failed"

    expect_file_to_have_content "${FS_ROOT}/${factory_fs_file1}" "${factory_fs_file1_content}"
    expect_file_to_have_content "${FS_ROOT}/${factory_fs_file1}" "${factory_fs_file1_content}"
  }

  prune() {
    ${cmd} prune fs ${WAIOB_EXTRA_ARGS[@]} || throw "prune failed"
  }

  list() {
    last_tag="$(${cmd} list --json -f | jq -r '.[0].tags[0]')"
    expect_to_be "${last_tag}" "${factory_fs_tag}"
  }

  # ---

  test_fs_simple() {
    it "should backup" backup
    it "should list using correct tag" list
    it "should restore" restore
  }

    test_prune() {
    
    prune
    count=$(restic list snapshots | wc -l)

    if [ $count -ne 1 ]
    then
      throw "Erreur : le nombre de snapshots est différent de 1."
    fi

  }

  test_fs_prune() {
    export WAIOB_RETENTION_POLICY='last=1' 

    it "should backup" backup
    it "should backup" backup

    it "should prune" test_prune

  }

  prepare
  describe "- simple backup/restore" test_fs_simple
  describe "prune" test_fs_prune
  teardown
}

[[ "${WAIOB_ADAPTER}" =~ ^(fs|all)$ ]] && describe "FS" test_fs || debug "skip fs"
