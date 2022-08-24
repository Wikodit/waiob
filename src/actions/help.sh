help () {
  cat <<EOF
Wikodit AIO Backup, simplifies backup through restic.

It handles the restic repository initialization, as well as easy restore and easy backup of a variety of sources. It locks database and can be used to backup them using utility of fs

Supported backup adapters:

* MySQL database
* PostgreSQL database
* MongoDB database
* Filesystem

Usage:
  wik-aio-backup <action> [adapter] [options] [restic_additional_args] [ -- [adapter_additional_args]]

  ? [] denotes optional

  "<action>" can be :
    * backup - launch the backup, this command will also clean old backups if a retention policy has been set in the env.
    * restore - restore a specified snapshots
    * list - list all available snapshots (can use --tags to filter)
    * prune - forget all backups depending on the retention policy (do not clean anything if no retention policy)
    * forget - remove some snapshots

  "[adapter]" can be 'mysql', 'pg', 'mongo', 'fs'

Options:
  -h, --help                      show brief help
  -a adapter, --adapter=adapter   can be 'mysql', 'pg', 'mongo', 'fs'
  -f, --force                     less safe, but force some actions even if not entirely possible, and avoid some checks
  -m mode, --mode=mode         can be 'files' or 'utility', default to 'utility' (no effect for 'fs' adapter). Utility uses mongodump, mysqldump, ... while 'files' backup database files. FS_ROOT is required with 'files' option
  -s id, --snapshot-id=id          use a specific snapshot (restore action only), "latest" is a valid value
  -t tag, --tag=tag               filer using tag (or tags, option can be used multiple time)
  --no-clean                      prevent the cleaning after all actions (and act as a dry-run for prune action)
  --fs-root                       check FS_ROOT
  --fs-relative                   check FS_RELATIVE
  --no-db-lock                    when using mode=files, disable the database lock (hot backup), may result in data lost if the database is in use. This can be useful to backup a database that is not running and thus not reachable
  --clean                         trigger the cleaning after all action (or act as a dry-run for prune action), for use with WAIOB_DISABLE_AUTO_CLEAN env variable
  -d, --debug                     set the logging level to debug (see WAIOB_SYSLOG_LEVEL)
  -v, --verbose                   set the logging level to info (see WAIOB_SYSLOG_LEVEL)
  --log-level=level               set the logging level (see WAIOB_SYSLOG_LEVEL)
  --json                          output json instead of human readable output
  -*, --*                         all other restic available options
  -- *                            all other adapter available options (ex: mysqldump additional options if adapter is mysql)

  Note: `=` is optional in options and can be replaced by the next argument

Environment:

  Note: those are considered permanent config options, and should not change through time

  - Required:
    * AWS_ACCESS_KEY_ID: The S3 storage key id
    * AWS_SECRET_ACCESS_KEY: The S3 storage secret id
    * RESTIC_PASSWORD: An encryption password to write and read from the restic repository
    * RESTIC_REPOSITORY: The repository to store the snapshosts, exemple: s3:s3.gra.perf.cloud.ovh.net/backups/my-namespace/mysql
    * RESTIC_COMPRESSION: set compression level (repository v2), "auto", "max", "off"
    * RESTIC_\*: all other Restic possible env variables
    * WAIOB_ADAPTER: can be
      - mysql - require mysqldump/mysql
      - pg - require pg_dump/pg_restore
      - mongo - require mongodump/mongorestore
      - fs

  - Recommended:
    * TAGS: list of tags to filter snapshots (ex: TAG="tag1 tag2")
  
  - FileSystem (FS):
    * FS_ROOT: the root directory to backup from or restore to
    * FS_RELATIVE: backup option, default to 0, if enabled, will not store the whole path in the archive. If this option is not enable, on restore FS_ROOT needs to be set to /, otherwise a backup of "/dir1/dir2/" will be restored like "/dir1/dir2/dir1/dir2/

  - MySQL/Mongo/PG:
    * WAIOB_MODE: can be "files" or "utility", default to "utility", "utility" uses mongodump/mongorestore, and "files" backup database directory files. "files" is not compatible with DB_DATABASE, DB_TABLES, DB_COLLECTIONS...
    * WAIOB_DB_LOCK: enable by default '1', disable to '0', with mode="files" it is strongly advised lock files to prevent data loss during backup (no effect for mode="utility")
    * FS_ROOT: required only for mode=files, the root directory is necessary

  - MySQL/PG:
    * DB_CONFIG_HOST: the database host, default to database type default
    * DB_CONFIG_PORT: the database port, default to database type default
    * DB_CONFIG_USER: the database username, default to database type default
    * DB_CONFIG_PASSWORD: the database password, default to database type default
    * DB_DATABASE: the database to backup, if you want to backup all databases, pass '-- --all-databases' at the end of the command, or '-- --databases DB1 DB2 DB3'
    * DB_TABLES: list of tables to backup, by default all tables are backed up
    
  - Mongo:
    * DB_MONGO_URI: uri, like mongodb://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[database][?options]]
    * DB_MONGO_PASSWORD: the database password (@todo, for now put it in DB_MONGO_URI)

  - Other optional envs:
    * WAIOB_SYSLOG_FACILITY: define facility for syslog, default to local0
    * WAIOB_SYSLOG_LEVEL: define logging level, default to 5 "notice" (0=emergency, 1=alert, 2=crit, 3=error, 4=warning, 5=notice, 6=info, 7=debug), --verbose override the level to 7
    * WAIOB_RESTIC_REPOSITORY_VERSION: default to 2 (restic >=v0.14), repository version
    * WAIOB_DISABLE_AUTO_CLEAN: disabled by default, each action trigger an auto-clean of old snapshots if there is some retention policy, set to 1 to disable it by default, can still be enable afterwards with --clean
    * WAIOB_RETENTION_POLICY: define retention policy, default to none, if some tags have been defined, they will be used and only the snapshot with the same tags may be removed. An exemple: "hourly=24 daily=7 weekly=5 monthly=12 yearly=10 tag=manual last=5", this will keep the latest backup for each hour in the last 24h, the last backup of each day in the last 7 days, the last backup each week in the last 5 weeks, last backup per month for a year, and the last backup of each year for 10 years, it also keep all backups with the tag "manual" and ensure the last 5 backups are also kept.

Examples:
  wik-aio-backup backup fs
  wik-aio-backup backup fs --no-clean --tag=2022 --tag=app --tag=manual-backup
  wik-aio-backup backup fs -t 2022 -t manual-backup -t app --no-clean --dry-run --verbose
  wik-aio-backup backup fs -t 2022 -t manual-backup -t app --no-clean --exclude="node_modules"
  wik-aio-backup backup mysql -t 2022 -t manual-backup -t db --dry-run -- -C --add-drop-database
  wik-aio-backup backup pg -t db:pg -- --clean
  wik-aio-backup list mysql -t=2022 --no-clean
  wik-aio-backup restore mysql -s 123456 --no-clean
  wik-aio-backup prune mysql --exclude-tag=periodic-backup
  wik-aio-backup forget mysql -t 2021
  wik-aio-backup forget mysql -s 123456

Recommendation:
  MongoDB
    When backuping large collections
      wik-aio-backup backup mongo --mode=files

    When backuping all databases (recommended)
      wik-aio-backup backup mongo -- --oplog
      wik-aio-backup restore mongo -- --oplogReplay

Author:
  Wikodit - Jeremy Trufier <jeremy@wikodit.fr>
EOF
}