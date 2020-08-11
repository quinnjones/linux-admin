#!/bin/env bash

# defaults

DEBUG=0
VERBOSE=0

BACKUPDIR=/backup
BASEDIR=default
MAX_DAYS=10

RSYNC_OPTIONS=( "-alRxz"
                "--fake-super"
                "--delete"
                "--delete-excluded"
              )

DEFAULT_DIRS=( "/boot"
               "/etc"
               "/root"
               "/var"
             )

PROGNAME=$(basename $0)

function std_debug
{
    if [[ "$DEBUG" != "0" ]]; then
        echo "$@"
    fi
}

function std_err
{
    echo "$@"
}

function verbose
{
    if [[ "$VERBOSE" != "0" ]]; then
        echo "$@"
    fi
}

function rotatedirs
{
    local basedir=$1
    local end=$2

    verbose "### Rotating backups in $basedir ###"

    # remove oldest copy
    std_debug rm -Rf "$basedir.$end"
    rm -Rf "$basedir.$end"

    # +1 each remaining folder
    while (( $end > 0 )); do
        let older=end--
        std_debug mv "$basedir.$end" "$basedir.$older"
        mv "$basedir.$end" "$basedir.$older"
    done

    # duplicate end (.1) to make new copy (.0)
    std_debug cp -al "$basedir.1" "$basedir.0"
    cp -al "$basedir.1" "$basedir.0"

    # even if $basedir.1 doesn't exist, make sure $basedir.0 does
    std_debug mkdir -p "$basedir.0"
    mkdir -p "$basedir.0"

    # set timestamp so we know when this copy was made
    std_debug touch "$basedir.0"
    touch "$basedir.0"
}

function localSync
{
    local host=$1;    shift
    local basedir=$1; shift
    local end=$1;     shift

    rotatedirs "$basedir/$host" "$end"

    for dir in $@; do
        verbose "Syncing $host:$dir"
        std_debug rsync ${RSYNC_OPTIONS[@]} $host:$dir "$basedir/$host.0/"
        rsync ${RSYNC_OPTIONS[@]} $dir "$basedir/$host.0/"
    done

    verbose "Done sync'ing $host"
}

function remoteSync
{
    local host=$1;    shift
    local basedir=$1; shift
    local end=$1;     shift

    rotatedirs "$basedir/$host" "$end"

    for dir in $@; do
        verbose "Syncing $host:$dir"
        std_debug rsync ${RSYNC_OPTIONS[@]} $host:$dir "$basedir/$host.0/"
        rsync ${RSYNC_OPTIONS[@]} $host:$dir "$basedir/$host.0/"
    done

    verbose "Done sync'ing $host"
}

function copyLocalKconfig
{
    local host=$1; shift
    local basedir=$1; shift

    local target="$basedir/$host.0/usr/src/linux/"

    mkdir -p "$target"

    modprobe -q configs
    gzip -dc /proc/config.gz > "$target/kernel-config"
}

function copyRemoteKconfig
{
    local host=$1; shift
    local basedir=$1; shift

    local target="$basedir/$host.0/usr/src/linux/"

    mkdir -p "$target"

    ssh "$host" "modprobe -q configs; cat /proc/config.gz" | gzip -dc > "$target/kernel-config"
}

function helpmsg
{
    cat <<EOF

$PROGNAME -h "hostname" dir1 ...
$PROGNAME dir1 ...

Try --man to see a complete manual

EOF
}

function manpage
{
    cat <<EOF

NAME

    $PROGNAME - pull backups from remote systems

SYNOPSIS

    $PROGNAME -h <hostname> dir1 ...
    $PROGNAME dir1 ...

DESCRIPTION

    Pull a rotating snapshot from "host" to a local directory using
    rsync.

    The latest snapshot directory will end in ".0", the next oldest
    snapshot will end in ".1", etc. The oldest snapshots are deleted
    after a configurable number of snapshots; see the "-d" option.

    A reasonable selection of default rsync options, directories, and
    directory and filename exclusions are already set.  Additions may
    be specified on the command line.

    Directories may be added to the default set as additional command-
    line arguments.

Backup and Base Directories

    The backup dir and base dir are combined into a parent path to the
    snapshot sets. The base dir enables rough partitioning between
    backup sets, for example "home" and "business" sets, or "server"
    and "workstation" sets.

        * The default backup directory is "$BACKUPDIR"
        * The default base directory is "$BASEDIR"
        * The combined parent directory is "$BACKUPDIR/$BASEDIR"

Selecting Directories to Snapshot

    The default set of directories covers the basic configuration
    of a system:

        ${DEFAULT_DIRS[@]}

    Notice that /home is not included. /home is frequently a network-
    mounted filesystem, and including it in the snapshot would be
    redundant.

    Additional directories may be included on the command line as
    arguments.

        $PROGNAME [options] -h hostname /home /srv

Kernel Config

    The running kernel configuration is also copied, if available,
    and written to \$snapshot/usr/src/linux/kernel-config.

Rsync Options

    A reasonable set of options is already configured:

        ${RSYNC_OPTIONS[@]}

    Additional options may be specified using '-r':

        $PROGNAME [other options] -r --exclude-file="exclusions.txt"

OPTIONS

    -b "basedir", --basedir "basedir"
        Set a new "basedir" inside of the backup directory. Defaults
        to "$BASEDIR"

    --backup-dir "backup dir"
        Set an alternate backup directory. Recommended to be a full
        path.  Defaults to "$BACKUPDIR"

    -d "days", --days "days"
        Set maximum number of snapshots to keep. Default is $MAX_DAYS.

    --debug
        Enable debugging output

    --help
        Print a help message

    -h "hostname", --host "hostname"
        Configures the hostname to pull a snapshot from.  If omitted,
	localhost is assumed.

    --local
        Make a snapshot of the local system.  The target directory
        will be creating using the output from "hostname". If an
	alternate name is desired, set it using "-h".

        See --remote

    --man
        Print a comprehensive manual

    -q, --quiet
        Disable as much output as possible

    -r, --rsync-opt
        Pass additional options to rsync.  May be specified multiple
        times

    --remote
        Make a snapshot of a remote system (default).

        See "--local"

    -v, --verbose
        Enable verbose output

EOF

}

backupdir=$BACKUPDIR
basedir=$BASEDIR
days=$MAX_DAYS
dirs=(${DEFAULT_DIRS[@]})
remote=1

while [ "$1" != "" ]; do
    case $1 in
        -b | --basedir   ) shift
                           basedir=$1
                           shift
                           ;;
        --backup-dir     ) shift
                           backupdir=$1
                           shift
                           ;;
        -d | --days      ) shift
                           days=$1
                           shift
                           ;;
        --debug          ) shift
                           DEBUG=1
                           ;;
        --help           ) shift
                           helpmsg
                           exit 0
                           ;;
        -h | --host      ) shift
                           host=$1
                           shift
                           ;;
        --local          ) shift
                           remote=0
			   ;;
        --man            ) shift
                           manpage
                           exit 0
                           ;;
        -q | --quiet     ) shift
                           DEBUG=0
                           VERBOSE=0
                           RSYNC_OPTIONS+=( "-q" )
                           ;;
        -r | --rsync-opt ) shift
                           RSYNC_OPTIONS+=( $1 )
                           shift
                           ;;
        --remote         ) shift
                           remote=1
                           ;;
        -v | --verbose   ) shift
                           VERBOSE=1
                           RSYNC_OPTIONS+=( "-v" )
                           ;;
                       * ) dirs+=( $1 )
                           shift
                           ;;
    esac
done

if [ "$basedir" == "" ]; then
    std_err "Missing basedir (try --help)"
    exit 255
elif [[ ! $days =~ ^[0-9]+ ]]; then
    std_err "Invalid days (try --help)"
    exit 255
elif [ $days -lt 1 ]; then
    std_err "Invalid days, must be greater than zero (try --help)"
    exit 255
fi

if [[ -z $host ]]; then
    host=$(hostname)
fi

if [[ "$remote" == 1 ]]; then
    remoteSync "$host" "$backupdir/$basedir" "$days" ${dirs[@]}
    copyRemoteKconfig "$host" "$backupdir/$basedir"
else
    localSync "$host" "$backupdir/$basedir" "$days" ${dirs[@]}
    copyLocalKconfig "$host" "$backupdir/$basedir"
fi

exit

