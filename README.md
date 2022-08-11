# Wikodit All-In-One Backup

## General informations

Wikodit AIO Backup, simplifies backup through restic.

It handles the restic repository initialization, as well as easy restore and easy backup of a variety of sources.

Supported backup sources:

* MySQL database
* PostgreSQL database
* MongoDB database
* Filesystem

## Usage

### Docker basic usage

The `ENTRYPOINT` defaults to `wik-aio-backup` script.

You should specific the command and option depending on the action you want to perform.

This suppose, a `./wik-aio-backup.env` file exists and is correctly filled with the required environment variables.


```
docker run --rm -ti --env-file ./wik-aio-backup.env wik-aio-backup <command> [-- <options>]
```

**example:**

```
docker run --rm -ti --env-file ./wik-aio-backup.env wik-aio-backup backup
```

## Available commands

### `backup`

Launch the backup, this command will also clean old backups if a retention policy has been set in the env.

**Options**

* `--no-clean` - Prevent the forget of old backups using retention policy, by default if there is no retention policy, old backup will not be removed

**Required options**

### `list`

List all available snapshots

### `restore`

Restore a specified snapshots.

**Options**

* `snapshotId` - Required, the snapshot id found with the `list` action

**Exemple**

```
docker run --rm -ti --env-file ./wik-aio-backup.env wik-aio-backup restore -- 12345678
```

## Environment variables

### Required variables

All `restic` env variables are supported.

For an S3 storage, following is recommended:

* `RESTIC_PASSWORD`: An encryption password to write and read from the restic repository
* `AWS_ACCESS_KEY_ID`: The S3 storage key id
* `AWS_SECRET_ACCESS_KEY`: The S3 storage secret id
* `RESTIC_REPOSITORY`: The repository to store the snapshosts, exemple: `s3:s3.gra.perf.cloud.ovh.net/backups/my-namespace/mysql`

### Sources variables

#### For MySQL

* `DB_HOST`: the mysql host, default to mysql default
* `DB_PORT`: the mysql port, default to mysql default
* `DB_USERNAME`: the mysql username, default to mysql default
* `DB_PASSWORD`: the mysql password, default to mysql default
* `DB_DATABASES`: databases list to backup (separated by spaces), default to all-databases if not specified
* `DB_TABLES`: backup specific tables (separated by spaces), `DB_DATABASES` should only contain one database
